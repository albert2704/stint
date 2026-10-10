import 'dart:collection';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:stint/data/controller.dart';
import 'package:stint/data/models.dart';
import 'package:stint/data/progress.dart';
import 'package:stint/data/store.dart';

FocusSession stint(DateTime end, {int minutes = 25, String? id}) =>
    FocusSession(
      id: id ?? 'stint-${end.microsecondsSinceEpoch}-$minutes',
      taskTitle: 'Open focus',
      projectName: '',
      seconds: minutes * 60,
      finishedAt: end,
    );

/// Counts reads so a countdown can prove it never walks saved history.
class CountingSessions extends ListBase<FocusSession> {
  CountingSessions(this.items);
  final List<FocusSession> items;
  int reads = 0;
  @override
  int get length => items.length;
  @override
  set length(int value) => items.length = value;
  @override
  FocusSession operator [](int index) {
    reads++;
    return items[index];
  }

  @override
  void operator []=(int index, FocusSession value) => items[index] = value;
}

/// Allows a same-day OS timezone change to be observed without changing the
/// machine's clock or timezone during a test.
class TimezoneReading extends Fake implements DateTime {
  TimezoneReading(this.date, this.timeZoneOffset, this.timeZoneName);
  final DateTime date;
  @override
  final Duration timeZoneOffset;
  @override
  final String timeZoneName;
  @override
  DateTime toLocal() => this;
  @override
  int get year => date.year;
  @override
  int get month => date.month;
  @override
  int get day => date.day;
}

void main() {
  final friday = DateTime(2026, 10, 9, 12);

  group('ProgressSummary', () {
    test('buckets by the local day a session finished, across midnight', () {
      final s = ProgressSummary.from(
        [
          stint(DateTime(2026, 10, 8, 23, 50)),
          stint(DateTime(2026, 10, 9, 0, 10), minutes: 30),
          stint(DateTime(2026, 10, 9, 9)),
        ],
        now: friday,
        goal: 8,
      );
      expect(s.todayTotal.count, 2);
      expect(s.todayTotal.seconds, 55 * 60);
      expect(s.totalFor(DateTime(2026, 10, 8)).count, 1);
      expect(s.todaySessions.first.finishedAt, DateTime(2026, 10, 9, 9));
      expect(s.remainingToGoal, 6);
      expect(s.allTimeSeconds, 80 * 60);
      expect(
        s.todaySessions.last.finishedAt.subtract(
          Duration(seconds: s.todaySessions.last.seconds),
        ),
        DateTime(2026, 10, 8, 23, 40),
        reason: 'a stint crossing midnight belongs to the day it finished',
      );
    });

    test('UTC timestamps and offset timestamps use the local finish day', () {
      final localEnd = DateTime(2026, 10, 9, 0, 10);
      final utcEnd = localEnd.toUtc();
      final offsetTimestamp =
          '${utcEnd.add(const Duration(hours: 9)).toIso8601String().replaceFirst('Z', '')}+09:00';
      final s = ProgressSummary.from(
        [stint(utcEnd), stint(DateTime.parse(offsetTimestamp))],
        now: friday.toUtc(),
        goal: 8,
      );
      expect(s.today, DateTime(2026, 10, 9));
      expect(s.todayTotal.count, 2);
      expect(s.totalFor(localEnd).count, 2);
    });

    test('week starts follow the locale and future days are marked', () {
      final sessions = [stint(DateTime(2026, 10, 5, 10))];
      final monday = ProgressSummary.from(sessions, now: friday, goal: 8);
      expect(monday.weekStart(0), DateTime(2026, 10, 5));
      final days = monday.week(0);
      expect(days.first.count, 1);
      expect(days[4].day, monday.today);
      expect(days.where((d) => d.future).length, 2);
      final sunday = ProgressSummary.from(
        sessions,
        now: friday,
        goal: 8,
        firstDayOfWeekIndex: 0,
      );
      expect(sunday.weekStart(0), DateTime(2026, 10, 4));
      expect(sunday.weekStart(1), DateTime(2026, 9, 27));
      expect(sunday.week(0).where((d) => d.future).length, 1);
    });

    test('streak ends today, or yesterday when today is empty', () {
      final past = [
        stint(DateTime(2026, 10, 8, 9)),
        stint(DateTime(2026, 10, 7, 9)),
        stint(DateTime(2026, 10, 5, 9)),
      ];
      expect(
        ProgressSummary.from(past, now: friday, goal: 8).streak,
        2,
        reason: 'today has none yet, so yesterday and the day before count',
      );
      expect(
        ProgressSummary.from(
          [...past, stint(DateTime(2026, 10, 9, 9))],
          now: friday,
          goal: 8,
        ).streak,
        3,
      );
      expect(ProgressSummary.from(const [], now: friday, goal: 8).streak, 0);
    });

    test('goal days count only elapsed days that reached the goal', () {
      final s = ProgressSummary.from(
        [
          for (var i = 0; i < 2; i++) stint(DateTime(2026, 10, 5, 9 + i)),
          stint(DateTime(2026, 10, 6, 9)),
          for (var i = 0; i < 2; i++) stint(DateTime(2026, 10, 10, 9 + i)),
        ],
        now: friday,
        goal: 2,
      );
      final week = s.week(0);
      expect(s.elapsedDays(week), 5);
      expect(s.goalDays(week), 1);
      final lowerGoal = s.withPreferences(goal: 1, firstDayOfWeekIndex: 1);
      expect(lowerGoal.goalDays(lowerGoal.week(0)), 2);
      expect(lowerGoal.todaySessions, same(s.todaySessions));
      expect(lowerGoal.allTimeSeconds, s.allTimeSeconds);
      expect(lowerGoal.goalDays(lowerGoal.week(1)), 0);
      expect(lowerGoal.elapsedDays(lowerGoal.week(1)), 7);
    });

    test('week navigation reaches back to the oldest session', () {
      expect(
        ProgressSummary.from(const [], now: friday, goal: 8).maxWeeksBack,
        0,
      );
      expect(
        ProgressSummary.from(
          [stint(DateTime(2026, 9, 22, 9))],
          now: friday,
          goal: 8,
        ).maxWeeksBack,
        2,
      );
    });

    test('formats focus time', () {
      expect(formatFocusTime(25 * 60), '25m');
      expect(formatFocusTime(75 * 60), '1h 15m');
      expect(formatFocusTime(125 * 60), '2h 05m');
      expect(formatFocusTime(0), '0m');
    });
  });

  group('controller', () {
    late DateTime now;
    late MemoryWorkspaceStore store;
    late StintController c;
    setUp(() {
      now = DateTime(2026, 10, 9, 9);
      store = MemoryWorkspaceStore();
      c = StintController(store, now: () => now, tickAutomatically: false);
    });
    tearDown(() => c.dispose());

    test(
      'a finished focus counts once; skip, jump and reset count nothing',
      () {
        c.startFocus();
        now = now.add(const Duration(minutes: 2));
        c.skipToNext();
        c.jumpToStep(0);
        c.startTimer();
        now = now.add(const Duration(minutes: 1));
        c.resetTimer();
        expect(c.progress().todayTotal.count, 0);

        c.startTimer();
        now = now.add(const Duration(minutes: 25));
        c.tick();
        c.tick();
        expect(c.progress().todayTotal.count, 1);
        expect(c.progress().todayTotal.seconds, 1500);
      },
    );

    test('daily goal defaults, clamps, persists and is validated', () {
      expect(c.workspace.settings.dailyGoal, 8);
      c.setDailyGoal(3);
      expect(c.progress().goal, 3);
      expect(Workspace.decode(store.contents!).settings.dailyGoal, 3);
      c.setDailyGoal(0);
      expect(c.progress().goal, 1);
      expect(Workspace.decode(store.contents!).settings.dailyGoal, 1);
      c.setDailyGoal(17);
      expect(c.progress().goal, 16);
      expect(Workspace.decode(store.contents!).settings.dailyGoal, 16);

      final legacy = jsonDecode(c.workspace.encode()) as Map<String, dynamic>;
      (legacy['settings'] as Map).remove('dailyGoal');
      expect(Workspace.decode(jsonEncode(legacy)).settings.dailyGoal, 8);
      for (final invalid in [0, 17, -1, 1.5, '8']) {
        (legacy['settings'] as Map)['dailyGoal'] = invalid;
        expect(
          () => Workspace.decode(jsonEncode(legacy)),
          throwsFormatException,
          reason: 'invalid saved goal: $invalid',
        );
      }
    });

    test(
      'adjusted focus length is recorded; completed breaks do not count',
      () {
        now = DateTime(2026, 10, 9, 23, 50);
        c.startFocus();
        c.adjustCurrent(5);
        now = c.timer.endsAt!;
        final finish = now;
        c.tick();
        expect(c.workspace.sessions.single.seconds, 30 * 60);
        final recorded = c.workspace.sessions.single;
        expect(recorded.finishedAt.isUtc, isTrue);
        expect(recorded.finishedAt.isAtSameMomentAs(finish), isTrue);
        expect(recorded.toJson()['finishedAt'], endsWith('Z'));
        final restored = Workspace.decode(store.contents!).sessions.single;
        expect(restored.finishedAt.isAtSameMomentAs(finish), isTrue);
        expect(c.progress().todayTotal.count, 1);
        expect(c.progress().today, DateTime(2026, 10, 10));
        expect(c.progress().totalFor(DateTime(2026, 10, 9)).count, 0);
        c.startTimer();
        now = c.timer.endsAt!;
        c.tick();
        expect(c.workspace.sessions, hasLength(1));
        expect(c.progress().todayTotal.seconds, 30 * 60);
      },
    );

    test(
      'countdown and preference changes reuse cached history aggregates',
      () {
        final workspace = c.workspace;
        final sessions = CountingSessions([
          for (var i = 0; i < 100; i++) stint(now.subtract(Duration(days: i))),
        ]);
        c.workspace = Workspace(
          projects: workspace.projects,
          tasks: workspace.tasks,
          notes: workspace.notes,
          sessions: sessions,
          settings: workspace.settings,
          timer: workspace.timer,
        );
        c.startTimer();
        final initial = c.progress();
        sessions.reads = 0;
        for (var i = 0; i < 20; i++) {
          now = now.add(const Duration(seconds: 1));
          c.tick();
          expect(c.progress(), same(initial));
        }
        expect(sessions.reads, 40, reason: 'only first and last are inspected');

        c.workspace.settings.dailyGoal = 3;
        final changedGoal = c.progress();
        expect(changedGoal.goal, 3);
        expect(changedGoal.todaySessions, same(initial.todaySessions));
        final sundayWeek = c.progress(firstDayOfWeekIndex: 0);
        expect(sundayWeek.weekStart(0), DateTime(2026, 10, 4));
        expect(sundayWeek.todaySessions, same(initial.todaySessions));
        expect(sessions.reads, 44);
      },
    );

    test(
      'adding history and replacing a workspace invalidate cached counts',
      () {
        final empty = c.progress();
        c.workspace.sessions.add(stint(DateTime(2026, 10, 9, 8)));
        final one = c.progress();
        expect(one, isNot(same(empty)));
        expect(one.todayTotal.count, 1);
        c.workspace.sessions.insert(0, stint(DateTime(2026, 10, 9, 9)));
        expect(c.progress().todayTotal.count, 2);

        final replacement = Workspace.decode(c.workspace.encode());
        replacement.sessions[1] = stint(DateTime(2026, 10, 8, 8));
        c.workspace = replacement;
        expect(c.progress().todayTotal.count, 1);
        expect(c.progress().totalFor(DateTime(2026, 10, 8)).count, 1);
      },
    );

    test('today rolls over at midnight while the timer is idle', () {
      c.workspace.sessions.insert(0, stint(DateTime(2026, 10, 9, 8)));
      c.persist();
      expect(c.progress().todayTotal.count, 1);
      var notified = 0;
      c.addListener(() => notified++);
      c.tick();
      expect(notified, 0);
      now = DateTime(2026, 10, 10, 0, 0, 1);
      c.tick();
      expect(notified, 1);
      expect(c.progress().todayTotal.count, 0);
      expect(c.progress().streak, 1);

      now = DateTime(2026, 10, 9, 23, 50);
      c.tick();
      expect(notified, 2);
      expect(c.progress().todayTotal.count, 1);
    });

    test('same-day timezone changes refresh progress while idle', () {
      c.workspace.sessions.add(stint(DateTime(2026, 10, 9, 8)));
      now = TimezoneReading(now, const Duration(hours: 7), 'ICT');
      c.tick();
      final initial = c.progress();
      var notified = 0;
      c.addListener(() => notified++);
      now = TimezoneReading(now, const Duration(hours: 8), 'SGT');
      c.tick();
      final changedZone = c.progress();
      expect(notified, 1);
      expect(changedZone, isNot(same(initial)));
      expect(changedZone.todayTotal.count, 1);
      c.tick();
      expect(notified, 1);
      expect(c.progress(), same(changedZone));
    });
  });
}
