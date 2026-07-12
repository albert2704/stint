import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/store.dart';

class FailingStore extends MemoryWorkspaceStore {
  bool fail = false;
  @override
  void save(Workspace workspace) {
    if (fail) {
      throw const FileSystemException('Disk full');
    }
    super.save(workspace);
  }
}

Workspace legacyWorkspace(DateTime now) => Workspace(
  projects: [
    Project(
      id: 'legacy-project',
      name: 'Original project',
      icon: BoardIcon.study,
      color: BoardColor.purple,
    ),
  ],
  tasks: [
    StintTask(
      id: 'legacy-task',
      projectId: 'legacy-project',
      title: 'Original task',
      description: 'Keep this task and its linked note.',
      status: TaskStatus.doing,
      priority: Priority.high,
      noteIds: ['legacy-note'],
      plannedDate: now,
      createdAt: now.subtract(const Duration(days: 2)),
    ),
  ],
  notes: [
    StintNote(
      id: 'legacy-note',
      projectId: 'legacy-project',
      title: 'Original note',
      body: 'This writing should survive the Pomodoro-only update.',
      updatedAt: now.subtract(const Duration(days: 1)),
    ),
  ],
  sessions: [
    FocusSession(
      id: 'legacy-session',
      taskId: 'legacy-task',
      taskTitle: 'Original task',
      projectName: 'Original project',
      seconds: 1500,
      finishedAt: now.subtract(const Duration(hours: 1)),
    ),
  ],
  settings: StintPreferences(),
  timer: FocusTimer(
    remaining: 1200,
    totalSeconds: 1500,
    sessionId: 'legacy-paused-interval',
    taskId: 'legacy-task',
    taskTitle: 'Original task',
    projectName: 'Original project',
    completedCount: 1,
  ),
);

void main() {
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

  test(
    'Pomodoro actions preserve legacy projects, tasks, notes, and history',
    () {
      final legacy = legacyWorkspace(now);
      final originalProjects = legacy.projects.map((p) => p.toJson()).toList();
      final originalTasks = legacy.tasks.map((t) => t.toJson()).toList();
      final originalNotes = legacy.notes.map((n) => n.toJson()).toList();
      final originalSession = legacy.sessions.single.toJson();
      store.save(legacy);
      final c = StintController(store, now: () => now, tickAutomatically: false);
      addTearDown(c.dispose);
      c.startTimer();
      now = now.add(const Duration(minutes: 1));
      c.pauseTimer();
      c.setTimerMinutes(2);
      c.startTimer();
      now = c.timer.endsAt!;
      c.tick();
      c.selectPhase(TimerPhase.longBreak);
      c.setTimerMinutes(12);
      c.startTimer();
      c.resetTimer();
      c.skipBreak();
      c.startFocus();
      now = c.timer.endsAt!;
      c.tick();

      final saved = store.load()!;
      expect(saved.projects.map((p) => p.toJson()).toList(), originalProjects);
      expect(saved.tasks.map((t) => t.toJson()).toList(), originalTasks);
      expect(saved.notes.map((n) => n.toJson()).toList(), originalNotes);
      expect(
        saved.sessions.firstWhere((s) => s.id == 'legacy-session').toJson(),
        originalSession,
      );
      expect(saved.sessions, hasLength(3));
      expect(c.saveError, isNull);
    },
  );

  test('deadline survives relaunch and completion records once', () {
    controller.startFocus();
    now = now.add(const Duration(minutes: 30));
    final reopened = StintController(
      store,
      now: () => now,
      tickAutomatically: false,
    );
    addTearDown(reopened.dispose);
    expect(reopened.workspace.sessions, hasLength(1));
    expect(
      reopened.workspace.sessions.single.finishedAt,
      DateTime(2026, 10, 8, 10, 25).toUtc(),
    );
    expect(reopened.timer.phase, TimerPhase.shortBreak);
    expect(reopened.timer.running, isFalse);
    reopened.tick();
    reopened.tick();
    expect(reopened.workspace.sessions, hasLength(1));
    final twice = StintController(
      store,
      now: () => now,
      tickAutomatically: false,
    );
    addTearDown(twice.dispose);
    expect(twice.workspace.sessions, hasLength(1));
  });

  test('pause excludes paused time and settings preserve session duration', () {
    controller.startFocus();
    now = now.add(const Duration(minutes: 5));
    controller.pauseTimer();
    expect(controller.remaining, 1200);
    now = now.add(const Duration(hours: 2));
    controller.updateSettings(
      focus: 40,
      shortBreak: 7,
      longBreak: 20,
      appearance: 'dark',
    );
    expect(controller.timer.totalSeconds, 1500);
    expect(controller.remaining, 1200);
    controller.startTimer();
    now = now.add(const Duration(minutes: 20));
    controller.tick();
    expect(controller.workspace.sessions.single.seconds, 1500);
    expect(controller.remaining, 420);
  });

  test('four completed focus sessions produce a long break', () {
    for (var i = 0; i < 4; i++) {
      controller.startFocus();
      now = now.add(const Duration(minutes: 25));
      controller.tick();
    }
    expect(controller.timer.phase, TimerPhase.longBreak);
    expect(controller.remaining, 900);
    expect(controller.workspace.sessions, hasLength(4));
  });

  test('backward wall clock jump cannot create invalid remaining time', () {
    controller.startFocus();
    now = now.subtract(const Duration(hours: 2));
    controller.pauseTimer();
    expect(controller.remaining, 1500);
    expect(controller.saveError, isNull);
    expect(store.load()!.timer.remaining, 1500);
  });

  test(
    'selecting a phase stops the interval and clears legacy task context',
    () {
      store.save(legacyWorkspace(now));
      final c = StintController(store, now: () => now, tickAutomatically: false);
      addTearDown(c.dispose);
      c.startTimer();
      c.selectPhase(TimerPhase.longBreak);
      expect(c.timer.phase, TimerPhase.longBreak);
      expect(c.timer.running, isFalse);
      expect(c.timer.sessionId, isNull);
      expect(c.remaining, 900);
      expect(c.timer.completedCount, 1);
      expect(c.timer.taskId, isNull);
      expect(c.timer.taskTitle, isNot('Original task'));
      expect(c.timer.projectName, isEmpty);
      expect(c.workspace.sessions, hasLength(1));
      expect(store.load()!.timer.phase, TimerPhase.longBreak);
      c.selectPhase(TimerPhase.focus);
      expect(c.remaining, 1500);
      expect(c.timer.running, isFalse);
      expect(c.timer.completedCount, 1);
    },
  );

  test('malformed stored data and invalid legacy links are rejected', () {
    final j = jsonDecode(legacyWorkspace(now).encode()) as Map<String, dynamic>;
    j['tasks'][0]['noteIds'] = ['legacy-note', 'legacy-note'];
    expect(() => Workspace.decode(jsonEncode(j)), throwsFormatException);
    expect(() => Workspace.decode('{bad'), throwsFormatException);
    j['version'] = 900;
    expect(() => Workspace.decode(jsonEncode(j)), throwsFormatException);
  });

  test('failed write is visible and retry persists pending changes', () {
    final failing = FailingStore();
    final c = StintController(failing, tickAutomatically: false);
    addTearDown(c.dispose);
    failing.fail = true;
    c.setTimerMinutes(40);
    expect(c.saveError, isNotNull);
    expect(c.remaining, 2400);
    expect(c.workspace.settings.focusMinutes, 40);
    failing.fail = false;
    c.persist();
    expect(c.saveError, isNull);
    expect(failing.load()!.timer.remaining, 2400);
    expect(failing.load()!.settings.focusMinutes, 40);
  });

  test(
    'completed breaks offer idle focus without recording a focus session',
    () {
      controller.selectPhase(TimerPhase.shortBreak);
      controller.startTimer();
      now = controller.timer.endsAt!;
      controller.tick();
      expect(controller.timer.phase, TimerPhase.focus);
      expect(controller.timer.running, isFalse);
      expect(controller.remaining, 1500);
      expect(controller.timer.completedCount, 0);
      expect(controller.workspace.sessions, isEmpty);
      expect(controller.notice, contains('Break complete'));
    },
  );

  test('reset and skipped breaks do not create phantom completions', () {
    controller.startFocus();
    now = now.add(const Duration(minutes: 2));
    controller.resetTimer();
    expect(controller.remaining, 1500);
    expect(controller.timer.sessionId, isNull);
    controller.selectPhase(TimerPhase.shortBreak);
    controller.startTimer();
    now = now.add(const Duration(minutes: 1));
    controller.skipBreak();
    expect(controller.timer.phase, TimerPhase.focus);
    expect(controller.timer.running, isFalse);
    expect(controller.remaining, 1500);
    expect(controller.workspace.sessions, isEmpty);
    expect(store.load()!.timer.phase, TimerPhase.focus);
  });

  test(
    'atomic local storage survives corrupt main file and preserves evidence',
    () {
      final dir = Directory.systemTemp.createTempSync('stint-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final files = FileWorkspaceStore(dir);
      files.save(Workspace.empty());
      final w = files.load()!;
      w.settings.focusMinutes = 40;
      w.timer.totalSeconds = 2400;
      w.timer.remaining = 2400;
      files.save(w);
      expect(files.load()!.settings.focusMinutes, 40);
      expect(
        Workspace.decode(files.backup.readAsStringSync()).settings.focusMinutes,
        25,
      );
      files.file.writeAsStringSync('broken');
      expect(files.load, throwsFormatException);
      final restored = files.restorePrevious();
      expect(restored.settings.focusMinutes, 25);
      expect(files.load()!.settings.focusMinutes, 25);
      expect(
        dir.listSync().where((f) => f.path.contains('.damaged-')),
        hasLength(1),
      );
    },
  );
}
