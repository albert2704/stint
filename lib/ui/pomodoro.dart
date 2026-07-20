import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/controller.dart';
import '../data/models.dart';
import '../music.dart';
import '../blocker.dart';
import 'blocker_settings.dart';
import 'components.dart';
import 'music_panel.dart';
import 'progress.dart';
import 'routines.dart';
import 'theme.dart';

class PomodoroScreen extends StatelessWidget {
  const PomodoroScreen({
    super.key,
    required this.controller,
    this.music,
    this.blocker,
  });
  final StintController controller;
  final FocusMusic? music;
  final BlockerController? blocker;

  String status(BuildContext context) {
    final timer = controller.timer;
    if (timer.running) {
      final end = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(timer.endsAt!.toLocal()),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      return timer.phase == TimerPhase.focus
          ? 'Ends at $end'
          : 'Back to it at $end';
    }
    if (controller.timerHasProgress) {
      return 'Paused. Pick up where you left off.';
    }
    return switch (timer.phase) {
      TimerPhase.focus => 'Ready when you are.',
      TimerPhase.shortBreak => 'Stand up. Look at something far away.',
      TimerPhase.longBreak => 'Four stints down. Take a real break.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = StintColors.of(context);
    final focus = c.timer.phase == TimerPhase.focus;
    final accent = colors.accent(focus);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                SizedBox(
                  height: 50,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 22, right: 14),
                    child: Row(
                      children: [
                        const StintMark(size: 26),
                        const SizedBox(width: 10),
                        Text(
                          'stint',
                          style: TextStyle(
                            fontFamily: 'MartianMono',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -.32,
                            color: colors.ink,
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ProgressButton(
                                  controller: c,
                                  onPressed: () =>
                                      showStintProgress(context, c),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: RhythmSelector(
                                    controller: c,
                                    onEdit: () => showStintSettings(
                                      context,
                                      c,
                                      blocker: blocker,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        MergeSemantics(
                          child: Semantics(
                            label: 'Settings',
                            child: Tooltip(
                              message: 'Settings',
                              excludeFromSemantics: true,
                              child: IconButton(
                                onPressed: () => showStintSettings(
                                  context,
                                  c,
                                  blocker: blocker,
                                ),
                                icon: const Icon(Icons.tune_rounded, size: 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        _Dot(color: accent, size: 8),
                                        const SizedBox(width: 10),
                                        Text(
                                          c.timer.phase.label.toUpperCase(),
                                          style: TextStyle(
                                            color: colors.accentText(focus),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1.92,
                                          ),
                                        ),
                                        if (focus) ...[
                                          const SizedBox(width: 10),
                                          Text(
                                            '${c.timer.cycleStep ~/ 2 + 1} of 4',
                                            style: TextStyle(
                                              color: colors.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 106,
                                      child: Row(
                                        children: [
                                          _RoundControl(
                                            tooltip: 'Remove a minute',
                                            size: 40,
                                            icon: Icons.remove_rounded,
                                            onPressed:
                                                c.remaining <= 60 ||
                                                    c.pendingAction != null
                                                ? null
                                                : () => c.adjustCurrent(-1),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                clockText(c.remaining),
                                                key: const Key('countdown'),
                                                style: TextStyle(
                                                  fontFamily: 'MartianMono',
                                                  fontSize: 84,
                                                  fontWeight: FontWeight.w300,
                                                  letterSpacing: -4.2,
                                                  color: colors.ink,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _RoundControl(
                                            tooltip: 'Add a minute',
                                            size: 40,
                                            icon: Icons.add_rounded,
                                            onPressed:
                                                c.remaining >=
                                                        (focus ? 120 : 60) *
                                                            60 ||
                                                    c.pendingAction != null
                                                ? null
                                                : () => c.adjustCurrent(1),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        status(context),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colors.muted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    CycleTrack(controller: c),
                                    const SizedBox(height: 20),
                                    if (c.pendingAction != null)
                                      TimerConfirmBar(controller: c)
                                    else
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          _RoundControl(
                                            tooltip: 'Reset',
                                            size: 52,
                                            icon: Icons.replay_rounded,
                                            onPressed: c.requestReset,
                                          ),
                                          const SizedBox(width: 14),
                                          Flexible(
                                            child: SizedBox(
                                              width: 208,
                                              height: 56,
                                              child: FilledButton.icon(
                                                key: const Key('timer-toggle'),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: accent,
                                                  foregroundColor:
                                                      colors.onAccent,
                                                  textStyle: const TextStyle(
                                                    fontFamily: 'HankenGrotesk',
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                onPressed: () {
                                                  final running =
                                                      c.timer.running;
                                                  c.tick();
                                                  if (running &&
                                                      !c.timer.running) {
                                                    return;
                                                  }
                                                  c.timer.running
                                                      ? c.pauseTimer()
                                                      : c.startTimer();
                                                },
                                                icon: Icon(
                                                  c.timer.running
                                                      ? Icons.pause_rounded
                                                      : Icons
                                                            .play_arrow_rounded,
                                                  size: 20,
                                                ),
                                                label: Text(
                                                  c.timer.running
                                                      ? 'Pause'
                                                      : c.timerHasProgress
                                                      ? 'Resume'
                                                      : focus
                                                      ? 'Start focus'
                                                      : 'Start break',
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          _RoundControl(
                                            tooltip: 'Skip to next',
                                            size: 52,
                                            icon: Icons.skip_next_rounded,
                                            onPressed: c.requestSkip,
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              if (blocker != null) ...[
                                const SizedBox(height: 12),
                                ListenableBuilder(
                                  listenable: blocker!,
                                  builder: (context, _) => TextButton.icon(
                                    key: const Key('open-blocker'),
                                    onPressed: () =>
                                        showBlockerSettings(context, blocker!),
                                    icon: Icon(
                                      blocker!.active
                                          ? Icons.shield
                                          : Icons.shield_outlined,
                                      size: 17,
                                    ),
                                    label: Text(blocker!.statusLabel),
                                  ),
                                ),
                              ],
                              if (music != null) ...[
                                const SizedBox(height: 20),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: MusicPanel(music: music!),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 38,
                                ),
                                child: Text(
                                  'Close this window and Stint keeps counting in your menu bar.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.muted,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              if (c.saveError != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    28,
                                    16,
                                    28,
                                    0,
                                  ),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Column(
                                      children: [
                                        Text(
                                          c.saveError!,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: colors.error),
                                        ),
                                        TextButton(
                                          onPressed: c.persist,
                                          child: const Text('Retry save'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (c.notice != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    16,
                                    14,
                                    0,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: colors.surface,
                                      border: Border.all(color: colors.line),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 14,
                                        right: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Semantics(
                                              liveRegion: true,
                                              child: Text(
                                                c.notice!,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Dismiss message',
                                            onPressed: c.clearNotice,
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 17,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TimerConfirmBar extends StatelessWidget {
  const TimerConfirmBar({super.key, required this.controller});
  final StintController controller;
  @override
  Widget build(BuildContext context) {
    final pending = controller.pendingAction!;
    final c = StintColors.of(context);
    return Semantics(
      container: true,
      child: Container(
        key: const Key('timer-confirmation'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                pending.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${clockText(controller.remaining)} left will be discarded.',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: controller.cancelPending,
                  child: const Text('Keep going'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent(
                      controller.timer.phase == TimerPhase.focus,
                    ),
                    foregroundColor: c.onAccent,
                  ),
                  onPressed: controller.confirmPending,
                  child: Text(pending.confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CycleTrack extends StatelessWidget {
  const CycleTrack({super.key, required this.controller});
  final StintController controller;
  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final step = controller.timer.cycleStep;
    final durations = List.generate(
      8,
      (index) => index == step
          ? controller.timer.totalSeconds
          : controller.workspace.settings.secondsFor(phaseForCycleStep(index)),
    );
    final left = 4 - ((step + 1) ~/ 2);
    final caption = step == 7
        ? 'Cycle complete after this break'
        : step == 6
        ? 'Long break after this stint'
        : 'Long break after $left more ${left == 1 ? 'stint' : 'stints'}';
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final widths = _segmentWidths(constraints.maxWidth - 35, durations);
            return Row(
              children: [
                for (var index = 0; index < 8; index++) ...[
                  if (index > 0) const SizedBox(width: 5),
                  SizedBox(
                    width: widths[index],
                    height: 44,
                    child: _CycleSegment(
                      key: ValueKey('cycle-step-$index'),
                      phaseKey: index == 0
                          ? const Key('phase-focus')
                          : index == 1
                          ? const Key('phase-shortBreak')
                          : index == 7
                          ? const Key('phase-longBreak')
                          : null,
                      phase: phaseForCycleStep(index),
                      durationSeconds: durations[index],
                      current: index == step,
                      past: index < step,
                      progress:
                          (1 -
                                  controller.remaining /
                                      controller.timer.totalSeconds)
                              .clamp(0, 1),
                      onPressed: index == step
                          ? null
                          : () => controller.requestJumpTo(index),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                caption,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            _Dot(color: colors.focus, size: 5),
            const SizedBox(width: 4),
            Text('Focus', style: TextStyle(fontSize: 11, color: colors.muted)),
            const SizedBox(width: 8),
            _Dot(color: colors.breakColor, size: 5),
            const SizedBox(width: 4),
            Text('Break', style: TextStyle(fontSize: 11, color: colors.muted)),
          ],
        ),
      ],
    );
  }

  List<double> _segmentWidths(double width, List<int> durations) {
    final result = List<double>.filled(8, 0);
    final pending = List.generate(8, (index) => index);
    var available = width;
    while (pending.isNotEmpty) {
      final sum = pending.fold<int>(0, (total, i) => total + durations[i]);
      final small = pending
          .where((i) => available * durations[i] / sum < 10)
          .toList();
      if (small.isEmpty) {
        for (final i in pending) {
          result[i] = available * durations[i] / sum;
        }
        break;
      }
      for (final i in small) {
        result[i] = 10;
        available -= 10;
        pending.remove(i);
      }
    }
    return result;
  }
}

class _CycleSegment extends StatelessWidget {
  const _CycleSegment({
    super.key,
    this.phaseKey,
    required this.phase,
    required this.durationSeconds,
    required this.current,
    required this.past,
    required this.progress,
    this.onPressed,
  });
  final Key? phaseKey;
  final TimerPhase phase;
  final int durationSeconds;
  final bool current, past;
  final double progress;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final accent = colors.accent(phase == TimerPhase.focus);
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    final duration =
        '$minutes ${minutes == 1 ? 'minute' : 'minutes'}'
        '${seconds == 0 ? '' : ' $seconds ${seconds == 1 ? 'second' : 'seconds'}'}';
    final label = '${phase.label}, $duration${current ? ', current' : ''}';
    return Semantics(
      label: label,
      selected: current,
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: TextButton(
          key: phaseKey,
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(10, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: SizedBox(
            height: current ? 10 : 6,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: past
                          ? accent.withValues(alpha: .45)
                          : colors.track,
                    ),
                  ),
                  if (current)
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: ColoredBox(
                        color: accent,
                        child: const SizedBox.expand(),
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

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.tooltip,
    required this.icon,
    required this.size,
    this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 21),
          style: IconButton.styleFrom(
            backgroundColor: StintColors.of(context).raised,
            fixedSize: Size.square(size),
            disabledBackgroundColor: StintColors.of(context).raised,
            disabledForegroundColor: StintColors.of(
              context,
            ).muted.withValues(alpha: .4),
          ),
        ),
      ),
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// Exact arcs from the handoff's vector mark, kept native to Flutter.
class StintMark extends StatelessWidget {
  const StintMark({super.key, this.size = 26});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _StintMarkPainter()),
    ),
  );
}

class _StintMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 100, 100),
        const Radius.circular(24),
      ),
      Paint()..color = const Color(0xFF1E2025),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(33, 50, 34, 34),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      stroke..color = StintColors.dark.breakColor,
    );
    canvas.drawArc(
      const Rect.fromLTWH(33, 16, 34, 34),
      0,
      -math.pi * 1.5,
      false,
      stroke..color = StintColors.dark.focus,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
