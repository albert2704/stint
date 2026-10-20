import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';

void main() {
  late DateTime now;
  late MemoryWorkspaceStore store;
  late StintController controller;

  setUp(() {
    now = DateTime(2026, 10, 20, 9);
    store = MemoryWorkspaceStore();
    controller = StintController(
      store,
      now: () => now,
      tickAutomatically: false,
    );
  });
  tearDown(() => controller.dispose());

  test('Flow counts upward without a deadline or automatic completion', () {
    controller.requestMode(FocusMode.flow);
    expect(controller.isFlowFocus, isTrue);
    expect(controller.elapsedSeconds, 0);
    expect(controller.timer.running, isFalse);
    controller.startTimer();
    final sessionId = controller.timer.sessionId;
    now = now.add(const Duration(hours: 2));
    controller.tick();
    expect(controller.elapsedSeconds, 7200);
    expect(controller.timer.running, isTrue);
    expect(controller.timer.endsAt, isNull);
    expect(controller.workspace.sessions, isEmpty);
    expect(controller.suggestedFlowBreakMinutes, 24);
    controller.startTimer();
    expect(controller.timer.sessionId, sessionId);
    expect(controller.elapsedSeconds, 7200);
    controller.adjustCurrent(10);
    expect(controller.elapsedSeconds, 7200);
    now = now.add(const Duration(hours: 1));
    expect(controller.suggestedFlowBreakMinutes, 30);
    expect(controller.timer.running, isTrue);
  });

  test('pauses exclude time and preserve fractions of an active second', () {
    controller.requestMode(FocusMode.flow);
    expect(controller.finishFlow(), isFalse);
    controller.startTimer();
    expect(controller.finishFlow(), isFalse);
    now = now.add(const Duration(milliseconds: 750));
    controller.pauseTimer();
    expect(controller.timer.elapsedMilliseconds, 750);
    expect(controller.elapsedSeconds, 0);
    expect(controller.timerHasProgress, isTrue);
    now = now.add(const Duration(hours: 1));
    controller.tick();
    expect(controller.elapsedSeconds, 0);
    controller.startTimer();
    now = now.add(const Duration(milliseconds: 750));
    expect(controller.elapsedSeconds, 1);
    expect(controller.finishFlow(), isTrue);
    expect(controller.workspace.sessions.single.seconds, 1);
    expect(controller.timer.totalSeconds, 60);
    expect(controller.timer.running, isFalse);
  });

  test('subsecond positive Flow is recorded as at least one second', () {
    controller.requestMode(FocusMode.flow);
    controller.startTimer();
    now = now.add(const Duration(milliseconds: 1));
    expect(controller.finishFlow(), isTrue);
    expect(controller.workspace.sessions.single.seconds, 1);
    expect(controller.finishFlow(), isFalse);
    expect(controller.workspace.sessions, hasLength(1));
  });

  test('a clock correction cannot make one active interval count twice', () {
    controller.requestMode(FocusMode.flow);
    controller.startTimer();
    now = now.add(const Duration(seconds: 20));
    controller.persist();
    expect(controller.elapsedSeconds, 20);
    now = now.subtract(const Duration(seconds: 10));
    controller.persist();
    now = now.add(const Duration(seconds: 10));
    expect(controller.elapsedSeconds, 20);
  });

  test('checkpoint recovery pauses Flow and excludes all closed app time', () {
    controller.requestMode(FocusMode.flow);
    controller.startTimer();
    final sessionId = controller.timer.sessionId;
    now = now.add(const Duration(seconds: 14));
    controller.tick();
    expect(store.load()!.timer.elapsedMilliseconds, 0);
    now = now.add(const Duration(seconds: 1));
    controller.tick();
    expect(store.load()!.timer.elapsedMilliseconds, 15000);
    expect(store.load()!.timer.running, isFalse);
    now = now.add(const Duration(seconds: 14));
    controller.tick();
    expect(controller.elapsedSeconds, 29);
    expect(store.load()!.timer.elapsedMilliseconds, 15000);

    now = now.add(const Duration(days: 3));
    final reopened = StintController(
      store,
      now: () => now,
      tickAutomatically: false,
    );
    addTearDown(reopened.dispose);
    expect(reopened.elapsedSeconds, 15);
    expect(reopened.timer.running, isFalse);
    expect(reopened.timer.sessionId, sessionId);
    expect(reopened.workspace.sessions, isEmpty);
    reopened.startTimer();
    now = now.add(const Duration(seconds: 7));
    reopened.persist();
    expect(reopened.elapsedSeconds, 22);
    expect(store.load()!.timer.elapsedMilliseconds, 22000);
    reopened.pauseTimer();
    now = now.add(const Duration(days: 1));
    expect(reopened.elapsedSeconds, 22);
  });

  test('delayed sleep delivery removes sleep even after a wake checkpoint', () {
    controller.requestMode(FocusMode.flow);
    controller.startTimer();
    now = now.add(const Duration(seconds: 23));
    controller.tick();
    final sleepStartedAt = now;
    now = now.add(const Duration(hours: 3));
    controller.tick();
    expect(controller.elapsedSeconds, 10823);
    controller.pauseFlowForSleep(sleepStartedAt);
    expect(controller.elapsedSeconds, 23);
    expect(controller.timer.running, isFalse);
    expect(store.load()!.timer.elapsedMilliseconds, 23000);
    controller.startTimer();
    now = now.add(const Duration(seconds: 7));
    controller.pauseFlowForSleep(sleepStartedAt);
    expect(controller.timer.running, isTrue);
    expect(controller.elapsedSeconds, 30);
    controller.pauseFlowForSleep(now.add(const Duration(minutes: 1)));
    expect(controller.elapsedSeconds, 30);
    expect(controller.timer.running, isFalse);
  });

  test('Flow completion follows the cycle and each break returns to Flow', () {
    controller.requestMode(FocusMode.flow);
    controller.setContinuationNote('Next: review the login redirect');
    for (var index = 0; index < 4; index++) {
      expect(controller.timer.cycleStep, index * 2);
      expect(controller.isFlowFocus, isTrue);
      controller.startTimer();
      final sessionId = controller.timer.sessionId;
      now = now.add(const Duration(minutes: 25, seconds: 1));
      expect(controller.suggestedFlowBreakMinutes, 6);
      expect(controller.finishFlow(), isTrue);
      expect(controller.finishFlow(), isFalse);
      expect(controller.timer.cycleStep, index * 2 + 1);
      expect(
        controller.timer.phase,
        index == 3 ? TimerPhase.longBreak : TimerPhase.shortBreak,
      );
      expect(controller.remaining, 360);
      expect(controller.timer.running, isFalse);
      expect(controller.timer.completedSessionId, sessionId);
      expect(controller.workspace.sessions.length, index + 1);
      final recorded = controller.workspace.sessions.first;
      expect(recorded.seconds, 1501);
      expect(recorded.mode, FocusMode.flow);
      expect(recorded.finishedAt, now.toUtc());
      expect(recorded.continuationNote, 'Next: review the login redirect');
      controller.startTimer();
      now = controller.timer.endsAt!;
      controller.tick();
      expect(controller.isFlowFocus, isTrue);
      expect(controller.elapsedSeconds, 0);
      expect(controller.timer.running, isFalse);
      expect(controller.workspace.sessions.length, index + 1);
    }
    expect(controller.timer.cycleStep, 0);
    expect(store.load()!.timer.mode, FocusMode.flow);
    expect(store.load()!.sessions, hasLength(4));
  });

  test('reset keeps a Flow break at its suggested length', () {
    controller.requestMode(FocusMode.flow);
    controller.startTimer();
    now = now.add(const Duration(minutes: 27));
    controller.finishFlow();
    expect(controller.remaining, 6 * 60);
    controller.startTimer();
    now = now.add(const Duration(minutes: 1));
    controller.requestReset();
    controller.confirmPending();
    expect(controller.remaining, 6 * 60);
    expect(controller.timer.running, isFalse);
    expect(controller.workspace.sessions, hasLength(1));
  });

  test(
    'Settings save checkpoints Flow without changing its running interval',
    () {
      controller.requestMode(FocusMode.flow);
      controller.startTimer();
      now = now.add(const Duration(seconds: 8));
      controller.updateSettings(
        focus: 30,
        shortBreak: 6,
        longBreak: 20,
        appearance: 'dark',
      );
      expect(controller.timer.running, isTrue);
      expect(controller.elapsedSeconds, 8);
      expect(store.load()!.timer.elapsedMilliseconds, 8000);
      expect(store.load()!.timer.running, isFalse);
      expect(store.load()!.settings.focusMode, FocusMode.flow);
    },
  );

  test(
    'changing mode confirms unfinished sessions and cancellation is inert',
    () {
      controller.startTimer();
      now = now.add(const Duration(minutes: 2));
      final oldTimer = controller.timer.toJson();
      final settings = controller.workspace.settings.toJson();
      controller.requestMode(FocusMode.flow);
      expect(controller.pendingAction?.kind, 'mode');
      expect(controller.pendingAction?.toJson()['mode'], 'flow');
      expect(controller.timer.toJson(), oldTimer);
      expect(controller.workspace.settings.toJson(), settings);
      controller.cancelPending();
      expect(controller.timer.toJson(), oldTimer);
      controller.pauseTimer();
      controller.requestMode(FocusMode.flow);
      expect(controller.pendingAction, isNotNull);
      controller.confirmPending();
      expect(controller.timer.mode, FocusMode.flow);
      expect(controller.workspace.settings.focusMode, FocusMode.flow);
      expect(controller.timer.running, isFalse);
      expect(controller.elapsedSeconds, 0);
      expect(controller.workspace.sessions, isEmpty);
      controller.startTimer();
      now = now.add(const Duration(seconds: 20));
      controller.requestMode(FocusMode.pomodoro);
      expect(controller.pendingAction, isNotNull);
      controller.finishFlow();
      controller.confirmPending();
      expect(controller.timer.mode, FocusMode.flow);
      expect(controller.timer.phase, TimerPhase.shortBreak);
      expect(controller.workspace.sessions, hasLength(1));
    },
  );

  test('requests at Pomodoro expiry do not discard the offered break', () {
    controller.startTimer();
    now = controller.timer.endsAt!;
    controller.requestMode(FocusMode.flow);
    expect(controller.workspace.sessions, hasLength(1));
    expect(controller.timer.phase, TimerPhase.shortBreak);
    expect(controller.timer.mode, FocusMode.pomodoro);
    expect(controller.pendingAction, isNull);
  });

  test(
    'external actions await confirmation and block timer edits while busy',
    () async {
      final pending = Completer<void>();
      var calls = 0;
      Future<void> configure() async {
        calls++;
        controller.applyProfileTimer(
          focus: 50,
          shortBreak: 10,
          longBreak: 20,
          mode: FocusMode.flow,
        );
        await pending.future;
      }

      controller.startTimer();
      final previous = controller.workspace.encode();
      controller.requestExternalAction(
        id: 'coding',
        title: 'Switch to Coding?',
        onConfirm: configure,
      );
      expect(calls, 0);
      expect(controller.pendingAction?.externalActionId, 'coding');
      controller.cancelPending();
      expect(controller.workspace.encode(), previous);
      expect(calls, 0);
      controller.requestExternalAction(
        id: 'coding',
        title: 'Switch to Coding?',
        onConfirm: configure,
      );
      controller.confirmPending();
      expect(calls, 1);
      expect(controller.externalActionBusy, isTrue);
      expect(controller.timer.mode, FocusMode.flow);
      expect(controller.workspace.settings.focusMinutes, 50);
      expect(controller.timer.running, isFalse);
      final prepared = controller.workspace.encode();
      controller.startTimer();
      controller.startFocus();
      controller.requestMode(FocusMode.pomodoro);
      controller.jumpToStep(3);
      controller.skipToNext();
      controller.selectPhase(TimerPhase.longBreak);
      controller.resetTimer();
      controller.applyRoutine('quick');
      expect(controller.workspace.encode(), prepared);
      expect(controller.pendingAction, isNull);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.externalActionBusy, isFalse);
      controller.startTimer();
      expect(controller.timer.running, isTrue);
    },
  );

  test(
    'external failures always release their timer gate and show a notice',
    () async {
      controller.requestExternalAction(
        id: 'unavailable',
        title: 'Switch profile?',
        onConfirm: () => throw StateError('Configuration unavailable'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.externalActionBusy, isFalse);
      expect(controller.notice, contains('could not be applied'));
      controller.startTimer();
      expect(controller.timer.running, isTrue);
    },
  );
}
