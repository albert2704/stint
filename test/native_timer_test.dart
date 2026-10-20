import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';
import 'package:stint/native_timer.dart';
import 'package:stint/music.dart';
import 'music_test.dart' show FakeMusicAssets, FakeMusicHost;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late MemoryWorkspaceStore store;
  late StintController controller;

  setUp(() {
    now = DateTime(2026, 10, 8, 10);
    store = MemoryWorkspaceStore();
    controller = StintController(
      store,
      now: () => now,
      tickAutomatically: false,
    );
  });
  tearDown(() => controller.dispose());

  group('native timer bridge', () {
    const channel = MethodChannel('stint/timer-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late NativeTimerBridge bridge;
    late List<TimerPhase> adjustedPhases;
    late int progressOpened;

    Future<Object?> nativeCall(String method, [Object? arguments]) async {
      final response = await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      );
      return response == null ? null : channel.codec.decodeEnvelope(response);
    }

    Map<Object?, Object?> lastSnapshot() =>
        calls.last.arguments as Map<Object?, Object?>;

    setUp(() {
      calls = [];
      adjustedPhases = [];
      progressOpened = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      bridge = NativeTimerBridge(
        controller,
        channel: channel,
        onAdjust: () async => adjustedPhases.add(controller.timer.phase),
        onProgress: () async => progressOpened++,
      );
    });
    tearDown(() {
      bridge.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });

    test(
      'publishes timer state, avoids duplicate updates, and refreshes',
      () async {
        await messenger.platformMessagesFinished;
        expect(calls.single.method, 'update');
        expect(lastSnapshot(), {
          'remaining': 1500,
          'flowFocus': false,
          'flowElapsedSeconds': 0,
          'continuationNote': '',
          'externalActionBusy': false,
          'totalSeconds': 1500,
          'running': false,
          'hasProgress': false,
          'phase': 'Focus',
          'deadlineMilliseconds': null,
          'sessionId': null,
          'completedSessionId': null,
          'cycleStep': 0,
          'focusMinutes': 25,
          'shortBreakMinutes': 5,
          'longBreakMinutes': 15,
          'appearance': 'system',
          'pendingAction': null,
          'routines': FocusRoutine.builtIns.map((r) => r.toJson()).toList(),
          'activeRoutineId': 'classic',
          'todayCount': 0,
          'dailyGoal': 8,
          'completionCount': 0,
        });
        controller.persist();
        await messenger.platformMessagesFinished;
        expect(calls, hasLength(1));

        controller.startFocus();
        await messenger.platformMessagesFinished;
        expect(lastSnapshot().containsKey('taskTitle'), isFalse);
        expect(lastSnapshot()['running'], true);
        expect(lastSnapshot()['hasProgress'], true);
        expect(lastSnapshot()['sessionId'], controller.timer.sessionId);
        expect(
          lastSnapshot()['deadlineMilliseconds'],
          now.add(const Duration(minutes: 25)).millisecondsSinceEpoch,
        );
        now = now.add(const Duration(seconds: 7));
        controller.tick();
        await messenger.platformMessagesFinished;
        expect(lastSnapshot()['remaining'], 1493);

        final count = calls.length;
        await nativeCall('refresh');
        await messenger.platformMessagesFinished;
        expect(calls, hasLength(count + 1));
        expect(lastSnapshot()['remaining'], 1493);
      },
    );

    test(
      'Flow counts up and accepts only the displayed finish action',
      () async {
        controller.applyMode(FocusMode.flow);
        controller.startTimer();
        final session = controller.timer.sessionId;
        final step = controller.timer.cycleStep;
        now = now.add(const Duration(minutes: 12, seconds: 30));
        controller.tick();
        await messenger.platformMessagesFinished;
        expect(lastSnapshot()['flowFocus'], isTrue);
        expect(lastSnapshot()['flowElapsedSeconds'], 750);
        expect(lastSnapshot()['deadlineMilliseconds'], isNull);
        await nativeCall('finishFlow', {
          'sessionId': 'stale',
          'cycleStep': step,
        });
        expect(controller.workspace.sessions, isEmpty);
        await nativeCall('finishFlow', {
          'sessionId': session,
          'cycleStep': step,
        });
        expect(controller.workspace.sessions.single.seconds, 750);
        expect(controller.timer.running, isFalse);
        expect(controller.remaining, 180);
        await nativeCall('finishFlow', {
          'sessionId': session,
          'cycleStep': step,
        });
        expect(controller.workspace.sessions, hasLength(1));
      },
    );

    test('sleep pauses only Flow focus and note projects to native', () async {
      controller.setContinuationNote('Next: fix login redirect');
      controller.applyMode(FocusMode.flow);
      controller.startTimer();
      now = now.add(const Duration(seconds: 45));
      await nativeCall('systemWillSleep');
      expect(controller.timer.running, isFalse);
      expect(controller.elapsedSeconds, 45);
      now = now.add(const Duration(hours: 2));
      controller.tick();
      expect(controller.elapsedSeconds, 45);
      await messenger.platformMessagesFinished;
      expect(lastSnapshot()['continuationNote'], 'Next: fix login redirect');
      controller.requestMode(FocusMode.pomodoro);
      controller.confirmPending();
      controller.startTimer();
      await nativeCall('systemWillSleep');
      expect(controller.timer.running, isTrue);
    });

    test(
      'a delayed sleep event excludes time while the Mac was asleep',
      () async {
        controller.applyMode(FocusMode.flow);
        controller.startTimer();
        final sleepAt = now.add(const Duration(seconds: 45));
        now = now.add(const Duration(hours: 2));
        controller.tick();
        await nativeCall('systemWillSleep', sleepAt.millisecondsSinceEpoch);
        expect(controller.timer.running, isFalse);
        expect(controller.elapsedSeconds, 45);
      },
    );

    test(
      'Progress entry settles the timer and shares its recorded count',
      () async {
        controller.startFocus();
        now = controller.timer.endsAt!;
        await nativeCall('progress');
        await messenger.platformMessagesFinished;
        expect(progressOpened, 1);
        expect(lastSnapshot()['todayCount'], 1);
        expect(lastSnapshot()['completionCount'], 1);
        expect(controller.workspace.sessions, hasLength(1));
        controller.setDailyGoal(6);
        await messenger.platformMessagesFinished;
        expect(lastSnapshot()['dailyGoal'], 6);
      },
    );

    test(
      'notification count follows the finish day and never counts breaks',
      () async {
        now = DateTime(2026, 10, 8, 23, 50);
        for (final end in [
          DateTime(2026, 10, 8, 10),
          DateTime(2026, 10, 8, 11),
          DateTime(2026, 10, 9, 10),
        ]) {
          controller.workspace.sessions.add(
            FocusSession(
              id: end.toIso8601String(),
              taskTitle: 'Open focus',
              projectName: '',
              seconds: 1500,
              finishedAt: end,
            ),
          );
        }
        controller.persist();
        controller.startFocus();
        await messenger.platformMessagesFinished;
        expect(lastSnapshot()['todayCount'], 2);
        expect(
          lastSnapshot()['completionCount'],
          2,
          reason: 'one saved stint on tomorrow plus this focus',
        );
        controller.adjustCurrent(-20);
        await messenger.platformMessagesFinished;
        expect(
          lastSnapshot()['completionCount'],
          3,
          reason: 'the adjusted focus ends today',
        );
        now = controller.timer.endsAt!;
        controller.tick();
        controller.startTimer();
        await messenger.platformMessagesFinished;
        expect(lastSnapshot()['phase'], 'Short break');
        expect(lastSnapshot()['todayCount'], 3);
        expect(
          lastSnapshot()['completionCount'],
          1,
          reason: 'a break ending at midnight adds nothing',
        );
      },
    );

    test(
      'menu toggle starts and pauses but an expired Pause cannot start a break',
      () async {
        await nativeCall('toggle');
        expect(controller.timer.running, isTrue);
        now = now.add(const Duration(seconds: 10));
        await nativeCall('toggle');
        expect(controller.timer.running, isFalse);
        expect(controller.remaining, 1490);
        now = now.add(const Duration(hours: 1));
        await nativeCall('toggle');
        expect(controller.timer.running, isTrue);
        expect(controller.remaining, 1490);
        now = controller.timer.endsAt!;
        await nativeCall('toggle');
        await messenger.platformMessagesFinished;
        expect(controller.workspace.sessions, hasLength(1));
        expect(controller.timer.phase, TimerPhase.shortBreak);
        expect(controller.timer.running, isFalse);
        expect(controller.remaining, 300);
        expect(lastSnapshot()['phase'], 'Short break');
        expect(lastSnapshot()['running'], false);
      },
    );

    test(
      'adjust settles expiry, notification errors surface, and disposal detaches',
      () async {
        controller.startTimer();
        now = controller.timer.endsAt!;
        await nativeCall('adjust');
        expect(adjustedPhases, [TimerPhase.shortBreak]);
        expect(controller.workspace.sessions, hasLength(1));
        await nativeCall('notificationError', 'Notifications are disabled.');
        expect(controller.notice, 'Notifications are disabled.');
        await nativeCall('notificationError');
        expect(controller.notice, contains('System Settings'));
        await messenger.platformMessagesFinished;

        bridge.dispose();
        final count = calls.length;
        await nativeCall('adjust');
        await nativeCall('toggle');
        expect(adjustedPhases, [TimerPhase.shortBreak]);
        expect(controller.timer.running, isFalse);
        controller.startTimer();
        await messenger.platformMessagesFinished;
        expect(calls, hasLength(count));
      },
    );
  });

  group('shared Stint controls', () {
    const channel = MethodChannel('stint/stint-panel-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late NativeTimerBridge bridge;
    late List<Map<Object?, Object?>> snapshots;
    late int settingsOpened;

    Map<String, Object?> displayedTimer() => {
      'running': controller.timer.running,
      'sessionId': controller.timer.sessionId,
      'cycleStep': controller.timer.cycleStep,
    };

    Future<void> nativeCall(String method, [Object? arguments]) async {
      if (method == 'toggle' && arguments == null) {
        arguments = displayedTimer();
      }
      final response = await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      );
      if (response != null) channel.codec.decodeEnvelope(response);
      await messenger.platformMessagesFinished;
    }

    setUp(() async {
      snapshots = [];
      settingsOpened = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        snapshots.add(call.arguments as Map<Object?, Object?>);
        return null;
      });
      bridge = NativeTimerBridge(
        controller,
        channel: channel,
        onSettings: () async {
          settingsOpened++;
        },
      );
      await messenger.platformMessagesFinished;
    });
    tearDown(() {
      bridge.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });

    test(
      'a stale native Pause cannot start the next interval after Dart already completed',
      () async {
        await nativeCall('toggle');
        final displayedPause = displayedTimer();
        now = controller.timer.endsAt!;
        controller.tick();
        expect(controller.timer.cycleStep, 1);
        expect(controller.timer.running, isFalse);
        await nativeCall('toggle', displayedPause);
        expect(controller.timer.running, isFalse);
        expect(controller.remaining, 300);
        expect(controller.workspace.sessions, hasLength(1));
        await nativeCall('toggle');
        expect(controller.timer.running, isTrue);
        now = now.add(const Duration(seconds: 5));
        await nativeCall('toggle');
        expect(controller.timer.running, isFalse);
        expect(controller.remaining, 295);
      },
    );

    test(
      'stale step, session and malformed toggle contexts are harmless',
      () async {
        final displayedStart = displayedTimer();
        controller.jumpToStep(2);
        await nativeCall('toggle', displayedStart);
        expect(controller.timer.running, isFalse);
        await nativeCall('toggle');
        final oldSession = displayedTimer();
        controller.resetTimer();
        controller.startTimer();
        await nativeCall('toggle', oldSession);
        expect(controller.timer.running, isTrue);
        final deadline = controller.timer.endsAt;
        for (final invalid in <Object>[
          'pause',
          {},
          {'running': true, 'cycleStep': 2},
          {'running': true, 'cycleStep': 2, 'sessionId': 42},
          {
            'running': 'yes',
            'cycleStep': 2,
            'sessionId': controller.timer.sessionId,
          },
          {
            'running': true,
            'cycleStep': 2.0,
            'sessionId': controller.timer.sessionId,
          },
        ]) {
          await nativeCall('toggle', invalid);
        }
        expect(controller.timer.endsAt, deadline);
        expect(controller.timer.running, isTrue);
      },
    );

    test('both surfaces share request, cancel and confirm state', () async {
      await nativeCall('jumpStep', 4);
      expect(controller.timer.cycleStep, 4);
      expect(controller.pendingAction, isNull);
      await nativeCall('toggle');
      now = now.add(const Duration(minutes: 2));
      final deadline = controller.timer.endsAt;
      await nativeCall('skip');
      expect(controller.timer.cycleStep, 4);
      expect(snapshots.last['pendingAction'], {
        'kind': 'skip',
        'title': 'Switch to short break?',
        'confirmLabel': 'Switch',
        'targetStep': 5,
      });
      await nativeCall('toggle');
      expect(controller.timer.endsAt, deadline);
      await nativeCall('cancel');
      expect(controller.pendingAction, isNull);
      expect(snapshots.last['pendingAction'], isNull);
      expect(controller.timer.endsAt, deadline);
      controller.requestJumpTo(7);
      await messenger.platformMessagesFinished;
      expect((snapshots.last['pendingAction'] as Map)['targetStep'], 7);
      await nativeCall('confirm');
      expect(controller.timer.cycleStep, 7);
      expect(snapshots.last['cycleStep'], 7);
      expect(snapshots.last['phase'], 'Long break');
      expect(controller.workspace.sessions, isEmpty);
      expect(controller.pendingAction, isNull);
      await nativeCall('settings');
      expect(settingsOpened, 1);
    });

    test(
      'rhythm and reset actions request confirmation and publish settings',
      () async {
        await nativeCall('toggle');
        await nativeCall('applyRoutine', 'deep');
        expect(controller.activeRoutineId, 'classic');
        expect(controller.pendingAction?.routineId, 'deep');
        await nativeCall('confirm');
        expect(snapshots.last['focusMinutes'], 50);
        expect(snapshots.last['shortBreakMinutes'], 10);
        expect(snapshots.last['longBreakMinutes'], 30);
        expect(snapshots.last['activeRoutineId'], 'deep');
        controller.updateSettings(
          focus: 50,
          shortBreak: 10,
          longBreak: 30,
          appearance: 'dark',
        );
        await messenger.platformMessagesFinished;
        expect(snapshots.last['appearance'], 'dark');
        await nativeCall('toggle');
        await nativeCall('reset');
        expect(controller.pendingAction?.kind, 'reset');
        await nativeCall('confirm');
        expect(controller.timerHasProgress, isFalse);
        expect(controller.remaining, 3000);
      },
    );

    test(
      'expiry makes a queued confirm harmless and action context starts once',
      () async {
        await nativeCall('toggle');
        final session = controller.timer.sessionId!;
        await nativeCall('jumpStep', 6);
        now = controller.timer.endsAt!;
        await nativeCall('confirm');
        expect(controller.timer.cycleStep, 1);
        expect(controller.pendingAction, isNull);
        expect(snapshots.last['completedSessionId'], session);
        await nativeCall('startNext', {'sessionId': 'old', 'cycleStep': 1});
        await nativeCall('startNext', {'sessionId': session, 'cycleStep': 7});
        expect(controller.timer.running, isFalse);
        await nativeCall('startNext', {'sessionId': session, 'cycleStep': 1});
        expect(controller.timer.running, isTrue);
        expect(snapshots.last['completedSessionId'], isNull);
        await nativeCall('toggle');
        await nativeCall('startNext', {'sessionId': session, 'cycleStep': 1});
        expect(controller.timer.running, isFalse);
        expect(controller.workspace.sessions, hasLength(1));
      },
    );

    for (final focusStep in [0, 2, 4, 6]) {
      test(
        'skipOffered after focus step $focusStep prepares the following focus idle',
        () async {
          controller.applyRoutine('deep');
          controller.jumpToStep(focusStep);
          await nativeCall('toggle');
          final session = controller.timer.sessionId!;
          final deadline = controller.timer.endsAt!;
          now = deadline;
          controller.tick();
          final recorded = controller.workspace.sessions.toList();
          final completedCount = controller.timer.completedCount;
          final context = {'sessionId': session, 'cycleStep': focusStep + 1};

          await nativeCall('skipOffered', context);

          expect(controller.timer.cycleStep, (focusStep + 2) % 8);
          expect(controller.timer.phase, TimerPhase.focus);
          expect(controller.timer.running, isFalse);
          expect(controller.timerHasProgress, isFalse);
          expect(controller.remaining, 50 * 60);
          expect(controller.timer.sessionId, isNull);
          expect(controller.timer.completedSessionId, isNull);
          expect(controller.pendingAction, isNull);
          expect(controller.workspace.sessions, recorded);
          expect(controller.timer.completedCount, completedCount);
          expect(snapshots.last['cycleStep'], (focusStep + 2) % 8);
          expect(snapshots.last['running'], isFalse);
          expect(store.load()!.timer.cycleStep, (focusStep + 2) % 8);

          final after = controller.workspace.encode();
          await nativeCall('skipOffered', context);
          expect(controller.workspace.encode(), after);
        },
      );
    }

    test(
      'skipOffered settles a native-first completion exactly once',
      () async {
        await nativeCall('toggle');
        final session = controller.timer.sessionId!;
        now = controller.timer.endsAt!;
        await nativeCall('skipOffered', {'sessionId': session, 'cycleStep': 1});
        expect(controller.timer.cycleStep, 2);
        expect(controller.timer.running, isFalse);
        expect(controller.workspace.sessions, hasLength(1));
        expect(controller.workspace.sessions.single.id, session);
      },
    );

    test(
      'skipOffered rejects mismatched and stale completion contexts',
      () async {
        await nativeCall('toggle');
        final session = controller.timer.sessionId!;
        now = controller.timer.endsAt!;
        controller.tick();
        final offered = controller.workspace.encode();
        for (final context in [
          {'sessionId': 'old', 'cycleStep': 1},
          {'sessionId': '', 'cycleStep': 1},
          {'sessionId': session, 'cycleStep': 7},
          {'sessionId': session, 'cycleStep': -1},
          {'sessionId': session, 'cycleStep': 8},
        ]) {
          await nativeCall('skipOffered', context);
          expect(controller.workspace.encode(), offered);
        }

        await nativeCall('reset');
        final reset = controller.workspace.encode();
        await nativeCall('skipOffered', {'sessionId': session, 'cycleStep': 1});
        expect(controller.workspace.encode(), reset);
        expect(controller.timer.cycleStep, 1);
        expect(controller.workspace.sessions, hasLength(1));
      },
    );

    test('skipOffered cannot skip a running or paused break', () async {
      await nativeCall('toggle');
      final session = controller.timer.sessionId!;
      now = controller.timer.endsAt!;
      controller.tick();
      final context = {'sessionId': session, 'cycleStep': 1};
      await nativeCall('startNext', context);
      final running = controller.workspace.encode();
      await nativeCall('skipOffered', context);
      expect(controller.workspace.encode(), running);
      now = now.add(const Duration(seconds: 10));
      await nativeCall('toggle');
      final paused = controller.workspace.encode();
      await nativeCall('skipOffered', context);
      expect(controller.workspace.encode(), paused);
      expect(controller.remaining, 290);
      expect(controller.pendingAction, isNull);
      expect(controller.workspace.sessions, hasLength(1));
    });

    test('skipOffered never skips the focus offered after a break', () async {
      controller.jumpToStep(1);
      await nativeCall('toggle');
      final session = controller.timer.sessionId!;
      now = controller.timer.endsAt!;
      controller.tick();
      final offered = controller.workspace.encode();
      await nativeCall('skipOffered', {'sessionId': session, 'cycleStep': 2});
      expect(controller.workspace.encode(), offered);
      expect(controller.timer.cycleStep, 2);
      expect(controller.workspace.sessions, isEmpty);
    });

    test('malformed cycle and notification arguments are ignored', () async {
      final original = controller.workspace.encode();
      for (final value in [-1, 8, 1.5, '2', null]) {
        await nativeCall('jumpStep', value);
      }
      for (final value in [
        null,
        'bad',
        {},
        {'sessionId': 2, 'cycleStep': 1},
        {'sessionId': 'x', 'cycleStep': 1.5},
      ]) {
        await nativeCall('startNext', value);
        await nativeCall('skipOffered', value);
      }
      expect(controller.workspace.encode(), original);
      expect(controller.pendingAction, isNull);
    });
  });

  group('menu panel controls', () {
    const channel = MethodChannel('stint/panel-test');
    const audioChannel = MethodChannel('stint/panel-music-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late FocusMusic music;
    late FakeMusicHost host;
    late NativeTimerBridge bridge;
    late List<MethodCall> snapshots;

    Future<void> nativeCall(String method, [Object? arguments]) async {
      final response = await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      );
      if (response != null) channel.codec.decodeEnvelope(response);
      await messenger.platformMessagesFinished;
    }

    setUp(() async {
      snapshots = [];
      host = FakeMusicHost();
      messenger.setMockMethodCallHandler(audioChannel, host.handle);
      messenger.setMockMethodCallHandler(channel, (call) async {
        snapshots.add(call);
        return null;
      });
      music = FocusMusic(channel: audioChannel, assets: FakeMusicAssets());
      await music.load();
      bridge = NativeTimerBridge(
        controller,
        music: music,
        channel: channel,
        onAdjust: () async {},
      );
      await messenger.platformMessagesFinished;
    });

    tearDown(() {
      bridge.dispose();
      music.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(audioChannel, null);
    });

    test(
      'publishes routines and music with no duplicate unchanged state',
      () async {
        final state = snapshots.single.arguments as Map;
        expect((state['routines'] as List).length, 3);
        expect(state['activeRoutineId'], 'classic');
        expect((state['music'] as Map)['selectedId'], 'warm_drift');
        expect((state['music'] as Map)['followTimer'], isFalse);
        controller.persist();
        await messenger.platformMessagesFinished;
        expect(snapshots, hasLength(1));
        await music.play();
        await messenger.platformMessagesFinished;
        final updated = snapshots.last.arguments as Map;
        expect((updated['music'] as Map)['playing'], isTrue);
        expect((updated['music'] as Map)['busy'], isFalse);
      },
    );

    test(
      'native actions change the same music and routine controllers',
      () async {
        await nativeCall('applyRoutine', 'quick');
        expect(controller.activeRoutineId, 'quick');
        expect(controller.remaining, 15 * 60);
        expect(controller.timer.running, isFalse);
        await nativeCall('musicSelect', 'custom-rain');
        expect(music.selectedId, 'custom-rain');
        await nativeCall('musicToggle');
        expect(music.playing, isTrue);
        await nativeCall('musicToggle');
        expect(music.playing, isFalse);
        await nativeCall('musicVolume', .7);
        expect(music.volume, .7);
        await nativeCall('followTimer', true);
        expect(music.followTimer, isTrue);
        expect((snapshots.last.arguments as Map)['activeRoutineId'], 'quick');
      },
    );

    test(
      'invalid native arguments leave preferences and timer unchanged',
      () async {
        final initial = controller.workspace.encode();
        final count = host.calls.length;
        await nativeCall('applyRoutine', 'missing');
        await nativeCall('applyRoutine', 42);
        await nativeCall('musicSelect', 'missing');
        await nativeCall('musicVolume', double.nan);
        await nativeCall('musicVolume', 'loud');
        await nativeCall('followTimer', 'yes');
        expect(controller.workspace.encode(), initial);
        expect(host.calls.length, count);
      },
    );
  });

  group('adjustable interval', () {
    test(
      'paused replacement persists while completed history stays intact',
      () {
        controller.startFocus();
        now = controller.timer.endsAt!;
        controller.tick();
        final completedId = controller.workspace.sessions.single.id;
        controller.startFocus();
        now = now.add(const Duration(minutes: 5));
        controller.pauseTimer();
        controller.setTimerMinutes(45);

        expect(controller.timer.running, isFalse);
        expect(controller.timer.sessionId, isNull);
        expect(controller.remaining, 2700);
        expect(controller.timer.totalSeconds, 2700);
        expect(controller.timer.completedCount, 1);
        expect(controller.workspace.sessions.single.id, completedId);
        final restored = StintController(
          store,
          now: () => now,
          tickAutomatically: false,
        );
        addTearDown(restored.dispose);
        expect(restored.timer.running, isFalse);
        expect(restored.remaining, 2700);
        expect(restored.workspace.settings.focusMinutes, 45);
        expect(restored.workspace.sessions.single.id, completedId);
      },
    );

    test(
      'running replacement gets a new deadline and records only the replacement',
      () {
        controller.startFocus();
        final discardedId = controller.timer.sessionId;
        final oldDeadline = controller.timer.endsAt!;
        now = now.add(const Duration(minutes: 4));
        controller.setTimerMinutes(40);
        final replacementId = controller.timer.sessionId;
        final newDeadline = now.add(const Duration(minutes: 40));
        expect(replacementId, isNot(discardedId));
        expect(controller.timer.endsAt, newDeadline);
        expect(controller.timer.running, isTrue);
        expect(controller.remaining, 2400);
        expect(controller.workspace.settings.focusMinutes, 40);
        expect(store.load()!.timer.endsAt, newDeadline);
        expect(store.load()!.timer.sessionId, replacementId);
        expect(controller.workspace.sessions, isEmpty);

        now = oldDeadline.add(const Duration(seconds: 1));
        controller.tick();
        expect(controller.timer.running, isTrue);
        expect(controller.workspace.sessions, isEmpty);
        now = newDeadline;
        controller.tick();
        controller.tick();
        expect(controller.workspace.sessions, hasLength(1));
        expect(controller.workspace.sessions.single.id, replacementId);
        expect(controller.workspace.sessions.single.seconds, 2400);
        expect(
          controller.workspace.sessions.single.finishedAt,
          newDeadline.toUtc(),
        );
      },
    );

    test(
      'phase-specific bounds reject invalid input without changing saved data',
      () {
        controller.persist();
        for (final phase in TimerPhase.values) {
          controller.selectPhase(phase);
          final maximum = phase == TimerPhase.focus ? 120 : 60;
          final original = store.contents;
          for (final invalid in [-1, 0, maximum + 1]) {
            expect(
              () => controller.setTimerMinutes(invalid),
              throwsArgumentError,
            );
            expect(store.contents, original);
            expect(controller.workspace.encode(), original);
          }
          controller.setTimerMinutes(maximum);
          expect(controller.remaining, maximum * 60);
          expect(store.load()!.settings.secondsFor(phase), maximum * 60);
          controller.setTimerMinutes(1);
          expect(controller.remaining, 60);
          expect(store.load()!.settings.secondsFor(phase), 60);
        }
        expect(controller.workspace.settings.focusMinutes, 1);
        expect(controller.workspace.settings.shortBreakMinutes, 1);
        expect(controller.workspace.settings.longBreakMinutes, 1);
      },
    );
  });
}
