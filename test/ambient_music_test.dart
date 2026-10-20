import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/store.dart';
import 'package:stint/music.dart';
import 'package:stint/timer_music.dart';
import 'package:stint/ui/ambient_mixer.dart';
import 'package:stint/ui/theme.dart';
import 'music_test.dart' show FakeMusicAssets, FakeMusicHost;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('stint/ambient-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FocusMusic music;
  late FakeMusicAssets assets;
  late FakeMusicHost host;

  setUp(() {
    assets = FakeMusicAssets();
    host = FakeMusicHost();
    messenger.setMockMethodCallHandler(channel, host.handle);
    music = FocusMusic(channel: channel, assets: assets);
  });
  tearDown(() {
    music.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'saved levels restore silently and are independent of music volume',
    () async {
      host.ambientLevels['rain'] = .6;
      host.ambientLevels['brown_noise'] = .2;
      await music.load();
      expect(music.ambientLevels, {'rain': .6, 'cafe': 0, 'brown_noise': .2});
      expect(music.ambientPlaying, isFalse);
      expect(assets.loaded, isEmpty);
      await music.setAmbientLevel('cafe', .3);
      expect(music.volume, .35);
      expect(music.ambientPlaying, isFalse);
      expect(assets.loaded, isEmpty);
      expect(() => music.ambientLevels['rain'] = 1, throwsUnsupportedError);
    },
  );

  test(
    'ambience plays alone, layers together, and pauses independently',
    () async {
      await music.load();
      await music.applyAmbientLevels({'rain': .6, 'cafe': .2});
      await music.toggleAmbient();
      expect(music.ambientPlaying, isTrue);
      expect(music.playing, isFalse);
      expect(music.wantsAnyPlayback, isTrue);
      expect(assets.loaded, [
        'assets/music/ambient_rain.wav',
        'assets/music/ambient_cafe.wav',
      ]);
      final data = (host.calls.last.arguments as Map)['data'] as Map;
      expect(data.keys, ['rain', 'cafe']);
      expect(data['rain'], isA<Uint8List>());
      await music.play();
      expect(music.playing, isTrue);
      expect(music.ambientPlaying, isTrue);
      await music.pauseAmbient();
      expect(music.playing, isTrue);
      expect(music.ambientPlaying, isFalse);
      await music.playAmbient();
      await music.pause();
      expect(music.wantsAnyPlayback, isFalse);
    },
  );

  test('starting and pausing a timer controls all configured layers', () async {
    final controller = StintController(
      MemoryWorkspaceStore(),
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    host.followTimer = true;
    host.ambientLevels['rain'] = .4;
    await music.load();
    final coordinator = TimerMusicCoordinator(controller, music);
    addTearDown(coordinator.dispose);
    controller.startTimer();
    await settle();
    expect(music.playing, isTrue);
    expect(music.ambientPlaying, isTrue);
    controller.pauseTimer();
    await settle();
    expect(music.wantsAnyPlayback, isFalse);
    expect(host.calls.last.method, 'fadePause');
    await music.playAmbient();
    controller.startTimer();
    await settle();
    controller.pauseTimer();
    await settle();
    expect(music.ambientPlaying, isFalse);
  });

  test('timer paused while ambience loads cannot start stale audio', () async {
    final controller = StintController(
      MemoryWorkspaceStore(),
      tickAutomatically: false,
    );
    addTearDown(controller.dispose);
    host.followTimer = true;
    host.ambientLevels['rain'] = .4;
    await music.load();
    final coordinator = TimerMusicCoordinator(controller, music);
    addTearDown(coordinator.dispose);
    assets.pending = Completer<ByteData>();
    controller.startTimer();
    controller.pauseTimer();
    assets.pending!.complete(assets.data);
    await settle();
    expect(host.calls.where((call) => call.method == 'play'), isEmpty);
    expect(music.wantsAnyPlayback, isFalse);
  });

  test(
    'profile waits for a pending fade and applies one silent command',
    () async {
      await music.load();
      await music.play();
      host.pendingFade = Completer<void>();
      final pause = music.fadePause();
      final profile = music.applySoundProfile(
        selectedId: 'quiet_keys',
        volume: .2,
        followTimer: true,
        ambientLevels: {'rain': .7},
      );
      host.pendingFade!.complete();
      await pause;
      expect(await profile, isTrue);
      expect(host.calls.last.method, 'applyProfile');
      expect(music.selectedId, 'quiet_keys');
      expect(music.volume, .2);
      expect(music.followTimer, isTrue);
      expect(music.ambientLevels['rain'], .7);
      expect(music.wantsAnyPlayback, isFalse);
    },
  );

  test(
    'invalid levels normalize and native profile failure is observable',
    () async {
      await music.applyAmbientLevels({
        'rain': 8,
        'cafe': double.nan,
        'brown_noise': -2,
      });
      expect(music.ambientLevels, {'rain': 1, 'cafe': 0, 'brown_noise': 0});
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'profile_failed',
          message: 'Unable to apply.',
        );
      });
      expect(
        await music.applySoundProfile(
          selectedId: 'quiet_keys',
          volume: .3,
          followTimer: false,
          ambientLevels: {},
        ),
        isFalse,
      );
      expect(music.error, 'Unable to apply.');
    },
  );

  testWidgets('mixer labels and all levels fit a compact dark window', (
    tester,
  ) async {
    await music.load();
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: stintTheme(Brightness.dark),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AmbientMixer(music: music, initiallyExpanded: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.text('Rain'), findsOneWidget);
    expect(find.text('Café hum'), findsOneWidget);
    expect(find.text('Brown noise'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('ambient-toggle')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('ambient-level-rain')));
    await tester.pumpAndSettle();
    expect(music.ambientLevels['rain'], greaterThan(0));
    await tester.tap(find.byKey(const Key('ambient-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Pause ambience'), findsOneWidget);
    expect(music.playing, isFalse);
    expect(tester.takeException(), isNull);
  });
}
