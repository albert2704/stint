import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'progress.dart';
import 'store.dart';

/// A shared, transient confirmation displayed by both timer surfaces.
class PendingTimerAction {
  const PendingTimerAction({
    required this.kind,
    required this.title,
    required this.confirmLabel,
    this.targetStep,
    this.routineId,
    this.mode,
    this.externalActionId,
    this.onConfirm,
  });

  final String kind;
  final String title;
  final String confirmLabel;
  final int? targetStep;
  final String? routineId;
  final FocusMode? mode;
  final String? externalActionId;
  final FutureOr<void> Function()? onConfirm;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'title': title,
    'confirmLabel': confirmLabel,
    if (targetStep != null) 'targetStep': targetStep,
    if (routineId != null) 'routineId': routineId,
    if (mode != null) 'mode': mode!.name,
    if (externalActionId != null) 'externalActionId': externalActionId,
  };
}

class StintController extends ChangeNotifier {
  StintController(
    this.store, {
    DateTime Function()? now,
    bool tickAutomatically = true,
  }) : now = now ?? DateTime.now {
    workspace = store.load() ?? Workspace.empty();
    tick();
    if (tickAutomatically) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
  }
  final WorkspaceStore store;
  final DateTime Function() now;
  late Workspace workspace;
  Timer? _ticker;
  String? saveError;
  String? notice;
  PendingTimerAction? _pendingAction;
  PendingTimerAction? get pendingAction => _pendingAction;
  int _intervalRevision = 0;
  int? _pendingRevision;
  int _lastRemaining = -1;
  int _lastElapsed = -1;
  DateTime? _flowRunStartedAt;
  int _flowRunBaseMilliseconds = 0;
  bool _externalActionBusy = false;
  bool get externalActionBusy => _externalActionBusy;
  (int, int, int, Duration, String)? _lastCalendar;
  Object? _progressSourceKey;
  ProgressSummary? _progressSource;
  final _progress = <(int, int, int), ProgressSummary>{};
  FocusTimer get timer => workspace.timer;
  bool get isFlowFocus => timer.isFlowFocus;
  int get _elapsedMilliseconds =>
      timer.elapsedMilliseconds +
      (timer.flowStartedAt == null
          ? 0
          : max(0, now().difference(timer.flowStartedAt!).inMilliseconds));
  int get elapsedSeconds => isFlowFocus ? _elapsedMilliseconds ~/ 1000 : 0;
  int get suggestedFlowBreakMinutes =>
      (_elapsedMilliseconds / (5 * 60 * 1000)).ceil().clamp(1, 30);
  int get remaining => timer.endsAt == null
      ? timer.remaining
      : min(
          timer.totalSeconds,
          max(
            0,
            (timer.endsAt!.difference(now()).inMilliseconds / 1000).ceil(),
          ),
        );
  bool get timerHasProgress => isFlowFocus
      ? timer.running || _elapsedMilliseconds > 0
      : timer.running || timer.remaining < timer.totalSeconds;

  List<FocusRoutine> get routines => List.unmodifiable([
    ...FocusRoutine.builtIns,
    ...workspace.settings.customRoutines,
  ]);

  String? get activeRoutineId {
    final settings = workspace.settings;
    final matching = routines.where((routine) => routine.matches(settings));
    for (final routine in matching) {
      if (routine.id == settings.preferredRoutineId) return routine.id;
    }
    return matching.firstOrNull?.id;
  }

  FocusRoutine _routine(String id) =>
      routines.where((routine) => routine.id == id).firstOrNull ??
      (throw ArgumentError('Unknown rhythm.'));

  /// Prepares focus at the current focus step, or the next focus after a break.
  /// Interactive callers use requestRoutine so progress is confirmed first.
  void applyRoutine(String id) {
    if (externalActionBusy) return;
    final routine = _routine(id);
    tick();
    final settings = workspace.settings;
    settings.focusMinutes = routine.focusMinutes;
    settings.shortBreakMinutes = routine.shortBreakMinutes;
    settings.longBreakMinutes = routine.longBreakMinutes;
    settings.preferredRoutineId = routine.id;
    _prepareStep(
      timer.cycleStep.isEven ? timer.cycleStep : (timer.cycleStep + 1) % 8,
    );
    notice = null;
    persist();
  }

  String saveRoutine({
    required String name,
    required int focus,
    required int shortBreak,
    required int longBreak,
  }) {
    final routine = FocusRoutine(
      id: newId(),
      name: name.trim(),
      focusMinutes: focus,
      shortBreakMinutes: shortBreak,
      longBreakMinutes: longBreak,
    );
    if (!routine.isValid) {
      throw ArgumentError('Invalid rhythm name or durations.');
    }
    workspace.settings.customRoutines.add(routine);
    if (routine.matches(workspace.settings)) {
      workspace.settings.preferredRoutineId = routine.id;
    }
    persist();
    return routine.id;
  }

  void deleteRoutine(String id) {
    final custom = workspace.settings.customRoutines;
    final index = custom.indexWhere((routine) => routine.id == id);
    if (index < 0) {
      throw ArgumentError('Only a saved custom rhythm can be deleted.');
    }
    custom.removeAt(index);
    if (workspace.settings.preferredRoutineId == id) {
      workspace.settings.preferredRoutineId = null;
    }
    if (_pendingAction?.routineId == id) _clearPending();
    persist();
  }

  /// Day totals are rebuilt only when sessions or the local calendar change.
  /// Goal and locale changes reuse those totals; countdown ticks never scan
  /// history. Sessions are immutable and the app only adds completed stints.
  ProgressSummary progress({int firstDayOfWeekIndex = 1}) {
    RangeError.checkValueInInterval(firstDayOfWeekIndex, 0, 6);
    final currentTime = now().toLocal();
    final sessions = workspace.sessions;
    final sourceKey = (
      sessions,
      sessions.length,
      sessions.firstOrNull,
      sessions.lastOrNull,
      _calendarKey(currentTime),
    );
    final goal = workspace.settings.dailyGoal;
    final weeklyGoalMinutes = workspace.settings.weeklyGoalMinutes;
    if (_progressSourceKey != sourceKey) {
      _progressSourceKey = sourceKey;
      _progressSource = ProgressSummary.from(
        sessions,
        now: currentTime,
        goal: goal,
        firstDayOfWeekIndex: firstDayOfWeekIndex,
        weeklyGoalMinutes: weeklyGoalMinutes,
      );
      _progress.clear();
      _progress[(goal, firstDayOfWeekIndex, weeklyGoalMinutes)] =
          _progressSource!;
    }
    return _progress.putIfAbsent(
      (goal, firstDayOfWeekIndex, weeklyGoalMinutes),
      () => _progressSource!.withPreferences(
        goal: goal,
        firstDayOfWeekIndex: firstDayOfWeekIndex,
        weeklyGoalMinutes: weeklyGoalMinutes,
      ),
    );
  }

  /// Saves immediately; the Progress sheet has no Save button.
  void setDailyGoal(int goal) {
    final bounded = goal.clamp(1, StintPreferences.maxDailyGoal);
    if (workspace.settings.dailyGoal == bounded) return;
    workspace.settings.dailyGoal = bounded;
    persist();
  }

  void setWeeklyGoalMinutes(int minutes) {
    final bounded = minutes.clamp(
      StintPreferences.minWeeklyGoalMinutes,
      StintPreferences.maxWeeklyGoalMinutes,
    );
    final rounded =
        (bounded / StintPreferences.weeklyGoalStepMinutes).round() *
        StintPreferences.weeklyGoalStepMinutes;
    if (workspace.settings.weeklyGoalMinutes == rounded && saveError == null) {
      return;
    }
    workspace.settings.weeklyGoalMinutes = rounded;
    persist();
  }

  void setContinuationNote(String note) {
    final normalized = normalizeContinuationNote(note);
    if (workspace.settings.continuationNote == normalized &&
        saveError == null) {
      return;
    }
    workspace.settings.continuationNote = normalized;
    persist();
  }

  (int, int, int, Duration, String) _calendarKey(DateTime local) => (
    local.year,
    local.month,
    local.day,
    local.timeZoneOffset,
    local.timeZoneName,
  );

  bool _calendarChanged() {
    final calendar = _calendarKey(now().toLocal());
    if (calendar == _lastCalendar) return false;
    _lastCalendar = calendar;
    return true;
  }

  void persist() {
    _checkpointFlow();
    try {
      store.save(workspace);
      saveError = null;
    } catch (_) {
      saveError =
          'The timer could not be saved. Keep this window open and try again.';
    }
    notifyListeners();
  }

  void _checkpointFlow() {
    if (!isFlowFocus || !timer.running) return;
    final checkpoint = now();
    if (checkpoint.isBefore(timer.flowStartedAt!)) return;
    timer.elapsedMilliseconds += max(
      0,
      checkpoint.difference(timer.flowStartedAt!).inMilliseconds,
    );
    timer.flowStartedAt = checkpoint;
  }

  void startFocus() {
    if (externalActionBusy) return;
    selectPhase(TimerPhase.focus);
    startTimer();
  }

  /// Compatibility for old callers; cycle-track callers use requestJumpTo.
  void selectPhase(TimerPhase phase) {
    if (externalActionBusy) return;
    final step = switch (phase) {
      TimerPhase.focus =>
        timer.cycleStep.isEven ? timer.cycleStep : (timer.cycleStep + 1) % 8,
      TimerPhase.shortBreak =>
        timer.cycleStep == 7
            ? 1
            : timer.cycleStep.isOdd
            ? timer.cycleStep
            : min(5, timer.cycleStep + 1),
      TimerPhase.longBreak => 7,
    };
    _prepareStep(step);
    notice = null;
    persist();
  }

  void startTimer() {
    if (externalActionBusy) return;
    final wasRunning = timer.running;
    tick();
    if (wasRunning) return;
    timer.sessionId ??= newId();
    timer.completedSessionId = null;
    if (isFlowFocus) {
      _flowRunStartedAt = now();
      _flowRunBaseMilliseconds = timer.elapsedMilliseconds;
      timer.flowStartedAt = _flowRunStartedAt;
    } else {
      timer.endsAt = now().add(Duration(seconds: timer.remaining));
    }
    _clearPending();
    notice = null;
    persist();
  }

  void pauseTimer() {
    if (externalActionBusy) return;
    if (!timer.running) return;
    if (isFlowFocus) {
      _checkpointFlow();
      timer.flowStartedAt = null;
      _flowRunStartedAt = null;
      persist();
      return;
    }
    if (remaining == 0) {
      tick();
      return;
    }
    timer.remaining = remaining;
    timer.endsAt = null;
    persist();
  }

  /// A native sleep event carries the instant sleep began. Delivery may wait
  /// until wake, so use the current run's original anchor, even if a resumed
  /// Dart tick already checkpointed time during sleep.
  void pauseFlowForSleep(DateTime cutoff) {
    if (!isFlowFocus || !timer.running) return;
    final startedAt = _flowRunStartedAt ?? timer.flowStartedAt!;
    if (cutoff.isBefore(startedAt)) return; // An older run's delayed event.
    final currentTime = now();
    final end = cutoff.isAfter(currentTime) ? currentTime : cutoff;
    final base = _flowRunStartedAt == null
        ? timer.elapsedMilliseconds
        : _flowRunBaseMilliseconds;
    timer.elapsedMilliseconds =
        base + max(0, end.difference(startedAt).inMilliseconds);
    timer.flowStartedAt = null;
    _flowRunStartedAt = null;
    persist();
  }

  void resetTimer() {
    if (externalActionBusy) return;
    final revision = _intervalRevision;
    tick();
    if (revision != _intervalRevision) return;
    _prepareStep(
      timer.cycleStep,
      totalSeconds: timer.mode == FocusMode.flow && !isFlowFocus
          ? timer.totalSeconds
          : null,
    );
    notice = null;
    persist();
  }

  void skipToNext() {
    if (externalActionBusy) return;
    final revision = _intervalRevision;
    tick();
    if (revision != _intervalRevision) return;
    _prepareStep((timer.cycleStep + 1) % 8);
    notice = null;
    persist();
  }

  void jumpToStep(int step) {
    if (externalActionBusy) return;
    phaseForCycleStep(step); // Validate before settling or changing any state.
    if (step == timer.cycleStep) return;
    final revision = _intervalRevision;
    tick();
    if (revision != _intervalRevision) return;
    _prepareStep(step);
    notice = null;
    persist();
  }

  void skipBreak() {
    if (timer.phase != TimerPhase.focus) skipToNext();
  }

  /// Adjusts this interval only, retaining elapsed time and the running session.
  void adjustCurrent(int deltaMinutes) {
    if (externalActionBusy || isFlowFocus || deltaMinutes == 0) return;
    final revision = _intervalRevision;
    tick();
    if (revision != _intervalRevision) return;
    final before = remaining;
    final maximum = (timer.phase == TimerPhase.focus ? 120 : 60) * 60;
    // Removing time near expiry must not add time to reach the lower bound.
    if ((deltaMinutes < 0 && before <= 60) ||
        (deltaMinutes > 0 && before >= maximum)) {
      return;
    }
    final after = (before + deltaMinutes * 60).clamp(60, maximum);
    final difference = after - before;
    if (difference == 0) return;
    timer.totalSeconds += difference;
    timer.remaining = after;
    if (timer.running) {
      timer.endsAt = timer.endsAt!.add(Duration(seconds: difference));
    }
    timer.completedSessionId = null;
    _clearPending();
    notice = null;
    persist();
  }

  void requestJumpTo(int step) {
    phaseForCycleStep(step);
    if (step == timer.cycleStep) return;
    _request(
      PendingTimerAction(
        kind: 'jump',
        title: 'Switch to ${phaseForCycleStep(step).label.toLowerCase()}?',
        confirmLabel: 'Switch',
        targetStep: step,
      ),
    );
  }

  void requestSkip() => _request(
    PendingTimerAction(
      kind: 'skip',
      title:
          'Switch to ${phaseForCycleStep((timer.cycleStep + 1) % 8).label.toLowerCase()}?',
      confirmLabel: 'Switch',
      targetStep: (timer.cycleStep + 1) % 8,
    ),
  );

  void requestReset() => _request(
    PendingTimerAction(
      kind: 'reset',
      title: timer.phase == TimerPhase.focus
          ? 'Reset this stint?'
          : 'Reset this break?',
      confirmLabel: 'Reset',
    ),
  );

  void requestRoutine(String id) {
    final routine = _routine(id);
    _request(
      PendingTimerAction(
        kind: 'routine',
        title: 'Switch to ${routine.name}?',
        confirmLabel: 'Switch',
        routineId: id,
      ),
    );
  }

  void requestMode(FocusMode mode) {
    if (mode == timer.mode) return;
    _request(
      PendingTimerAction(
        kind: 'mode',
        title: 'Switch to ${mode == FocusMode.flow ? 'Flow' : 'Pomodoro'}?',
        confirmLabel: 'Switch',
        mode: mode,
      ),
    );
  }

  /// Interactive callers use requestMode, which confirms unfinished progress.
  void applyMode(FocusMode mode) {
    if (externalActionBusy || mode == timer.mode) return;
    tick();
    workspace.settings.focusMode = mode;
    timer.mode = mode;
    _prepareStep(
      timer.cycleStep.isEven ? timer.cycleStep : (timer.cycleStep + 1) % 8,
    );
    notice = null;
    persist();
  }

  /// A profile's timer is prepared only after its shared confirmation succeeds.
  /// This is allowed within the external action gate; other timer edits wait.
  void applyProfileTimer({
    required int focus,
    required int shortBreak,
    required int longBreak,
    required FocusMode mode,
  }) {
    if (focus < 1 ||
        focus > 120 ||
        shortBreak < 1 ||
        shortBreak > 60 ||
        longBreak < 1 ||
        longBreak > 60) {
      throw ArgumentError('Invalid profile durations.');
    }
    tick();
    final settings = workspace.settings;
    settings.focusMinutes = focus;
    settings.shortBreakMinutes = shortBreak;
    settings.longBreakMinutes = longBreak;
    settings.focusMode = mode;
    settings.preferredRoutineId = null;
    timer.mode = mode;
    _prepareStep(
      timer.cycleStep.isEven ? timer.cycleStep : (timer.cycleStep + 1) % 8,
    );
    notice = null;
    persist();
  }

  /// Commit active Flow time once, then offer a manually started break.
  bool finishFlow() {
    if (externalActionBusy || !isFlowFocus || timer.sessionId == null) {
      return false;
    }
    final milliseconds = _elapsedMilliseconds;
    if (milliseconds <= 0) return false;
    final sessionId = timer.sessionId!;
    final alreadyRecorded = workspace.sessions.any((s) => s.id == sessionId);
    final breakMinutes = (milliseconds / (5 * 60 * 1000)).ceil().clamp(1, 30);
    if (!alreadyRecorded) {
      workspace.sessions.insert(
        0,
        FocusSession(
          id: sessionId,
          taskId: timer.taskId,
          taskTitle: timer.taskTitle,
          projectName: timer.projectName,
          seconds: max(1, milliseconds ~/ 1000),
          finishedAt: now().toUtc(),
          mode: FocusMode.flow,
          continuationNote: workspace.settings.continuationNote,
        ),
      );
      timer.completedCount++;
    }
    _prepareStep(
      (timer.cycleStep + 1) % 8,
      completedSessionId: sessionId,
      totalSeconds: breakMinutes * 60,
    );
    notice = 'Focus complete. Take a break when you are ready.';
    persist();
    return !alreadyRecorded;
  }

  /// Profiles share the same discard confirmation as ordinary timer changes.
  /// No asynchronous configuration begins until the user confirms.
  void requestExternalAction({
    required String id,
    required String title,
    String confirmLabel = 'Switch',
    required FutureOr<void> Function() onConfirm,
  }) {
    _request(
      PendingTimerAction(
        kind: 'external',
        title: title,
        confirmLabel: confirmLabel,
        externalActionId: id,
        onConfirm: onConfirm,
      ),
    );
  }

  void _request(PendingTimerAction action) {
    if (externalActionBusy) return;
    final revision = _intervalRevision;
    tick();
    if (revision != _intervalRevision) return;
    if (!timerHasProgress) {
      _applyAction(action);
      return;
    }
    _pendingAction = action;
    _pendingRevision = _intervalRevision;
    notifyListeners();
  }

  void cancelPending() {
    tick();
    if (_pendingAction == null) return;
    _clearPending();
    notifyListeners();
  }

  void confirmPending() {
    tick();
    final action = _pendingAction;
    if (action == null) return;
    final current = _pendingRevision == _intervalRevision;
    _clearPending();
    if (current) {
      _applyAction(action);
    } else {
      notifyListeners();
    }
  }

  void _applyAction(PendingTimerAction action) {
    switch (action.kind) {
      case 'jump':
      case 'skip':
        jumpToStep(action.targetStep!);
      case 'reset':
        resetTimer();
      case 'routine':
        if (routines.any((routine) => routine.id == action.routineId)) {
          applyRoutine(action.routineId!);
        } else {
          notifyListeners();
        }
      case 'mode':
        applyMode(action.mode!);
      case 'external':
        unawaited(_applyExternalAction(action.onConfirm!));
    }
  }

  Future<void> _applyExternalAction(FutureOr<void> Function() action) async {
    _externalActionBusy = true;
    notifyListeners();
    try {
      await action();
    } catch (_) {
      showNotice('The profile could not be applied. Please try again.');
    } finally {
      _externalActionBusy = false;
      notifyListeners();
    }
  }

  void _clearPending() {
    _pendingAction = null;
    _pendingRevision = null;
  }

  /// Starts only the untouched interval offered by this exact completion.
  void startNextFromNotification({
    required String sessionId,
    required int cycleStep,
  }) {
    tick();
    if (!_matchesNotificationOffer(sessionId, cycleStep)) return;
    startTimer();
  }

  /// Skips only the untouched break offered by this exact completion.
  void skipOfferedFromNotification({
    required String sessionId,
    required int cycleStep,
  }) {
    tick();
    if (!_matchesNotificationOffer(sessionId, cycleStep) || cycleStep.isEven) {
      return;
    }
    _prepareStep((cycleStep + 1) % 8);
    notice = null;
    persist();
  }

  bool _matchesNotificationOffer(String sessionId, int cycleStep) =>
      sessionId.isNotEmpty &&
      cycleStep >= 0 &&
      cycleStep < 8 &&
      timer.completedSessionId == sessionId &&
      timer.cycleStep == cycleStep &&
      timer.phase == phaseForCycleStep(cycleStep) &&
      !timerHasProgress &&
      _pendingAction == null;

  /// Compatibility for the old duration dialog. New UI uses adjustCurrent.
  void setTimerMinutes(int minutes) {
    if (externalActionBusy || isFlowFocus) return;
    final maxMinutes = timer.phase == TimerPhase.focus ? 120 : 60;
    if (minutes < 1 || minutes > maxMinutes) {
      throw ArgumentError('Invalid timer duration.');
    }
    final wasRunning = timer.running;
    switch (timer.phase) {
      case TimerPhase.focus:
        workspace.settings.focusMinutes = minutes;
      case TimerPhase.shortBreak:
        workspace.settings.shortBreakMinutes = minutes;
      case TimerPhase.longBreak:
        workspace.settings.longBreakMinutes = minutes;
    }
    timer.totalSeconds = minutes * 60;
    timer.remaining = timer.totalSeconds;
    timer.sessionId = wasRunning ? newId() : null;
    timer.completedSessionId = null;
    timer.endsAt = wasRunning ? now().add(Duration(minutes: minutes)) : null;
    _intervalRevision++;
    _flowRunStartedAt = null;
    _clearPending();
    notice = null;
    persist();
  }

  void showNotice(String message) {
    notice = message;
    notifyListeners();
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  void _prepareStep(int step, {String? completedSessionId, int? totalSeconds}) {
    final phase = phaseForCycleStep(step);
    workspace.timer = FocusTimer(
      phase: phase,
      cycleStep: step,
      completedCount: timer.completedCount,
      totalSeconds: totalSeconds ?? workspace.settings.secondsFor(phase),
      remaining: totalSeconds ?? workspace.settings.secondsFor(phase),
      completedSessionId: completedSessionId,
      mode: timer.mode,
    );
    _intervalRevision++;
    _flowRunStartedAt = null;
    _clearPending();
  }

  void tick() {
    final seconds = remaining;
    // Refresh at local midnight and on timezone changes, even while idle.
    final calendarChanged = _calendarChanged();
    if (isFlowFocus) {
      final elapsed = elapsedSeconds;
      if (timer.running &&
          _elapsedMilliseconds - timer.elapsedMilliseconds >= 15000) {
        _lastElapsed = elapsed;
        persist();
      } else if (_lastElapsed != elapsed || calendarChanged) {
        _lastElapsed = elapsed;
        notifyListeners();
      }
      return;
    }
    if (timer.running && seconds <= 0) {
      final completedSessionId = timer.sessionId;
      if (timer.phase == TimerPhase.focus) {
        if (!workspace.sessions.any((s) => s.id == timer.sessionId)) {
          workspace.sessions.insert(
            0,
            FocusSession(
              id: timer.sessionId!,
              taskId: timer.taskId,
              taskTitle: timer.taskTitle,
              projectName: timer.projectName,
              seconds: timer.totalSeconds,
              // New records retain their absolute instant across relaunches
              // in another timezone. Legacy records remain untouched.
              finishedAt: timer.endsAt!.toUtc(),
              continuationNote: workspace.settings.continuationNote,
            ),
          );
          timer.completedCount++;
        }
        notice = 'Focus complete. Take a break when you are ready.';
      } else {
        notice = 'Break complete. Ready for your next stint?';
      }
      _prepareStep(
        (timer.cycleStep + 1) % 8,
        completedSessionId: completedSessionId,
      );
      _lastRemaining = timer.remaining;
      persist();
    } else if (_lastRemaining != seconds || calendarChanged) {
      _lastRemaining = seconds;
      notifyListeners();
    }
  }

  void updateSettings({
    required int focus,
    required int shortBreak,
    required int longBreak,
    required String appearance,
    List<FocusRoutine>? customRoutines,
    String? preferredRoutineId,
  }) {
    final custom = List<FocusRoutine>.of(
      customRoutines ?? workspace.settings.customRoutines,
    );
    final all = [...FocusRoutine.builtIns, ...custom];
    if (focus < 1 ||
        focus > 120 ||
        shortBreak < 1 ||
        shortBreak > 60 ||
        longBreak < 1 ||
        longBreak > 60 ||
        !['system', 'light', 'dark'].contains(appearance) ||
        custom.any((routine) => !routine.isValid) ||
        all.map((routine) => routine.id).toSet().length != all.length ||
        (preferredRoutineId != null &&
            !all.any((routine) => routine.id == preferredRoutineId))) {
      throw ArgumentError('Invalid settings.');
    }
    // Settings apply from the next interval, including when this one is idle.
    final s = workspace.settings;
    final previous = StintPreferences(
      focusMinutes: s.focusMinutes,
      shortBreakMinutes: s.shortBreakMinutes,
      longBreakMinutes: s.longBreakMinutes,
      appearance: s.appearance,
      customRoutines: List.of(s.customRoutines),
      preferredRoutineId: s.preferredRoutineId,
    );
    s.focusMinutes = focus;
    s.shortBreakMinutes = shortBreak;
    s.longBreakMinutes = longBreak;
    s.appearance = appearance;
    s.customRoutines
      ..clear()
      ..addAll(custom);
    s.preferredRoutineId = preferredRoutineId;
    _checkpointFlow();
    try {
      store.save(workspace);
      saveError = null;
    } catch (_) {
      // A failed Settings save keeps the sheet as a draft. Roll back only
      // preferences, never the timer or history that may have advanced.
      s.focusMinutes = previous.focusMinutes;
      s.shortBreakMinutes = previous.shortBreakMinutes;
      s.longBreakMinutes = previous.longBreakMinutes;
      s.appearance = previous.appearance;
      s.customRoutines
        ..clear()
        ..addAll(previous.customRoutines);
      s.preferredRoutineId = previous.preferredRoutineId;
      saveError =
          'The settings could not be saved. Your changes are still a draft. Try again.';
      notifyListeners();
      return;
    }
    if (_pendingAction?.routineId case final id?
        when !all.any((r) => r.id == id)) {
      _clearPending();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
