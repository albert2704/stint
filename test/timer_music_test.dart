import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';
import 'package:stint/music.dart';
import 'package:stint/timer_music.dart';
import 'music_test.dart' show FakeMusicAssets, FakeMusicHost;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('stint/linked-music-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StintController controller;
  late FocusMusic music;
  late FakeMusicHost host;
  late FakeMusicAssets assets;
  late DateTime now;
  TimerMusicCoordinator? coordinator;

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> connect({bool enabled = true}) async {
    host.followTimer = enabled;
    await music.load();
    coordinator = TimerMusicCoordinator(controller, music);
  }

  List<String> getMethods() => host.calls.map((call) => call.method).toList();

  setUp(() {
    now = DateTime(2026, 10, 8, 10);
    controller = StintController(
      MemoryWorkspaceStore(),
      now: () => now,
      tickAutomatically: false,
    );
    host = FakeMusicHost();
    assets = FakeMusicAssets();
    messenger.setMockMethodCallHandler(channel, host.handle);
    music = FocusMusic(channel: channel, assets: assets);
  });

  tearDown(() {
    coordinator?.dispose();
    coordinator = null;
    music.dispose();
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('restoring a running timer and Follow timer never autoplays', () async {
    controller.startTimer();
    await connect();
    now = now.add(const Duration(seconds: 15));
    controller.tick();
    await settle();
    expect(music.followTimer, isTrue);
    expect(music.playing, isFalse);
    expect(getMethods(), ['load']);
  });

  test('disabled automation preserves independent playback', () async {
    await connect(enabled: false);
    controller.startTimer();
    await settle();
    expect(music.playing, isFalse);
    await music.play();
    controller.pauseTimer();
    controller.selectPhase(TimerPhase.shortBreak);
    await settle();
    expect(music.playing, isTrue);
    expect(getMethods(), ['load', 'play']);
  });

  test(
    'focus and break start, pause, resume and completion control music',
    () async {
      await connect();
      controller.startTimer();
      await settle();
      expect(music.playing, isTrue);
      expect((host.calls.last.arguments as Map)['fade'], isTrue);
      now = now.add(const Duration(seconds: 3));
      controller.pauseTimer();
      await settle();
      expect(music.playing, isFalse);
      expect(getMethods().last, 'fadePause');
      controller.startTimer();
      await settle();
      expect(music.playing, isTrue);
      now = controller.timer.endsAt!;
      controller.tick();
      await settle();
      expect(controller.timer.phase, TimerPhase.shortBreak);
      expect(music.playing, isFalse);
      controller.startTimer();
      await settle();
      expect(music.playing, isTrue);
      now = controller.timer.endsAt!;
      controller.tick();
      controller.startTimer();
      await settle();
      expect(controller.timer.phase, TimerPhase.focus);
      expect(music.playing, isTrue);
    },
  );

  test(
    'manual pause lasts through ticks and preference changes are explicit',
    () async {
      await connect(enabled: false);
      controller.startTimer();
      await music.setFollowTimer(true);
      await settle();
      expect(music.playing, isTrue);
      await music.pause();
      final count = host.calls.length;
      now = now.add(const Duration(minutes: 1));
      controller.tick();
      controller.persist();
      await settle();
      expect(host.calls.length, count);
      expect(music.playing, isFalse);
      await music.play();
      await music.setFollowTimer(false);
      controller.resetTimer();
      await settle();
      expect(music.playing, isTrue);
      expect(host.followTimer, isFalse);
    },
  );

  for (final phase in [TimerPhase.shortBreak, TimerPhase.longBreak]) {
    test('${phase.label} follows start, pause, resume and expiry', () async {
      controller.selectPhase(phase);
      await connect();
      controller.startTimer();
      await settle();
      expect(music.playing, isTrue);
      controller.pauseTimer();
      await settle();
      expect(music.playing, isFalse);
      controller.startTimer();
      await settle();
      expect(music.playing, isTrue);
      now = controller.timer.endsAt!;
      controller.tick();
      await settle();
      expect(controller.timer.running, isFalse);
      expect(music.playing, isFalse);
    });
  }

  test('enabling while a break runs immediately follows it', () async {
    await connect(enabled: false);
    controller.selectPhase(TimerPhase.longBreak);
    controller.startTimer();
    await music.setFollowTimer(true);
    await settle();
    expect(music.playing, isTrue);
    controller.skipToNext();
    await settle();
    expect(controller.timer.running, isFalse);
    expect(music.playing, isFalse);
  });

  test('reset and routine replacement stop linked focus playback', () async {
    await connect();
    controller.startTimer();
    await settle();
    controller.resetTimer();
    await settle();
    expect(music.playing, isFalse);
    controller.startTimer();
    await settle();
    controller.applyRoutine('deep');
    await settle();
    expect(music.playing, isFalse);
    expect(controller.remaining, 50 * 60);
  });

  test(
    'pausing while a built-in loads prevents stale audio from starting',
    () async {
      await connect();
      assets.pending = Completer<ByteData>();
      controller.startTimer();
      expect(music.busy, isTrue);
      controller.pauseTimer();
      assets.pending!.complete(assets.data);
      await settle();
      expect(getMethods().where((method) => method == 'play'), isEmpty);
      expect(music.busy, isFalse);
      expect(music.playing, isFalse);
      controller.startTimer();
      await settle();
      expect(music.playing, isTrue);
    },
  );

  test(
    'resuming during a fade eventually plays the latest timer state',
    () async {
      await connect();
      controller.startTimer();
      await settle();
      host.pendingFade = Completer<void>();
      controller.pauseTimer();
      await settle();
      expect(music.busy, isTrue);
      controller.startTimer();
      host.pendingFade!.complete();
      await settle();
      expect(music.playing, isTrue);
      expect(getMethods(), ['load', 'play', 'fadePause', 'play']);
    },
  );

  test(
    'timer transitions during an import converge after the picker closes',
    () async {
      await connect();
      host.pendingImport = Completer<void>();
      final importing = music.importFiles();
      controller.startTimer();
      controller.pauseTimer();
      host.pendingImport!.complete();
      await importing;
      await settle();
      expect(music.playing, isFalse);
      expect(getMethods(), ['load', 'import']);
    },
  );

  test(
    'playback failure is visible without retrying on countdown ticks',
    () async {
      await connect();
      host.failPlay = true;
      controller.startTimer();
      await settle();
      expect(music.error, contains('could not be played'));
      now = now.add(const Duration(seconds: 5));
      controller.tick();
      await settle();
      expect(getMethods(), ['load', 'play']);
    },
  );

  test(
    'disposing while audio loads cancels the pending automated start',
    () async {
      await connect();
      assets.pending = Completer<ByteData>();
      controller.startTimer();
      coordinator!.dispose();
      coordinator = null;
      assets.pending!.complete(assets.data);
      await settle();
      expect(getMethods(), ['load']);
    },
  );
}
