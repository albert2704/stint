import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_desk/data/controller.dart';
import 'package:focus_desk/data/store.dart';
import 'package:focus_desk/music.dart';
import 'package:focus_desk/timer_music.dart';
import 'package:focus_desk/ui/music_panel.dart';
import 'music_test.dart' show FakeMusicAssets, FakeMusicHost;

class YouTubeHost extends FakeMusicHost {
  bool starting = false;
  bool failAdd = false;

  @override
  Map<String, Object?> get state => {...super.state, 'starting': starting};

  @override
  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'addYouTube') {
      calls.add(call);
      if (failAdd) {
        throw PlatformException(
          code: 'save_failed',
          message: 'Link could not be saved.',
        );
      }
      final args = call.arguments as Map;
      final videoId = args['videoId'] as String;
      final id = 'youtube_$videoId';
      if (!custom.any((track) => track['id'] == id)) {
        custom.add({
          'id': id,
          'title': (args['title'] as String).isEmpty
              ? 'YouTube video'
              : args['title'] as String,
          'youtubeVideoId': videoId,
        });
      }
      selectedId = id;
      playing = false;
      starting = false;
      return state;
    }
    if (call.method == 'showYouTube') {
      calls.add(call);
      return state;
    }
    if (call.method == 'removeYouTube') {
      calls.add(call);
      final id = call.arguments as String;
      custom.removeWhere(
        (track) => track['id'] == id && track.containsKey('youtubeVideoId'),
      );
      if (selectedId == id) {
        selectedId = 'quiet_keys';
        playing = false;
        starting = false;
      }
      return state;
    }
    if (call.method == 'play' &&
        ((call.arguments as Map)['id'] as String).startsWith('youtube_')) {
      calls.add(call);
      selectedId = (call.arguments as Map)['id'] as String;
      starting = true;
      playing = false;
      return state;
    }
    if (['load', 'pause', 'fadePause', 'select'].contains(call.method)) {
      starting = false;
    }
    return super.handle(call);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const videoId = 'M7lc1UVf-VE';
  const channel = MethodChannel('focus_desk/youtube-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late YouTubeHost host;
  late FocusMusic music;
  late FakeMusicAssets assets;

  setUp(() {
    host = YouTubeHost();
    assets = FakeMusicAssets();
    messenger.setMockMethodCallHandler(channel, host.handle);
    music = FocusMusic(channel: channel, assets: assets);
  });
  tearDown(() {
    music.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> nativeEvent(String method, Object? args) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, args)),
      null,
    );
  }

  test('recognizes video links while dropping unrelated query parameters', () {
    for (final link in [
      'https://www.youtube.com/watch?v=$videoId',
      'https://youtube.com/watch?list=abc&v=$videoId&t=30',
      'https://youtu.be/$videoId?si=abc',
      'www.youtube.com/watch?v=$videoId',
      ' http://m.youtube.com/watch?v=$videoId ',
      'https://music.youtube.com/watch?v=$videoId',
      'https://youtube.com/shorts/$videoId',
      'https://youtube.com/live/$videoId',
      'https://youtube.com/embed/$videoId',
      'https://www.youtube-nocookie.com/embed/$videoId',
    ]) {
      expect(youtubeVideoIdFromUrl(link), videoId, reason: link);
    }
  });

  test(
    'rejects spoofed hosts, credentials, playlists and malformed video links',
    () {
      for (final link in [
        '',
        videoId,
        'not a link',
        'https://youtube.com.evil.example/watch?v=$videoId',
        'https://youtube.com@evil.example/watch?v=$videoId',
        'https://user:pass@youtube.com/watch?v=$videoId',
        'javascript:alert(1)',
        'file:///watch?v=$videoId',
        'https://youtube.com/playlist?list=abc',
        'https://youtube.com/watch?v=$videoId&v=abcdefghijk',
        'https://youtu.be/short',
        'https://youtu.be/$videoId/extra',
        'https://youtube.com/watch?v=aaaaaaaaaaa%22',
        'https://example.com/embed/$videoId',
        'https://[broken',
        'https://youtube.com/watch?v=%FF',
        'https://youtube.com/%FF/watch?v=$videoId',
      ]) {
        expect(youtubeVideoIdFromUrl(link), isNull, reason: link);
      }
    },
  );

  test(
    'saving selects a named link once without fetching an asset or autoplay',
    () async {
      await music.load();
      expect(
        await music.addYouTube(
          'https://youtu.be/$videoId',
          title: ' Evening focus ',
        ),
        isTrue,
      );
      expect(host.calls.last.arguments, {
        'videoId': videoId,
        'title': 'Evening focus',
      });
      expect(music.selected.isYouTube, isTrue);
      expect(music.selected.title, 'Evening focus');
      expect(music.wantsPlayback, isFalse);
      expect(assets.loaded, isEmpty);
      expect(music.tracks.any((track) => track.id == 'quiet_keys'), isTrue);
      await music.addYouTube('https://youtube.com/watch?v=$videoId');
      expect(music.tracks.where((track) => track.isYouTube), hasLength(1));
      await music.showYouTube();
      expect(host.calls.last.method, 'showYouTube');
      expect(music.wantsPlayback, isFalse);
    },
  );

  test('invalid link and name never reach the native host', () async {
    expect(await music.addYouTube('https://example.com/video'), isFalse);
    expect(
      await music.addYouTube('https://youtu.be/$videoId', title: 'a' * 121),
      isFalse,
    );
    expect(host.calls, isEmpty);
    expect(music.error, isNotNull);
  });

  test(
    'YouTube playback can be cancelled while loading and reports native errors',
    () async {
      await music.addYouTube('https://youtu.be/$videoId');
      await music.play();
      expect(host.calls.last.arguments, {'id': 'youtube_$videoId'});
      expect(music.starting, isTrue);
      expect(music.playing, isFalse);
      expect(music.wantsPlayback, isTrue);
      await music.pause();
      expect(music.wantsPlayback, isFalse);
      await music.play();
      await nativeEvent('error', 'This video cannot be embedded.');
      expect(music.starting, isFalse);
      expect(music.playing, isFalse);
      expect(music.error, contains('cannot be embedded'));
      host.playing = true;
      host.starting = false;
      await nativeEvent('state', host.state);
      expect(music.playing, isTrue);
      expect(music.error, isNull);
    },
  );

  test(
    'Follow timer cancels a pending YouTube start when focus pauses',
    () async {
      await music.addYouTube('https://youtu.be/$videoId');
      await music.setFollowTimer(true);
      final controller = DeskController(
        MemoryWorkspaceStore(),
        tickAutomatically: false,
      );
      final coordinator = TimerMusicCoordinator(controller, music);
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      controller.startTimer();
      await settle();
      expect(music.starting, isTrue);
      controller.pauseTimer();
      await settle();
      expect(host.calls.last.method, 'fadePause');
      expect(music.wantsPlayback, isFalse);
      expect(controller.timer.running, isFalse);
    },
  );

  testWidgets(
    'link dialog validates, keeps errors open, and saves a usable source',
    (tester) async {
      await music.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 420, child: MusicPanel(music: music)),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YouTube link…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('youtube-url')),
        'https://example.com',
      );
      await tester.tap(find.text('Save link'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "That doesn't look like a YouTube video or live stream link.",
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('youtube-url')),
        'https://youtu.be/$videoId',
      );
      await tester.enterText(
        find.byKey(const Key('youtube-title')),
        'Evening focus',
      );
      host.failAdd = true;
      await tester.tap(find.text('Save link'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Link could not be saved.'), findsWidgets);
      host.failAdd = false;
      await tester.tap(find.text('Save link'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Evening focus'), findsWidgets);
      expect(find.text('Show player'), findsOneWidget);
      expect(find.byTooltip('Add'), findsOneWidget);
      await tester.tap(find.text('Show player'));
      await tester.pumpAndSettle();
      expect(host.calls.last.method, 'showYouTube');
      expect(music.wantsPlayback, isFalse);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(music.selected.isYouTube, isTrue);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(music.tracks.where((track) => track.isYouTube), isEmpty);
      expect(music.selectedId, 'quiet_keys');
      expect(tester.takeException(), isNull);
    },
  );
}
