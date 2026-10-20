import 'models.dart';

/// Local midnight of [time], used as the key for daily totals.
DateTime localDay(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime _addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// Finished focus stints and their length for one local calendar day.
class DayTotal {
  const DayTotal({
    required this.day,
    required this.count,
    required this.seconds,
    this.future = false,
  });
  final DateTime day;
  final int count;
  final int seconds;
  final bool future;
}

/// Finished focus time for one selected local calendar week.
class WeekTotal {
  const WeekTotal({required this.count, required this.seconds});
  final int count;
  final int seconds;
  int get typicalMinutes => count == 0 ? 0 : (seconds / count / 60).round();
}

/// Read-only view of saved focus sessions for the Progress sheet.
///
/// A session counts on the local day it finished. Only finished focus
/// intervals are ever recorded, so skips, jumps and resets never appear here.
/// Goal days are judged against the current goal; goals are not stored per day.
class ProgressSummary {
  ProgressSummary._({
    required this.today,
    required this.goal,
    required this.firstDayOfWeekIndex,
    required this.weeklyGoalMinutes,
    required Map<DateTime, (int, int)> days,
    required this.allTimeSeconds,
    required this.todaySessions,
    required DateTime? oldestDay,
  }) : _days = days,
       _oldestDay = oldestDay;

  factory ProgressSummary.from(
    Iterable<FocusSession> sessions, {
    required DateTime now,
    required int goal,
    int firstDayOfWeekIndex = 1,
    int weeklyGoalMinutes = StintPreferences.defaultWeeklyGoalMinutes,
  }) {
    RangeError.checkValueInInterval(firstDayOfWeekIndex, 0, 6);
    final today = localDay(now);
    final days = <DateTime, (int, int)>{};
    final todaySessions = <FocusSession>[];
    var allTime = 0;
    DateTime? oldest;
    for (final session in sessions) {
      final day = localDay(session.finishedAt);
      final (count, seconds) = days[day] ?? (0, 0);
      days[day] = (count + 1, seconds + session.seconds);
      allTime += session.seconds;
      if (oldest == null || day.isBefore(oldest)) oldest = day;
      if (day == today) todaySessions.add(session);
    }
    todaySessions.sort((a, b) => b.finishedAt.compareTo(a.finishedAt));
    return ProgressSummary._(
      today: today,
      goal: goal,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
      weeklyGoalMinutes: weeklyGoalMinutes,
      days: days,
      allTimeSeconds: allTime,
      todaySessions: List.unmodifiable(todaySessions),
      oldestDay: oldest,
    );
  }

  /// Local midnight today.
  final DateTime today;
  final int goal;
  final int weeklyGoalMinutes;

  /// 0 = Sunday … 6 = Saturday, as in `MaterialLocalizations`.
  final int firstDayOfWeekIndex;
  final int allTimeSeconds;

  /// Today's sessions, newest first.
  final List<FocusSession> todaySessions;
  final Map<DateTime, (int, int)> _days;
  final DateTime? _oldestDay;

  DayTotal totalFor(DateTime day) {
    final key = localDay(day);
    final (count, seconds) = _days[key] ?? (0, 0);
    return DayTotal(
      day: key,
      count: count,
      seconds: seconds,
      future: key.isAfter(today),
    );
  }

  DayTotal get todayTotal => totalFor(today);

  /// Reuses the day aggregates when only the goal or locale has changed.
  ProgressSummary withPreferences({
    required int goal,
    required int firstDayOfWeekIndex,
    int? weeklyGoalMinutes,
  }) => ProgressSummary._(
    today: today,
    goal: goal,
    firstDayOfWeekIndex: firstDayOfWeekIndex,
    weeklyGoalMinutes: weeklyGoalMinutes ?? this.weeklyGoalMinutes,
    days: _days,
    allTimeSeconds: allTimeSeconds,
    todaySessions: todaySessions,
    oldestDay: _oldestDay,
  );

  int get remainingToGoal => goal - todayTotal.count;

  DateTime _weekStartOf(DateTime day) {
    final weekdayIndex = day.weekday % 7; // Sunday = 0
    final offset = (weekdayIndex - firstDayOfWeekIndex + 7) % 7;
    return _addDays(day, -offset);
  }

  /// First day of the week [weeksBack] weeks before the current one.
  DateTime weekStart(int weeksBack) =>
      _addDays(_weekStartOf(today), -7 * weeksBack);

  /// Seven days of the week [weeksBack] weeks back, in display order.
  List<DayTotal> week(int weeksBack) {
    final start = weekStart(weeksBack);
    return [for (var i = 0; i < 7; i++) totalFor(_addDays(start, i))];
  }

  WeekTotal weekTotal(int weeksBack) {
    final days = week(weeksBack);
    return WeekTotal(
      count: days.fold(0, (sum, day) => sum + day.count),
      seconds: days.fold(0, (sum, day) => sum + day.seconds),
    );
  }

  /// How far back week navigation can go: the week holding the oldest session.
  int get maxWeeksBack {
    final oldest = _oldestDay;
    if (oldest == null || !oldest.isBefore(weekStart(0))) return 0;
    // Calendar dates, rather than local elapsed hours, stay exact across DST.
    final start = weekStart(0);
    final end = _weekStartOf(oldest);
    final days = DateTime.utc(
      start.year,
      start.month,
      start.day,
    ).difference(DateTime.utc(end.year, end.month, end.day)).inDays;
    return days ~/ 7;
  }

  /// Consecutive days with at least one stint, ending today, or yesterday when
  /// today has none yet.
  int get streak {
    var day = todayTotal.count > 0 ? today : _addDays(today, -1);
    var count = 0;
    while ((_days[day]?.$1 ?? 0) > 0) {
      count++;
      day = _addDays(day, -1);
    }
    return count;
  }

  /// Elapsed days in [days] (today and earlier).
  int elapsedDays(List<DayTotal> days) => days.where((d) => !d.future).length;

  /// Elapsed days in [days] that reached the current goal.
  int goalDays(List<DayTotal> days) =>
      days.where((d) => !d.future && d.count >= goal).length;
}

/// `1h 05m`, or `25m` under an hour.
String formatFocusTime(int seconds) {
  final minutes = (seconds / 60).round();
  final hours = minutes ~/ 60;
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}
