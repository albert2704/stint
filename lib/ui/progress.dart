import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/controller.dart';
import '../data/models.dart';
import '../data/progress.dart';
import 'theme.dart';

/// Material exposes localized medium dates and narrow weekdays, but no short
/// weekday getter. Reuse its abbreviated weekday where the month/day can be
/// separated; unusual locale patterns still get a localized narrow label.
String _weekday(BuildContext context, DateTime day) {
  final localizations = MaterialLocalizations.of(context);
  final medium = localizations.formatMediumDate(day);
  final monthDay = localizations.formatShortMonthDay(day);
  if (!medium.contains(monthDay)) {
    return localizations.narrowWeekdays[day.weekday % 7];
  }
  return medium
      .replaceFirst(monthDay, '')
      .replaceAll(RegExp(r'^[\s,،、，()\[\]（）·]+|[\s,،、，()\[\]（）·]+$'), '');
}

String _plural(int n, String one, String many) => n == 1 ? one : many;

int _firstDayOfWeek(BuildContext context) =>
    MaterialLocalizations.of(context).firstDayOfWeekIndex;

final _progressNavigators = <NavigatorState>{};

Future<void> showStintProgress(
  BuildContext context,
  DeskController controller,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (!_progressNavigators.add(navigator)) return;
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => StintProgress(controller: controller),
    );
  } finally {
    _progressNavigators.remove(navigator);
  }
}

/// Header entry point: today's count against the daily goal.
class ProgressButton extends StatelessWidget {
  const ProgressButton({
    super.key,
    required this.controller,
    required this.onPressed,
  });
  final DeskController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final today = controller
        .progress(firstDayOfWeekIndex: _firstDayOfWeek(context))
        .todayTotal
        .count;
    final goal = controller.workspace.settings.dailyGoal;
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: 'Progress, $today of $goal stints today',
        child: Tooltip(
          message: 'Progress',
          excludeFromSemantics: true,
          child: TextButton(
            key: const Key('progress-button'),
            onPressed: onPressed,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart_rounded, size: 16, color: colors.ink2),
                  const SizedBox(width: 6),
                  Text(
                    '$today/$goal',
                    style: TextStyle(
                      fontFamily: 'MartianMono',
                      fontSize: 12,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StintProgress extends StatefulWidget {
  const StintProgress({super.key, required this.controller});
  final DeskController controller;
  @override
  State<StintProgress> createState() => _StintProgressState();
}

class _StintProgressState extends State<StintProgress> {
  int weeksBack = 0;

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    return Dialog.fullscreen(
      key: const Key('progress-sheet'),
      backgroundColor: colors.ground,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'Progress',
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final summary = widget.controller.progress(
                firstDayOfWeekIndex: _firstDayOfWeek(context),
              );
              final shownWeeksBack = math.min(weeksBack, summary.maxWeeksBack);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: const Text(
                              'Progress',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close progress',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: colors.line),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TodaySection(
                            summary: summary,
                            controller: widget.controller,
                          ),
                          if (widget.controller.saveError != null) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.controller.saveError!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colors.error,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: widget.controller.persist,
                                    child: const Text('Retry save'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          _WeekSection(
                            summary: summary,
                            weeksBack: shownWeeksBack,
                            onPrevious: shownWeeksBack < summary.maxWeeksBack
                                ? () => setState(
                                    () => weeksBack = shownWeeksBack + 1,
                                  )
                                : null,
                            onNext: shownWeeksBack > 0
                                ? () => setState(
                                    () => weeksBack = shownWeeksBack - 1,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 24),
                          _SummaryTiles(
                            summary: summary,
                            week: summary.week(shownWeeksBack),
                          ),
                          const SizedBox(height: 24),
                          _TodayList(summary: summary),
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              'Only finished focus stints count. Your history stays on this Mac.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.76,
        color: StintColors.of(context).muted,
      ),
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    return MergeSemantics(
      child: Semantics(
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(32),
              fixedSize: const Size.square(32),
              padding: EdgeInsets.zero,
              side: BorderSide(color: colors.line),
              backgroundColor: colors.surface,
              disabledBackgroundColor: colors.surface,
              disabledForegroundColor: colors.muted.withValues(alpha: .4),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.summary, required this.controller});
  final ProgressSummary summary;
  final DeskController controller;

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final today = summary.todayTotal;
    final goal = summary.goal;
    final left = summary.remainingToGoal;
    final caption = left > 1
        ? '$left more to reach today’s goal.'
        : left == 1
        ? '1 more to reach today’s goal.'
        : 'Goal met. Anything more is a bonus.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('Today'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${today.count}',
                    key: const Key('progress-today-count'),
                    style: TextStyle(
                      fontFamily: 'MartianMono',
                      fontSize: 56,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -2.8,
                      height: 1,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'of $goal ${_plural(goal, 'stint', 'stints')}',
                      style: TextStyle(fontSize: 15, color: colors.ink2),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatFocusTime(today.seconds),
                      style: TextStyle(
                        fontFamily: 'MartianMono',
                        color: colors.ink,
                      ),
                    ),
                    const TextSpan(text: ' focused'),
                  ],
                ),
                style: TextStyle(fontSize: 14, color: colors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < goal; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: i < today.count ? colors.focus : colors.track,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              if (today.count > goal) ...[
                const SizedBox(width: 8),
                Text(
                  '+${today.count - goal}',
                  style: TextStyle(
                    fontFamily: 'MartianMono',
                    fontSize: 11,
                    color: colors.focusText,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final goalControl = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Daily goal',
                  style: TextStyle(fontSize: 13, color: colors.ink2),
                ),
                const SizedBox(width: 8),
                _StepButton(
                  key: const Key('daily-goal-down'),
                  tooltip: 'Lower daily goal',
                  icon: Icons.remove_rounded,
                  onPressed: goal > 1
                      ? () => controller.setDailyGoal(goal - 1)
                      : null,
                ),
                SizedBox(
                  width: 28,
                  child: Semantics(
                    label: 'Daily goal',
                    value: '$goal ${_plural(goal, 'stint', 'stints')}',
                    excludeSemantics: true,
                    child: Text(
                      '$goal',
                      key: const Key('daily-goal-value'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'MartianMono',
                        fontSize: 13,
                        color: colors.ink,
                      ),
                    ),
                  ),
                ),
                _StepButton(
                  key: const Key('daily-goal-up'),
                  tooltip: 'Raise daily goal',
                  icon: Icons.add_rounded,
                  onPressed: goal < DeskSettings.maxDailyGoal
                      ? () => controller.setDailyGoal(goal + 1)
                      : null,
                ),
              ],
            );
            final goalCaption = Semantics(
              liveRegion: true,
              label:
                  'Daily goal: $goal ${_plural(goal, 'stint', 'stints')}. $caption',
              excludeSemantics: true,
              child: Text(
                caption,
                style: TextStyle(fontSize: 13, color: colors.muted),
              ),
            );
            if (constraints.maxWidth < 400) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  goalCaption,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: goalControl),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: goalCaption),
                const SizedBox(width: 12),
                goalControl,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WeekSection extends StatelessWidget {
  const _WeekSection({
    required this.summary,
    required this.weeksBack,
    required this.onPrevious,
    required this.onNext,
  });
  final ProgressSummary summary;
  final int weeksBack;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final days = summary.week(weeksBack);
    final start = summary.weekStart(weeksBack);
    final title = switch (weeksBack) {
      0 => 'This week',
      1 => 'Last week',
      _ =>
        'Week of ${MaterialLocalizations.of(context).formatShortMonthDay(start)}',
    };
    final count = days.fold(0, (sum, d) => sum + d.count);
    final seconds = days.fold(0, (sum, d) => sum + d.seconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _Eyebrow(title)),
            Text(
              '$count ${_plural(count, 'stint', 'stints')} · ${formatFocusTime(seconds)}',
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: const Key('progress-week-prev'),
              tooltip: 'Previous week',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
            ),
            IconButton(
              key: const Key('progress-week-next'),
              tooltip: 'Next week',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _WeekChart(days: days, summary: summary),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < days.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    days[i].day == summary.today
                        ? 'Today'
                        : _weekday(context, days[i].day),
                    textAlign: TextAlign.center,
                    style: days[i].day == summary.today
                        ? TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          )
                        : TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days, required this.summary});
  final List<DayTotal> days;
  final ProgressSummary summary;
  static const plotHeight = 132.0;

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final goal = summary.goal;
    final busiest = days.fold(0, (most, d) => math.max(most, d.count));
    final yMax = math.max(goal + 2, busiest + 1);
    final goalY = goal / yMax * plotHeight;
    return SizedBox(
      height: 150,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(height: 1, color: colors.line2),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: goalY,
            child: ExcludeSemantics(
              child: CustomPaint(
                size: const Size.fromHeight(1),
                painter: _DashPainter(colors.muted.withValues(alpha: .6)),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: goalY + 4,
            child: ExcludeSemantics(
              child: Text(
                'Goal $goal',
                style: TextStyle(fontSize: 11, color: colors.muted),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _DayColumn(
                      key: ValueKey('progress-day-$i'),
                      day: days[i],
                      isToday: days[i].day == summary.today,
                      yMax: yMax,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatefulWidget {
  const _DayColumn({
    super.key,
    required this.day,
    required this.isToday,
    required this.yMax,
  });
  final DayTotal day;
  final bool isToday;
  final int yMax;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  final tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final day = widget.day;
    final label = day.future
        ? '${_weekday(context, day.day)} · upcoming'
        : '${MaterialLocalizations.of(context).formatMediumDate(day.day)} · '
              '${day.count} ${_plural(day.count, 'stint', 'stints')} · '
              '${formatFocusTime(day.seconds)}';
    final height = day.count == 0
        ? 2.0
        : math.max(4.0, day.count / widget.yMax * _WeekChart.plotHeight);
    return Tooltip(
      key: tooltip,
      message: label,
      excludeFromSemantics: true,
      preferBelow: false,
      decoration: BoxDecoration(
        color: colors.raised,
        border: Border.all(color: colors.line2),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        fontFamily: 'HankenGrotesk',
        fontSize: 12,
        color: colors.ink,
      ),
      child: TextButton(
        onPressed: () => tooltip.currentState?.ensureTooltipVisible(),
        onFocusChange: (focused) {
          if (focused) {
            tooltip.currentState?.ensureTooltipVisible();
          } else {
            Tooltip.dismissAllToolTips();
          }
        },
        style:
            TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? BorderSide(color: colors.focusText, width: 2)
                    : BorderSide.none,
              ),
            ),
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: day.future
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isToday) ...[
                          Text(
                            '${day.count}',
                            style: TextStyle(
                              fontFamily: 'MartianMono',
                              fontSize: 11,
                              height: 1,
                              color: colors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Container(
                          key: ValueKey(
                            'progress-bar-${day.day.toIso8601String()}',
                          ),
                          width: 24,
                          height: height,
                          decoration: BoxDecoration(
                            color: day.count == 0 ? colors.line2 : colors.chart,
                            borderRadius: day.count == 0
                                ? null
                                : const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, .5),
        Offset(math.min(x + 4, size.width), .5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.summary, required this.week});
  final ProgressSummary summary;
  final List<DayTotal> week;

  @override
  Widget build(BuildContext context) {
    final streak = summary.streak;
    final elapsed = summary.elapsedDays(week);
    final all = summary.allTimeSeconds;
    final hours = all ~/ 3600;
    final minutes = (all / 60).round();
    return Row(
      children: [
        Expanded(
          child: _Tile(
            label: 'Streak',
            value: '$streak',
            unit: _plural(streak, 'day', 'days'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            label: 'Goal met',
            value: '${summary.goalDays(week)}',
            unit: 'of $elapsed ${_plural(elapsed, 'day', 'days')}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            label: 'All time',
            value: all >= 3600 ? '$hours' : '$minutes',
            unit: all >= 3600 ? _plural(hours, 'hour', 'hours') : 'min',
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.unit});
  final String label, value, unit;
  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: colors.muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        fontFamily: 'MartianMono',
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    TextSpan(text: ' $unit'),
                  ],
                ),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayList extends StatelessWidget {
  const _TodayList({required this.summary});
  final ProgressSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    String time(DateTime t) => localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(t.toLocal()),
      alwaysUse24HourFormat: use24,
    );
    final sessions = summary.todaySessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('Today’s stints'),
        const SizedBox(height: 10),
        if (sessions.isEmpty)
          CustomPaint(
            painter: _EmptyBorderPainter(colors.line2),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'No stints yet today. Finish one and it shows up here.',
                  style: TextStyle(fontSize: 13, color: colors.muted),
                ),
              ),
            ),
          )
        else
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < sessions.length; i++) ...[
                  if (i > 0) Divider(color: colors.line),
                  MergeSemantics(
                    child: SizedBox(
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${time(sessions[i].finishedAt.subtract(Duration(seconds: sessions[i].seconds)))} – ${time(sessions[i].finishedAt)}',
                                  style: TextStyle(
                                    fontFamily: 'MartianMono',
                                    fontSize: 13,
                                    color: colors.ink,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${(sessions[i].seconds / 60).round()} min',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyBorderPainter extends CustomPainter {
  const _EmptyBorderPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5),
          const Radius.circular(12),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 8) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + 4, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EmptyBorderPainter old) => old.color != color;
}
