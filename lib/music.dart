import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Only video identifiers leave this parser; arbitrary URLs are never loaded.
String? youtubeVideoIdFromUrl(String input) {
  try {
    var text = input.trim();
    if (!text.contains('://')) text = 'https://$text';
    final url = Uri.tryParse(text);
    if (url == null ||
        !['https', 'http'].contains(url.scheme) ||
        url.userInfo.isNotEmpty ||
        url.hasPort) {
      return null;
    }
    final host = url.host.toLowerCase();
    final parts = url.pathSegments;
    String? id;
    if (host == 'youtu.be' || host == 'www.youtu.be') {
      if (parts.length == 1) id = parts.single;
    } else if (const {
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'music.youtube.com',
    }.contains(host)) {
      if (url.path == '/watch' && url.queryParametersAll['v']?.length == 1) {
        id = url.queryParameters['v'];
      } else if (parts.length == 2 &&
          ['shorts', 'live', 'embed'].contains(parts.first)) {
        id = parts.last;
      }
    } else if ([
          'youtube-nocookie.com',
          'www.youtube-nocookie.com',
        ].contains(host) &&
        parts.length == 2 &&
        parts.first == 'embed') {
      id = parts.last;
    }
    return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)
        ? id
        : null;
  } on FormatException {
    return null;
  }
}

class MusicTrack {
  const MusicTrack(this.id, this.title, {this.asset, this.youtubeVideoId});
  final String id;
  final String title;
  final String? asset;
  final String? youtubeVideoId;
  bool get isYouTube => youtubeVideoId != null;
}

class FocusMusic extends ChangeNotifier {
  FocusMusic({MethodChannel? channel, AssetBundle? assets})
    : channel = channel ?? const MethodChannel('stint/music'),
      assets = assets ?? rootBundle {
    this.channel.setMethodCallHandler(_handle);
  }
  static const builtIns = [
    MusicTrack(
      'quiet_keys',
      'Quiet Keys',
      asset: 'assets/music/quiet_keys.wav',
    ),
    MusicTrack(
      'warm_drift',
      'Warm Drift',
      asset: 'assets/music/warm_drift.wav',
    ),
    MusicTrack(
      'night_study',
      'Night Study',
      asset: 'assets/music/night_study.wav',
    ),
  ];
  final MethodChannel channel;
  final AssetBundle assets;
  List<MusicTrack> imported = [];
  String selectedId = 'quiet_keys';
  bool playing = false;
  bool starting = false;
  bool busy = false;
  bool followTimer = false;
  double volume = .35;
  String? error;
  bool _disposed = false;
  bool get wantsPlayback => playing || starting;

  List<MusicTrack> get tracks => [...builtIns, ...imported];
  MusicTrack get selected => tracks.firstWhere(
    (track) => track.id == selectedId,
    orElse: () => builtIns.first,
  );

  void _apply(Object? result) {
    if (result is! Map || _disposed) return;
    final entries = result['tracks'];
    if (entries is List) {
      imported = entries
          .whereType<Map>()
          .where((track) => track['id'] is String && track['title'] is String)
          .map(
            (track) => MusicTrack(
              track['id'] as String,
              track['title'] as String,
              youtubeVideoId: track['youtubeVideoId'] is String
                  ? track['youtubeVideoId'] as String
                  : null,
            ),
          )
          .toList();
    }
    final id = result['selectedId'];
    if (id is String && tracks.any((track) => track.id == id)) selectedId = id;
    playing = result['playing'] == true;
    starting = result['starting'] == true;
    if (result['followTimer'] is bool) {
      followTimer = result['followTimer'] as bool;
    }
    if (result['volume'] is num) {
      volume = (result['volume'] as num).toDouble().clamp(0, 1);
    }
  }

  Future<void> _handle(MethodCall call) async {
    if (_disposed) return;
    if (call.method == 'state') {
      _apply(call.arguments);
      if (playing) error = null;
    }
    if (call.method == 'error') {
      playing = false;
      starting = false;
      error = call.arguments is String
          ? call.arguments as String
          : 'Music could not be played.';
    }
    notifyListeners();
  }

  Future<void> _command(String method, [Object? arguments]) =>
      _run(() => channel.invokeMethod<Object?>(method, arguments));

  Future<void> _run(Future<Object?> Function() action) async {
    if (_disposed || busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      _apply(await action());
    } on PlatformException catch (exception) {
      error =
          exception.message ??
          'Music could not be loaded. Try another audio file.';
    } catch (_) {
      error = 'Music is unavailable. Try again.';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> load() => _command('load');
  Future<void> importFiles() => _command('import');
  Future<bool> addYouTube(String url, {String title = ''}) async {
    if (_disposed || busy) return false;
    final videoId = youtubeVideoIdFromUrl(url);
    final name = title.trim();
    if (videoId == null || name.length > 120) {
      error = videoId == null
          ? 'Paste a YouTube link to a single video or live stream.'
          : 'Use a name with 120 characters or fewer.';
      notifyListeners();
      return false;
    }
    await _command('addYouTube', {'videoId': videoId, 'title': name});
    return error == null && selected.youtubeVideoId == videoId;
  }

  Future<void> showYouTube() => _command('showYouTube');
  Future<void> removeYouTube(String id) => _command('removeYouTube', id);
  Future<void> removeCustom(String id) => _command('removeCustom', id);
  Future<void> select(String id) => _command('select', id);
  Future<void> pause() => _command('pause');
  Future<void> fadePause() => _command('fadePause');
  Future<void> setFollowTimer(bool value) => _command('followTimer', value);
  Future<void> play({bool fade = false, bool Function()? shouldPlay}) =>
      _run(() async {
        final track = selected;
        if (shouldPlay != null && !shouldPlay()) return null;
        if (track.asset == null) {
          return channel.invokeMethod<Object?>('play', {
            'id': track.id,
            if (fade) 'fade': true,
          });
        }
        final bytes = await assets.load(track.asset!);
        // A pause or phase change may arrive while an asset is loading.
        if (_disposed || (shouldPlay != null && !shouldPlay())) return null;
        return channel.invokeMethod<Object?>('play', {
          'id': track.id,
          if (fade) 'fade': true,
          'data': bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          ),
        });
      });

  void previewVolume(double value) {
    volume = value.clamp(0, 1);
    notifyListeners();
  }

  Future<void> saveVolume(double value) =>
      _command('volume', value.clamp(0, 1));

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
