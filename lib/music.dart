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
  static const ambientLayers = {
    'rain': ('Rain', 'assets/music/ambient_rain.wav'),
    'cafe': ('Café hum', 'assets/music/ambient_cafe.wav'),
    'brown_noise': ('Brown noise', 'assets/music/ambient_brown_noise.wav'),
  };
  final MethodChannel channel;
  final AssetBundle assets;
  List<MusicTrack> imported = [];
  String selectedId = 'quiet_keys';
  bool playing = false;
  bool starting = false;
  bool busy = false;
  bool followTimer = false;
  double volume = .35;
  Map<String, double> _ambientLevels = {
    for (final id in ambientLayers.keys) id: 0,
  };
  bool ambientPlaying = false;
  String? error;
  String? profileWarning;
  bool _disposed = false;
  bool get wantsPlayback => playing || starting;
  bool get wantsAnyPlayback => wantsPlayback || ambientPlaying;
  bool get hasAmbient => _ambientLevels.values.any((level) => level > 0);
  Map<String, double> get ambientLevels => Map.unmodifiable(_ambientLevels);

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
    final levels = result['ambientLevels'];
    if (levels is Map) {
      _ambientLevels = {
        for (final id in ambientLayers.keys)
          id: levels[id] is num && (levels[id] as num).isFinite
              ? (levels[id] as num).toDouble().clamp(0, 1)
              : 0,
      };
    }
    if (result['ambientPlaying'] is bool) {
      ambientPlaying = result['ambientPlaying'] as bool;
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
        final ambientData = await _loadAmbient(_ambientLevels);
        if (_disposed || (shouldPlay != null && !shouldPlay())) return null;
        if (track.asset == null) {
          return channel.invokeMethod<Object?>('play', {
            'id': track.id,
            if (fade) 'fade': true,
            if (ambientData.isNotEmpty) 'ambientData': ambientData,
          });
        }
        final bytes = await assets.load(track.asset!);
        // A pause or phase change may arrive while an asset is loading.
        if (_disposed || (shouldPlay != null && !shouldPlay())) return null;
        return channel.invokeMethod<Object?>('play', {
          'id': track.id,
          if (fade) 'fade': true,
          if (ambientData.isNotEmpty) 'ambientData': ambientData,
          'data': bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          ),
        });
      });

  Map<String, double> _normalizedLevels(Map<String, double> levels) => {
    for (final id in ambientLayers.keys)
      id: (levels[id] ?? 0).isFinite ? (levels[id] ?? 0).clamp(0, 1) : 0,
  };

  Future<Map<String, Uint8List>> _loadAmbient(
    Map<String, double> levels,
  ) async {
    final data = <String, Uint8List>{};
    for (final entry in levels.entries) {
      if (entry.value <= 0) continue;
      final bytes = await assets.load(ambientLayers[entry.key]!.$2);
      data[entry.key] = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
    }
    return data;
  }

  void previewAmbientLevel(String id, double value) {
    if (!ambientLayers.containsKey(id) || !value.isFinite) return;
    _ambientLevels = {..._ambientLevels, id: value.clamp(0, 1)};
    notifyListeners();
  }

  Future<void> setAmbientLevel(String id, double value) async {
    if (!ambientLayers.containsKey(id) || !value.isFinite) return;
    await applyAmbientLevels({..._ambientLevels, id: value.clamp(0, 1)});
  }

  Future<void> applyAmbientLevels(Map<String, double> levels) => _run(() async {
    final normalized = _normalizedLevels(levels);
    final data = ambientPlaying ? await _loadAmbient(normalized) : null;
    if (_disposed) return null;
    return channel.invokeMethod<Object?>('ambientLevels', {
      'levels': normalized,
      'data': ?data,
    });
  });

  Future<void> playAmbient({bool fade = false, bool Function()? shouldPlay}) =>
      _run(() async {
        if (!hasAmbient || (shouldPlay != null && !shouldPlay())) return null;
        final data = await _loadAmbient(_ambientLevels);
        if (_disposed || (shouldPlay != null && !shouldPlay())) return null;
        return channel.invokeMethod<Object?>('ambientPlay', {
          'data': data,
          if (fade) 'fade': true,
        });
      });

  Future<void> pauseAmbient() => _command('ambientPause');
  Future<void> toggleAmbient() =>
      ambientPlaying ? pauseAmbient() : playAmbient();

  /// Applies a complete profile silently as one native transaction. A missing
  /// saved track falls back to Quiet Keys and is reported through profileWarning.
  Future<bool> applySoundProfile({
    required String selectedId,
    required double volume,
    required bool followTimer,
    required Map<String, double> ambientLevels,
  }) async {
    // Stopping a timer can have just started its linked audio fade. Wait for
    // that command to settle before applying the complete sound configuration.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (busy && !_disposed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_disposed) return false;
    if (busy || !volume.isFinite) {
      error = busy
          ? 'Finish the current sound action before applying this profile.'
          : 'This profile has an invalid sound volume.';
      notifyListeners();
      return false;
    }
    var applied = false;
    profileWarning = null;
    await _run(() async {
      final result = await channel.invokeMethod<Object?>('applyProfile', {
        'selectedId': selectedId,
        'volume': volume.clamp(0, 1),
        'followTimer': followTimer,
        'ambientLevels': _normalizedLevels(ambientLevels),
      });
      if (result is Map) {
        applied = true;
        profileWarning = result['profileWarning'] is String
            ? result['profileWarning'] as String
            : null;
      }
      return result;
    });
    return applied && error == null;
  }

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
