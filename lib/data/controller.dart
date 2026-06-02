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
  });

  final String kind;
  final String title;
  final String confirmLabel;
  final int? targetStep;
  final String? routineId;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'title': title,
    'confirmLabel': confirmLabel,
    if (targetStep != null) 'targetStep': targetStep,
    if (routineId != null) 'routineId': routineId,
  };
}

class DeskController extends ChangeNotifier {
  DeskController(
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
  (int, int, int, Duration, String)? _lastCalendar;
  Object? _progressSourceKey;
  ProgressSummary? _progressSource;
  final _progress = <(int, int), ProgressSummary>{};
  FocusTimer get timer => workspace.timer;
  int get remaining => timer.endsAt == null
      ? timer.remaining
      : min(
          timer.totalSeconds,
          max(
            0,
            (timer.endsAt!.difference(now()).inMilliseconds / 1000).ceil(),
          ),
        );
  bool get timerHasProgress =>
      timer.running || timer.remaining < timer.totalSeconds;

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
    if (_progressSourceKey != sourceKey) {
      _progressSourceKey = sourceKey;
      _progressSource = ProgressSummary.from(
        sessions,
        now: currentTime,
        goal: goal,
        firstDayOfWeekIndex: firstDayOfWeekIndex,
      );
      _progress.clear();
      _progress[(goal, firstDayOfWeekIndex)] = _progressSource!;
    }
    return _progress.putIfAbsent(
      (goal, firstDayOfWeekIndex),
      () => _progressSource!.withPreferences(
        goal: goal,
        firstDayOfWeekIndex: firstDayOfWeekIndex,
      ),
    );
  }

  /// Saves immediately; the Progress sheet has no Save button.
  void setDailyGoal(int goal) {
    final bounded = goal.clamp(1, DeskSettings.maxDailyGoal);
    if (workspace.settings.dailyGoal == bounded) return;
    workspace.settings.dailyGoal = bounded;
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
    try {
      store.save(workspace);
      saveError = null;
    } catch (_) {
      saveError =
          'The timer could not be saved. Keep this window open and try again.';
    }
    notifyListeners();
  }

  void startFocus() {
    selectPhase(TimerPhase.focus);
    startTimer();
  }

  /// Compatibility for old callers; cycle-track callers use requestJumpTo.
  void selectPhase(TimerPhase phase) {
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
    final wasRunning = timer.running;
    tick();
    if (wasRunning) return;
    timer.sessionId ??= newId();
    timer.completedSessionId = null;
    timer.endsAt = now().add(Duration(seconds: timer.remaining));
    _clearPending();
    notice = null;
    persist();
  }

  void pauseTimer() {
    if (!timer.running) return;
    if (remaining == 0) {
      tick();
      return;
    }
    timer.remaining = remaining;
    timer.endsAt = null;
    persist();
  }

  void resetTimer() {
    final revision = _intervalRevision;
    tick();
    if (revision != _intervalRevision) return;
    _prepareStep(timer.cycleStep);
    notice = null;
    persist();
  }

  void skipToNext() {
    final revision = _intervalRevision;
    tick();
    if (revision != _intervalRevision) return;
    _prepareStep((timer.cycleStep + 1) % 8);
    notice = null;
    persist();
  }

  void jumpToStep(int step) {
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
    if (deltaMinutes == 0) return;
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

  void _request(PendingTimerAction action) {
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

  void _prepareStep(int step, {String? completedSessionId}) {
    final phase = phaseForCycleStep(step);
    workspace.timer = FocusTimer(
      phase: phase,
      cycleStep: step,
      completedCount: timer.completedCount,
      totalSeconds: workspace.settings.secondsFor(phase),
      remaining: workspace.settings.secondsFor(phase),
      completedSessionId: completedSessionId,
    );
    _intervalRevision++;
    _clearPending();
  }

  void tick() {
    final seconds = remaining;
    // Refresh at local midnight and on timezone changes, even while idle.
    final calendarChanged = _calendarChanged();
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
    final previous = DeskSettings(
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
