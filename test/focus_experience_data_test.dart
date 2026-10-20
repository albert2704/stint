import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/progress.dart';
import 'package:stint/data/store.dart';

class RecoverableExperienceStore extends MemoryWorkspaceStore {
  bool fail = false;
  @override
  void save(Workspace workspace) {
    if (fail) throw StateError('Disk unavailable');
    super.save(workspace);
  }
}

FocusSession session(String id, DateTime finishedAt, int seconds) =>
    FocusSession(
      id: id,
      taskTitle: 'Open focus',
      projectName: '',
      seconds: seconds,
      finishedAt: finishedAt,
    );

void main() {
  test(
    'unchanged note and weekly goal retry after a recovered save failure',
    () {
      final store = RecoverableExperienceStore();
      final controller = StintController(store, tickAutomatically: false);
      addTearDown(controller.dispose);
      store.fail = true;
      controller.setContinuationNote('Next: finish login');
      expect(controller.saveError, isNotNull);
      store.fail = false;
      controller.setContinuationNote('Next: finish login');
      expect(controller.saveError, isNull);
      expect(store.load()!.settings.continuationNote, 'Next: finish login');
      store.fail = true;
      controller.setWeeklyGoalMinutes(900);
      expect(controller.saveError, isNotNull);
      store.fail = false;
      controller.setWeeklyGoalMinutes(900);
      expect(controller.saveError, isNull);
      expect(store.load()!.settings.weeklyGoalMinutes, 900);
    },
  );

  test('legacy workspaces use defaults without altering existing records', () {
    final workspace = Workspace.empty();
    workspace.sessions.add(session('older', DateTime(2025, 12, 31, 20), 1500));
    final data = jsonDecode(workspace.encode()) as Map<String, dynamic>;
    for (final key in ['focusMode', 'weeklyGoalMinutes', 'continuationNote']) {
      (data['settings'] as Map).remove(key);
    }
    for (final key in ['mode', 'elapsedMilliseconds', 'flowStartedAt']) {
      (data['timer'] as Map).remove(key);
    }
    for (final entry in data['sessions'] as List) {
      (entry as Map).remove('mode');
      entry.remove('continuationNote');
    }
    final restored = Workspace.decode(jsonEncode(data));
    expect(restored.settings.focusMode, FocusMode.pomodoro);
    expect(restored.settings.weeklyGoalMinutes, 600);
    expect(restored.settings.continuationNote, '');
    expect(restored.timer.mode, FocusMode.pomodoro);
    expect(restored.timer.elapsedMilliseconds, 0);
    expect(restored.sessions.single.seconds, 1500);
    expect(restored.sessions.single.finishedAt, DateTime(2025, 12, 31, 20));
    expect(restored.sessions.single.mode, FocusMode.pomodoro);
    expect(Workspace.decode(restored.encode()).sessions, hasLength(1));
  });

  test('malformed new preference and Flow fields are rejected', () {
    void invalidSetting(String key, Object? value) {
      final data =
          jsonDecode(Workspace.empty().encode()) as Map<String, dynamic>;
      data['settings'][key] = value;
      expect(
        () => Workspace.decode(jsonEncode(data)),
        throwsFormatException,
        reason: '$key: $value',
      );
    }

    for (final value in [0, 29, 31, 6001, -30, 30.5, '600']) {
      invalidSetting('weeklyGoalMinutes', value);
    }
    invalidSetting('focusMode', 'unknown');
    invalidSetting('continuationNote', 1);
    invalidSetting('continuationNote', 'x' * 241);
    invalidSetting('continuationNote', '  padded  ');
    invalidSetting('continuationNote', 'multiple\nlines');

    for (final change in <Map<String, dynamic>>[
      {'mode': 'unknown'},
      {'elapsedMilliseconds': -1},
      {'elapsedMilliseconds': 0.5},
      {'elapsedMilliseconds': 1},
      {'flowStartedAt': DateTime(2026, 10, 20).toIso8601String()},
      {'mode': 'flow', 'endsAt': DateTime(2026, 10, 20).toIso8601String()},
      {'mode': 'flow', 'elapsedMilliseconds': 1},
      {'mode': 'flow', 'flowStartedAt': 'not a date'},
    ]) {
      final data =
          jsonDecode(Workspace.empty().encode()) as Map<String, dynamic>;
      (data['timer'] as Map).addAll(change);
      expect(
        () => Workspace.decode(jsonEncode(data)),
        throwsFormatException,
        reason: '$change',
      );
    }
  });

  test('continuation trims, stays one line, bounds Unicode, and clears', () {
    final store = MemoryWorkspaceStore();
    final controller = StintController(store, tickAutomatically: false);
    addTearDown(controller.dispose);
    controller.setContinuationNote(' \n Next:  finish\tlogin redirect \n');
    expect(
      controller.workspace.settings.continuationNote,
      'Next: finish login redirect',
    );
    expect(
      store.load()!.settings.continuationNote,
      'Next: finish login redirect',
    );
    controller.setContinuationNote('🌳' * 241);
    final note = controller.workspace.settings.continuationNote;
    expect(note.runes.length, 240);
    expect(note, '🌳' * 240);
    expect(store.load()!.settings.continuationNote, note);
    controller.requestMode(FocusMode.flow);
    expect(controller.workspace.settings.continuationNote, note);
    controller.setContinuationNote('   ');
    expect(store.load()!.settings.continuationNote, '');
  });

  test(
    'weekly goals clamp, round to steps, save, and retain cached day totals',
    () {
      final store = MemoryWorkspaceStore();
      final controller = StintController(store, tickAutomatically: false);
      addTearDown(controller.dispose);
      final initial = controller.progress();
      expect(initial.weeklyGoalMinutes, 600);
      controller.setWeeklyGoalMinutes(0);
      expect(controller.progress().weeklyGoalMinutes, 30);
      expect(store.load()!.settings.weeklyGoalMinutes, 30);
      controller.setWeeklyGoalMinutes(6001);
      expect(store.load()!.settings.weeklyGoalMinutes, 6000);
      controller.setWeeklyGoalMinutes(615);
      final changed = controller.progress();
      expect(changed.weeklyGoalMinutes, 630);
      expect(changed.todaySessions, same(initial.todaySessions));
      expect(changed.weekTotal(0).count, 0);
      expect(changed.weekTotal(0).seconds, 0);
      expect(changed.weekTotal(0).typicalMinutes, 0);
    },
  );

  test(
    'weekly metrics use the selected calendar week across year boundaries',
    () {
      final summary = ProgressSummary.from(
        [
          session('previous', DateTime(2025, 12, 28, 23, 59, 59), 1800),
          session('monday', DateTime(2025, 12, 29), 1490),
          session('year-end', DateTime(2025, 12, 31, 23, 59), 3010),
          session('sunday', DateTime(2026, 1, 4, 23, 59, 59), 3600),
          session('next', DateTime(2026, 1, 5), 60),
        ],
        now: DateTime(2026, 1, 5, 12),
        goal: 8,
      );
      expect(summary.weekStart(1), DateTime(2025, 12, 29));
      final previous = summary.weekTotal(1);
      expect(previous.count, 3);
      expect(previous.seconds, 8100);
      expect(previous.typicalMinutes, 45);
      expect(summary.weekTotal(0).count, 1);
      expect(summary.weekTotal(0).seconds, 60);
      expect(summary.weekTotal(0).typicalMinutes, 1);
      expect(summary.weekTotal(2).count, 1);

      final sundayFirst = summary.withPreferences(
        goal: 8,
        firstDayOfWeekIndex: 0,
      );
      expect(sundayFirst.weekStart(0), DateTime(2026, 1, 4));
      expect(sundayFirst.weekTotal(0).count, 2);
      expect(sundayFirst.weekTotal(0).seconds, 3660);
      expect(sundayFirst.weekTotal(0).typicalMinutes, 31);
      expect(sundayFirst.weekTotal(1).count, 3);
      expect(summary.weekTotal(3).typicalMinutes, 0);
    },
  );

  test('UTC completion instants belong to their local calendar week', () {
    final localStart = DateTime(2026, 10, 19);
    final summary = ProgressSummary.from(
      [
        session(
          'before',
          localStart.subtract(const Duration(seconds: 1)).toUtc(),
          300,
        ),
        session('at', localStart.toUtc(), 599),
      ],
      now: DateTime(2026, 10, 20),
      goal: 8,
    );
    expect(summary.weekTotal(1).count, 1);
    expect(summary.weekTotal(0).count, 1);
    expect(summary.weekTotal(0).seconds, 599);
    expect(summary.weekTotal(0).typicalMinutes, 10);
  });
}
