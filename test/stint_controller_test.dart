import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';

class SettingsFailingStore extends MemoryWorkspaceStore {
  bool fail = false;
  @override
  void save(Workspace workspace) {
    if (fail) throw StateError('Disk full');
    super.save(workspace);
  }
}

void main() {
  late DateTime now;
  late MemoryWorkspaceStore store;
  late StintController controller;
  setUp(() {
    now = DateTime(2026, 10, 9, 9);
    store = MemoryWorkspaceStore();
    controller = StintController(
      store,
      now: () => now,
      tickAutomatically: false,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'failed Settings save rolls back preferences only and keeps the draft retryable',
    () {
      final disk = SettingsFailingStore();
      final c = StintController(disk, now: () => now, tickAutomatically: false);
      addTearDown(c.dispose);
      c.startTimer();
      now = now.add(const Duration(minutes: 2));
      c.requestReset();
      final before = c.workspace.settings.toJson();
      final timer = c.timer.toJson();
      final saved = disk.contents;
      final published = <Map<String, dynamic>>[];
      c.addListener(() => published.add(c.workspace.settings.toJson()));
      const draft = [
        FocusRoutine(
          id: 'mine',
          name: 'Writing',
          focusMinutes: 40,
          shortBreakMinutes: 8,
          longBreakMinutes: 20,
        ),
      ];
      disk.fail = true;
      c.updateSettings(
        focus: 40,
        shortBreak: 8,
        longBreak: 20,
        appearance: 'dark',
        customRoutines: draft,
        preferredRoutineId: 'mine',
      );
      expect(c.saveError, isNotNull);
      expect(c.workspace.settings.toJson(), before);
      expect(c.timer.toJson(), timer);
      expect(c.remaining, 23 * 60);
      expect(c.pendingAction?.kind, 'reset');
      expect(disk.contents, saved);
      expect(published, [before]);
      disk.fail = false;
      c.updateSettings(
        focus: 40,
        shortBreak: 8,
        longBreak: 20,
        appearance: 'dark',
        customRoutines: draft,
        preferredRoutineId: 'mine',
      );
      expect(c.saveError, isNull);
      expect(c.activeRoutineId, 'mine');
      expect(c.timer.toJson(), timer);
      expect(c.pendingAction?.kind, 'reset');
      expect(disk.load()!.settings.customRoutines.single.id, 'mine');
    },
  );

  test(
    'old timers derive cycle position without changing their phase or count',
    () {
      final data =
          jsonDecode(controller.workspace.encode()) as Map<String, dynamic>;
      final timer = data['timer'] as Map<String, dynamic>;
      timer.remove('cycleStep');
      timer.remove('completedSessionId');
      for (var count = 0; count < 12; count++) {
        for (final phase in TimerPhase.values) {
          timer['phase'] = phase.name;
          timer['completedCount'] = count;
          final restored = Workspace.decode(jsonEncode(data));
          final expected = switch (phase) {
            TimerPhase.focus => 2 * (count % 4),
            TimerPhase.shortBreak => count % 4 == 0 ? 1 : 2 * (count % 4) - 1,
            TimerPhase.longBreak => 7,
          };
          expect(restored.timer.cycleStep, expected);
          expect(restored.timer.phase, phase);
          expect(restored.timer.completedCount, count);
          expect(restored.timer.completedSessionId, isNull);
          expect(Workspace.decode(restored.encode()).timer.cycleStep, expected);
        }
      }
    },
  );

  test('invalid cycle positions and phase mismatches are rejected', () {
    final data =
        jsonDecode(controller.workspace.encode()) as Map<String, dynamic>;
    for (final invalid in [-1, 8, 2.5, '2', 1]) {
      data['timer']['cycleStep'] = invalid;
      expect(() => Workspace.decode(jsonEncode(data)), throwsFormatException);
    }
    expect(() => controller.jumpToStep(-1), throwsRangeError);
    expect(() => controller.requestJumpTo(8), throwsRangeError);
    expect(controller.timer.cycleStep, 0);
  });

  test(
    'completion follows all eight cycle steps independent of lifetime count',
    () {
      controller.timer.completedCount = 23;
      for (var step = 0; step < 8; step++) {
        expect(controller.timer.cycleStep, step);
        expect(controller.timer.phase, phaseForCycleStep(step));
        controller.startTimer();
        final session = controller.timer.sessionId;
        now = controller.timer.endsAt!;
        controller.tick();
        expect(controller.timer.cycleStep, (step + 1) % 8);
        expect(controller.timer.phase, phaseForCycleStep((step + 1) % 8));
        expect(controller.timer.completedSessionId, session);
        expect(controller.timer.running, isFalse);
        expect(controller.timer.completedCount, 23 + (step ~/ 2) + 1);
      }
      expect(controller.workspace.sessions, hasLength(4));
      controller.tick();
      expect(controller.workspace.sessions, hasLength(4));
    },
  );

  test('skip and jump move position without recording completions', () {
    controller.timer.completedCount = 12;
    controller.startTimer();
    now = now.add(const Duration(minutes: 3));
    controller.skipToNext();
    expect(controller.timer.cycleStep, 1);
    expect(controller.timer.running, isFalse);
    expect(controller.remaining, 300);
    controller.jumpToStep(6);
    expect(controller.timer.phase, TimerPhase.focus);
    controller.skipToNext();
    expect(controller.timer.cycleStep, 7);
    expect(controller.remaining, 900);
    controller.skipToNext();
    expect(controller.timer.cycleStep, 0);
    expect(controller.timer.completedCount, 12);
    expect(controller.workspace.sessions, isEmpty);
    expect(store.load()!.timer.cycleStep, 0);
  });

  test(
    'idle current adjustment preserves settings and does not create progress',
    () {
      final settings = controller.workspace.settings.toJson();
      controller.adjustCurrent(1);
      expect(controller.remaining, 1560);
      expect(controller.timer.totalSeconds, 1560);
      expect(controller.timerHasProgress, isFalse);
      expect(controller.timer.sessionId, isNull);
      expect(controller.timer.endsAt, isNull);
      controller.adjustCurrent(-1);
      expect(controller.remaining, 1500);
      expect(controller.workspace.settings.toJson(), settings);
      expect(store.load()!.timer.remaining, 1500);
    },
  );

  test(
    'running adjustments preserve elapsed time, session and exact deadline',
    () {
      controller.startTimer();
      final session = controller.timer.sessionId;
      final deadline = controller.timer.endsAt!;
      now = now.add(const Duration(minutes: 4, milliseconds: 500));
      final before = controller.remaining;
      controller.adjustCurrent(1);
      expect(controller.remaining, before + 60);
      expect(controller.timer.totalSeconds, 1560);
      expect(controller.timer.endsAt, deadline.add(const Duration(minutes: 1)));
      expect(controller.timer.sessionId, session);
      expect(controller.workspace.settings.focusMinutes, 25);
      controller.pauseTimer();
      final elapsed = controller.timer.totalSeconds - controller.remaining;
      controller.adjustCurrent(-2);
      expect(controller.timer.totalSeconds - controller.remaining, elapsed);
      expect(controller.timer.running, isFalse);
      expect(controller.timer.sessionId, session);
      final restored = store.load()!;
      expect(restored.timer.remaining, controller.remaining);
      expect(restored.timer.totalSeconds, controller.timer.totalSeconds);
    },
  );

  test(
    'remaining clamps by phase and extended elapsed totals survive storage',
    () {
      controller.startTimer();
      now = now.add(const Duration(minutes: 20));
      controller.adjustCurrent(1000);
      expect(controller.remaining, 7200);
      expect(controller.timer.totalSeconds, 8400);
      expect(store.load()!.timer.totalSeconds, 8400);
      controller.adjustCurrent(1);
      expect(controller.timer.totalSeconds, 8400);
      now = controller.timer.endsAt!;
      controller.tick();
      expect(controller.workspace.sessions.single.seconds, 8400);
      expect(store.load()!.sessions.single.seconds, 8400);
      controller.adjustCurrent(1000);
      expect(controller.remaining, 3600);
      expect(controller.timer.totalSeconds, 3600);
      controller.adjustCurrent(-1000);
      expect(controller.remaining, 60);
      expect(controller.timer.totalSeconds, 60);
      controller.startTimer();
      now = now.add(const Duration(seconds: 35));
      final deadline = controller.timer.endsAt;
      controller.adjustCurrent(-1);
      expect(controller.remaining, 25);
      expect(controller.timer.endsAt, deadline);
    },
  );

  test(
    'adjustment at expiry records completion and leaves the next interval alone',
    () {
      controller.startTimer();
      now = controller.timer.endsAt!;
      controller.adjustCurrent(1);
      expect(controller.workspace.sessions, hasLength(1));
      expect(controller.timer.cycleStep, 1);
      expect(controller.remaining, 300);
      expect(controller.timer.totalSeconds, 300);
    },
  );

  test(
    'requests apply immediately when idle and confirmations are transient',
    () {
      controller.requestJumpTo(4);
      expect(controller.timer.cycleStep, 4);
      expect(controller.pendingAction, isNull);
      controller.requestSkip();
      expect(controller.timer.cycleStep, 5);
      controller.requestRoutine('deep');
      expect(controller.timer.cycleStep, 6);
      expect(controller.remaining, 3000);
      controller.startTimer();
      now = now.add(const Duration(minutes: 2));
      final saved = store.contents;
      final deadline = controller.timer.endsAt;
      controller.requestReset();
      expect(controller.pendingAction?.title, 'Reset this stint?');
      expect(controller.pendingAction?.confirmLabel, 'Reset');
      expect(controller.pendingAction?.kind, 'reset');
      expect(store.contents, saved);
      expect(store.load()!.timer.endsAt, deadline);
      final reopened = StintController(
        store,
        now: () => now,
        tickAutomatically: false,
      );
      addTearDown(reopened.dispose);
      expect(reopened.pendingAction, isNull);
      controller.cancelPending();
      expect(controller.pendingAction, isNull);
      expect(controller.timer.endsAt, deadline);
      controller.requestReset();
      controller.confirmPending();
      expect(controller.timer.cycleStep, 6);
      expect(controller.remaining, 3000);
      expect(controller.timerHasProgress, isFalse);
      expect(controller.pendingAction, isNull);
    },
  );

  test('shared confirmation handles skip, jump and rhythm without history', () {
    controller.startTimer();
    now = now.add(const Duration(seconds: 1));
    controller.requestSkip();
    expect(controller.pendingAction?.targetStep, 1);
    expect(controller.pendingAction?.title, 'Switch to short break?');
    controller.confirmPending();
    expect(controller.timer.cycleStep, 1);
    controller.startTimer();
    controller.requestJumpTo(7);
    expect(controller.pendingAction?.kind, 'jump');
    expect(controller.pendingAction?.targetStep, 7);
    controller.confirmPending();
    expect(controller.timer.cycleStep, 7);
    controller.startTimer();
    controller.requestRoutine('quick');
    expect(controller.pendingAction?.routineId, 'quick');
    expect(controller.pendingAction?.title, 'Switch to Quick focus?');
    controller.confirmPending();
    expect(controller.timer.cycleStep, 0);
    expect(controller.remaining, 900);
    expect(controller.timer.completedCount, 0);
    expect(controller.workspace.sessions, isEmpty);
  });

  test(
    'expiry clears each pending action before a stale confirmation can discard',
    () {
      for (final request in <void Function()>[
        controller.requestReset,
        controller.requestSkip,
        () => controller.requestJumpTo(6),
        () => controller.requestRoutine('deep'),
      ]) {
        controller.selectPhase(TimerPhase.focus);
        controller.startTimer();
        request();
        expect(controller.pendingAction, isNotNull);
        now = controller.timer.endsAt!;
        controller.confirmPending();
        expect(controller.pendingAction, isNull);
        expect(controller.timer.phase, isNot(TimerPhase.focus));
        expect(controller.timer.running, isFalse);
        expect(controller.activeRoutineId, 'classic');
      }
      expect(controller.workspace.sessions, hasLength(4));
    },
  );

  test(
    'a request arriving at expiry does not skip the newly offered break',
    () {
      controller.startTimer();
      now = controller.timer.endsAt!;
      controller.requestSkip();
      expect(controller.timer.cycleStep, 1);
      expect(controller.remaining, 300);
      expect(controller.pendingAction, isNull);
      controller.confirmPending();
      expect(controller.timer.cycleStep, 1);
    },
  );

  test('rhythms land on the current focus or the next focus after a break', () {
    for (var step = 0; step < 8; step++) {
      controller.jumpToStep(step);
      controller.applyRoutine('quick');
      expect(controller.timer.cycleStep, step.isEven ? step : (step + 1) % 8);
      expect(controller.timer.phase, TimerPhase.focus);
      expect(controller.remaining, 900);
    }
  });

  test(
    'settings atomically save drafts without changing even an idle interval',
    () {
      final draft = <FocusRoutine>[
        const FocusRoutine(
          id: 'mine',
          name: 'Writing',
          focusMinutes: 40,
          shortBreakMinutes: 8,
          longBreakMinutes: 20,
        ),
      ];
      final timer = controller.timer.toJson();
      controller.updateSettings(
        focus: 40,
        shortBreak: 8,
        longBreak: 20,
        appearance: 'dark',
        customRoutines: draft,
        preferredRoutineId: 'mine',
      );
      expect(controller.timer.toJson(), timer);
      expect(controller.activeRoutineId, 'mine');
      draft.clear();
      expect(controller.workspace.settings.customRoutines, hasLength(1));
      expect(store.load()!.settings.preferredRoutineId, 'mine');
      final saved = store.contents;
      expect(
        () => controller.updateSettings(
          focus: 30,
          shortBreak: 5,
          longBreak: 15,
          appearance: 'light',
          customRoutines: FocusRoutine.builtIns,
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.updateSettings(
          focus: 30,
          shortBreak: 5,
          longBreak: 15,
          appearance: 'light',
          preferredRoutineId: 'missing',
        ),
        throwsArgumentError,
      );
      expect(store.contents, saved);
      expect(controller.workspace.encode(), saved);
      controller.startTimer();
      now = now.add(const Duration(minutes: 1));
      final running = controller.timer.toJson();
      controller.updateSettings(
        focus: 41,
        shortBreak: 9,
        longBreak: 21,
        appearance: 'light',
      );
      expect(controller.timer.toJson(), running);
      expect(controller.activeRoutineId, isNull);
      now = controller.timer.endsAt!;
      controller.tick();
      expect(controller.remaining, 9 * 60);
    },
  );

  test(
    'notification action survives restart and only starts its untouched offer once',
    () {
      controller.startTimer();
      final session = controller.timer.sessionId!;
      now = controller.timer.endsAt!;
      controller.tick();
      final restored = StintController(
        store,
        now: () => now,
        tickAutomatically: false,
      );
      addTearDown(restored.dispose);
      expect(restored.timer.completedSessionId, session);
      restored.startNextFromNotification(sessionId: 'stale', cycleStep: 1);
      restored.startNextFromNotification(sessionId: session, cycleStep: 3);
      expect(restored.timer.running, isFalse);
      restored.startNextFromNotification(sessionId: session, cycleStep: 1);
      expect(restored.timer.running, isTrue);
      final deadline = restored.timer.endsAt;
      restored.pauseTimer();
      restored.startNextFromNotification(sessionId: session, cycleStep: 1);
      expect(restored.timer.running, isFalse);
      expect(deadline, now.add(const Duration(minutes: 5)));
      expect(restored.timer.completedSessionId, isNull);
    },
  );

  test(
    'changed intervals invalidate old completion actions even after returning to step',
    () {
      controller.startTimer();
      final session = controller.timer.sessionId!;
      now = controller.timer.endsAt!;
      controller.tick();
      controller.jumpToStep(3);
      controller.jumpToStep(1);
      controller.startNextFromNotification(sessionId: session, cycleStep: 1);
      expect(controller.timer.running, isFalse);
      expect(controller.timer.completedSessionId, isNull);
    },
  );
}
