import 'dart:convert';
import 'dart:math';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 32).toRadixString(36)}';

enum TaskStatus { todo, doing, done }

enum Priority { low, normal, high }

enum TimerPhase { focus, shortBreak, longBreak }

TimerPhase phaseForCycleStep(int step) {
  if (step < 0 || step > 7) throw RangeError.range(step, 0, 7, 'step');
  if (step == 7) return TimerPhase.longBreak;
  return step.isEven ? TimerPhase.focus : TimerPhase.shortBreak;
}

int _legacyCycleStep(TimerPhase phase, int completedCount) => switch (phase) {
  TimerPhase.focus => 2 * (completedCount % 4),
  // Old manual phase selection allowed a short break before any completions.
  TimerPhase.shortBreak => max(1, 2 * (completedCount % 4) - 1),
  TimerPhase.longBreak => 7,
};

enum BoardIcon { board, work, code, study, creative, rocket, home, favorite }

enum BoardColor { forest, blue, purple, rose, orange, teal }

extension TaskStatusLabel on TaskStatus {
  String get label => switch (this) {
    TaskStatus.todo => 'To do',
    TaskStatus.doing => 'Doing',
    TaskStatus.done => 'Done',
  };
}

extension PhaseLabel on TimerPhase {
  String get label => switch (this) {
    TimerPhase.focus => 'Focus',
    TimerPhase.shortBreak => 'Short break',
    TimerPhase.longBreak => 'Long break',
  };
}

class Project {
  Project({
    required this.id,
    required this.name,
    this.icon = BoardIcon.board,
    this.color = BoardColor.forest,
  });
  final String id;
  String name;
  BoardIcon icon;
  BoardColor color;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon.name,
    'color': color.name,
  };
  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: j['id'] as String,
    name: j['name'] as String,
    // Older workspaces have no appearance fields. Unknown future choices also
    // fall back safely without losing the project or its linked records.
    icon: BoardIcon.values.firstWhere(
      (icon) => icon.name == j['icon'],
      orElse: () => BoardIcon.board,
    ),
    color: BoardColor.values.firstWhere(
      (color) => color.name == j['color'],
      orElse: () => BoardColor.forest,
    ),
  );
}

class DeskTask {
  DeskTask({
    required this.id,
    required this.projectId,
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = Priority.normal,
    this.plannedDate,
    List<String>? noteIds,
    DateTime? createdAt,
    this.completedAt,
  }) : noteIds = noteIds ?? [],
       createdAt = createdAt ?? DateTime.now();
  final String id;
  String projectId;
  String title;
  String description;
  TaskStatus status;
  Priority priority;
  DateTime? plannedDate;
  List<String> noteIds;
  final DateTime createdAt;
  DateTime? completedAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'description': description,
    'status': status.name,
    'priority': priority.name,
    'plannedDate': plannedDate?.toIso8601String(),
    'noteIds': noteIds,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
  factory DeskTask.fromJson(Map<String, dynamic> j) => DeskTask(
    id: j['id'] as String,
    projectId: j['projectId'] as String,
    title: j['title'] as String,
    description: j['description'] as String,
    status: TaskStatus.values.byName(j['status'] as String),
    priority: Priority.values.byName(j['priority'] as String),
    plannedDate: j['plannedDate'] == null
        ? null
        : DateTime.parse(j['plannedDate'] as String),
    noteIds: (j['noteIds'] as List).cast<String>(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    completedAt: j['completedAt'] == null
        ? null
        : DateTime.parse(j['completedAt'] as String),
  );
}

class DeskNote {
  DeskNote({
    required this.id,
    required this.projectId,
    this.title = 'Untitled note',
    this.body = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();
  final String id;
  String projectId;
  String title;
  String body;
  DateTime updatedAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory DeskNote.fromJson(Map<String, dynamic> j) => DeskNote(
    id: j['id'] as String,
    projectId: j['projectId'] as String,
    title: j['title'] as String,
    body: j['body'] as String,
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}

class FocusSession {
  FocusSession({
    required this.id,
    required this.taskTitle,
    required this.projectName,
    required this.seconds,
    required this.finishedAt,
    this.taskId,
  });
  final String id;
  final String? taskId;
  final String taskTitle;
  final String projectName;
  final int seconds;
  final DateTime finishedAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'taskTitle': taskTitle,
    'projectName': projectName,
    'seconds': seconds,
    'finishedAt': finishedAt.toIso8601String(),
  };
  factory FocusSession.fromJson(Map<String, dynamic> j) => FocusSession(
    id: j['id'] as String,
    taskId: j['taskId'] as String?,
    taskTitle: j['taskTitle'] as String,
    projectName: j['projectName'] as String,
    seconds: j['seconds'] as int,
    finishedAt: DateTime.parse(j['finishedAt'] as String),
  );
}

class FocusRoutine {
  const FocusRoutine({
    required this.id,
    required this.name,
    required this.focusMinutes,
    required this.shortBreakMinutes,
    required this.longBreakMinutes,
  });

  static const builtIns = [
    FocusRoutine(
      id: 'quick',
      name: 'Quick focus',
      focusMinutes: 15,
      shortBreakMinutes: 3,
      longBreakMinutes: 15,
    ),
    FocusRoutine(
      id: 'classic',
      name: 'Classic',
      focusMinutes: 25,
      shortBreakMinutes: 5,
      longBreakMinutes: 15,
    ),
    FocusRoutine(
      id: 'deep',
      name: 'Deep work',
      focusMinutes: 50,
      shortBreakMinutes: 10,
      longBreakMinutes: 30,
    ),
  ];

  final String id;
  final String name;
  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  bool get isValid =>
      id.trim().isNotEmpty &&
      name.trim().isNotEmpty &&
      name.trim().length <= 80 &&
      focusMinutes >= 1 &&
      focusMinutes <= 120 &&
      shortBreakMinutes >= 1 &&
      shortBreakMinutes <= 60 &&
      longBreakMinutes >= 1 &&
      longBreakMinutes <= 60;

  bool matches(DeskSettings settings) =>
      focusMinutes == settings.focusMinutes &&
      shortBreakMinutes == settings.shortBreakMinutes &&
      longBreakMinutes == settings.longBreakMinutes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
  };

  factory FocusRoutine.fromJson(Map<String, dynamic> json) {
    final routine = FocusRoutine(
      id: json['id'] as String,
      name: json['name'] as String,
      focusMinutes: json['focusMinutes'] as int,
      shortBreakMinutes: json['shortBreakMinutes'] as int,
      longBreakMinutes: json['longBreakMinutes'] as int,
    );
    if (!routine.isValid) {
      throw const FormatException('Invalid saved routine.');
    }
    return routine;
  }
}

class DeskSettings {
  DeskSettings({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.appearance = 'system',
    List<FocusRoutine>? customRoutines,
    this.preferredRoutineId,
    this.dailyGoal = defaultDailyGoal,
  }) : customRoutines = customRoutines ?? [];
  static const defaultDailyGoal = 8;
  static const maxDailyGoal = 16;
  int focusMinutes;
  int shortBreakMinutes;
  int longBreakMinutes;
  String appearance;
  final List<FocusRoutine> customRoutines;
  String? preferredRoutineId;
  // Finished focus stints per day, 1 to [maxDailyGoal].
  int dailyGoal;
  int secondsFor(TimerPhase phase) =>
      60 *
      switch (phase) {
        TimerPhase.focus => focusMinutes,
        TimerPhase.shortBreak => shortBreakMinutes,
        TimerPhase.longBreak => longBreakMinutes,
      };
  Map<String, dynamic> toJson() => {
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'appearance': appearance,
    'customRoutines': customRoutines
        .map((routine) => routine.toJson())
        .toList(),
    'preferredRoutineId': preferredRoutineId,
    'dailyGoal': dailyGoal,
  };
  factory DeskSettings.fromJson(Map<String, dynamic> j) => DeskSettings(
    focusMinutes: j['focusMinutes'] as int,
    shortBreakMinutes: j['shortBreakMinutes'] as int,
    longBreakMinutes: j['longBreakMinutes'] as int,
    appearance: j['appearance'] as String,
    customRoutines: (j['customRoutines'] as List?)
        ?.map((value) => FocusRoutine.fromJson(value as Map<String, dynamic>))
        .toList(),
    preferredRoutineId: j['preferredRoutineId'] as String?,
    // Older workspaces have no goal and start with the default.
    dailyGoal: j['dailyGoal'] as int? ?? defaultDailyGoal,
  );
}

class FocusTimer {
  FocusTimer({
    this.phase = TimerPhase.focus,
    this.remaining = 1500,
    this.totalSeconds = 1500,
    this.endsAt,
    this.sessionId,
    this.taskId,
    this.taskTitle = 'Open focus',
    this.projectName = '',
    this.completedCount = 0,
    int? cycleStep,
    this.completedSessionId,
  }) : cycleStep = cycleStep ?? _legacyCycleStep(phase, completedCount);
  TimerPhase phase;
  int remaining;
  int totalSeconds;
  DateTime? endsAt;
  String? sessionId;
  String? taskId;
  String taskTitle;
  String projectName;
  int completedCount;
  int cycleStep;
  // The completion that offered this untouched idle interval. Notification
  // actions must match this context, including after a process restart.
  String? completedSessionId;
  bool get running => endsAt != null;
  Map<String, dynamic> toJson() => {
    'phase': phase.name,
    'remaining': remaining,
    'totalSeconds': totalSeconds,
    'endsAt': endsAt?.toIso8601String(),
    'sessionId': sessionId,
    'taskId': taskId,
    'taskTitle': taskTitle,
    'projectName': projectName,
    'completedCount': completedCount,
    'cycleStep': cycleStep,
    'completedSessionId': completedSessionId,
  };
  factory FocusTimer.fromJson(Map<String, dynamic> j) => FocusTimer(
    phase: TimerPhase.values.byName(j['phase'] as String),
    remaining: j['remaining'] as int,
    totalSeconds: j['totalSeconds'] as int,
    endsAt: j['endsAt'] == null ? null : DateTime.parse(j['endsAt'] as String),
    sessionId: j['sessionId'] as String?,
    taskId: j['taskId'] as String?,
    taskTitle: j['taskTitle'] as String,
    projectName: j['projectName'] as String,
    completedCount: j['completedCount'] as int,
    cycleStep: j['cycleStep'] as int?,
    completedSessionId: j['completedSessionId'] as String?,
  );
}

class Workspace {
  Workspace({
    required this.projects,
    required this.tasks,
    required this.notes,
    required this.sessions,
    required this.settings,
    required this.timer,
  });
  final List<Project> projects;
  final List<DeskTask> tasks;
  final List<DeskNote> notes;
  final List<FocusSession> sessions;
  final DeskSettings settings;
  FocusTimer timer;

  factory Workspace.empty() => Workspace(
    projects: [Project(id: newId(), name: 'Personal')],
    tasks: [],
    notes: [],
    sessions: [],
    settings: DeskSettings(),
    timer: FocusTimer(),
  );
  String encode() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'projects': projects.map((x) => x.toJson()).toList(),
    'tasks': tasks.map((x) => x.toJson()).toList(),
    'notes': notes.map((x) => x.toJson()).toList(),
    'sessions': sessions.map((x) => x.toJson()).toList(),
    'settings': settings.toJson(),
    'timer': timer.toJson(),
  });

  factory Workspace.decode(String source) {
    try {
      final j = jsonDecode(source) as Map<String, dynamic>;
      if (j['version'] != 1) {
        throw const FormatException('This workspace version is not supported.');
      }
      final w = Workspace(
        projects: (j['projects'] as List)
            .map((x) => Project.fromJson(x as Map<String, dynamic>))
            .toList(),
        tasks: (j['tasks'] as List)
            .map((x) => DeskTask.fromJson(x as Map<String, dynamic>))
            .toList(),
        notes: (j['notes'] as List)
            .map((x) => DeskNote.fromJson(x as Map<String, dynamic>))
            .toList(),
        sessions: (j['sessions'] as List)
            .map((x) => FocusSession.fromJson(x as Map<String, dynamic>))
            .toList(),
        settings: DeskSettings.fromJson(j['settings'] as Map<String, dynamic>),
        timer: FocusTimer.fromJson(j['timer'] as Map<String, dynamic>),
      );
      final projectIds = w.projects.map((p) => p.id).toSet();
      final noteIds = w.notes.map((n) => n.id).toSet();
      final ids = [
        ...w.projects.map((x) => x.id),
        ...w.tasks.map((x) => x.id),
        ...w.notes.map((x) => x.id),
        ...w.sessions.map((x) => x.id),
      ];
      if (w.projects.isEmpty ||
          ids.any((id) => id.isEmpty) ||
          ids.toSet().length != ids.length ||
          w.projects.any((p) => p.name.trim().isEmpty) ||
          w.tasks.any(
            (t) =>
                t.title.trim().isEmpty ||
                !projectIds.contains(t.projectId) ||
                t.noteIds.toSet().length != t.noteIds.length ||
                t.noteIds.any((id) => !noteIds.contains(id)),
          ) ||
          w.notes.any((n) => !projectIds.contains(n.projectId)) ||
          w.sessions.any((s) => s.seconds <= 0)) {
        throw const FormatException(
          'Workspace contains invalid records or links.',
        );
      }
      final s = w.settings;
      final routineIds = s.customRoutines.map((routine) => routine.id).toSet();
      if (s.focusMinutes < 1 ||
          s.focusMinutes > 120 ||
          s.shortBreakMinutes < 1 ||
          s.shortBreakMinutes > 60 ||
          s.longBreakMinutes < 1 ||
          s.longBreakMinutes > 60 ||
          !['system', 'light', 'dark'].contains(s.appearance) ||
          s.dailyGoal < 1 ||
          s.dailyGoal > DeskSettings.maxDailyGoal ||
          routineIds.length != s.customRoutines.length ||
          s.customRoutines.any(
            (routine) =>
                !routine.isValid ||
                FocusRoutine.builtIns.any(
                  (builtIn) => builtIn.id == routine.id,
                ),
          )) {
        throw const FormatException('Invalid workspace settings.');
      }
      final t = w.timer;
      if (t.totalSeconds <= 0 ||
          t.remaining < 0 ||
          t.remaining > t.totalSeconds ||
          t.completedCount < 0 ||
          t.cycleStep < 0 ||
          t.cycleStep > 7 ||
          phaseForCycleStep(t.cycleStep) != t.phase ||
          t.completedSessionId == '' ||
          (t.running && t.sessionId == null) ||
          (t.taskId != null && !w.tasks.any((task) => task.id == t.taskId))) {
        throw const FormatException('Invalid timer state.');
      }
      return w;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('This file is not a valid Stint workspace.');
    }
  }
}

bool sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}
