import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'data/controller.dart';
import 'data/models.dart';
import 'music.dart';

/// Keeps macOS chrome in sync with the same timer that the Flutter UI uses.
class NativeTimerBridge {
  NativeTimerBridge(
    this.controller, {
    this.onSettings,
    this.onAdjust,
    this.onProgress,
    this.music,
    MethodChannel? channel,
  }) : channel = channel ?? const MethodChannel('focus_desk/timer') {
    this.channel.setMethodCallHandler(_handle);
    controller.addListener(_sync);
    music?.addListener(_sync);
    _sync();
  }
  final DeskController controller;
  final Future<void> Function()? onSettings;
  final Future<void> Function()? onAdjust;
  final Future<void> Function()? onProgress;
  final MethodChannel channel;
  final FocusMusic? music;
  String? _previous;
  bool _disposed = false;

  Map<String, Object?> get snapshot {
    final progress = controller.progress();
    final completionDay = controller.timer.endsAt ?? controller.now();
    // A scheduled notification describes the day the interval will finish.
    // The running focus has not been recorded yet; breaks never add a stint.
    final completionCount =
        progress.totalFor(completionDay).count +
        (controller.timer.running && controller.timer.phase == TimerPhase.focus
            ? 1
            : 0);
    return {
      'remaining': controller.remaining,
      'totalSeconds': controller.timer.totalSeconds,
      'running': controller.timer.running,
      'hasProgress': controller.timerHasProgress,
      'phase': controller.timer.phase.label,
      'deadlineMilliseconds': controller.timer.endsAt?.millisecondsSinceEpoch,
      'sessionId': controller.timer.sessionId,
      'completedSessionId': controller.timer.completedSessionId,
      'cycleStep': controller.timer.cycleStep,
      'focusMinutes': controller.workspace.settings.focusMinutes,
      'shortBreakMinutes': controller.workspace.settings.shortBreakMinutes,
      'longBreakMinutes': controller.workspace.settings.longBreakMinutes,
      'appearance': controller.workspace.settings.appearance,
      'pendingAction': controller.pendingAction?.toJson(),
      'routines': controller.routines
          .map((routine) => routine.toJson())
          .toList(),
      'activeRoutineId': controller.activeRoutineId,
      'todayCount': progress.todayTotal.count,
      'dailyGoal': controller.workspace.settings.dailyGoal,
      'completionCount': completionCount,
      if (music != null)
        'music': {
          'tracks': music!.tracks
              .map((track) => {'id': track.id, 'title': track.title})
              .toList(),
          'selectedId': music!.selectedId,
          'playing': music!.playing,
          'starting': music!.starting,
          'busy': music!.busy,
          'volume': music!.volume,
          'followTimer': music!.followTimer,
          'error': music!.error,
        },
    };
  }

  void _sync() {
    if (_disposed) {
      return;
    }
    final current = snapshot;
    final encoded = jsonEncode(current);
    if (_previous == encoded) {
      return;
    }
    _previous = encoded;
    unawaited(
      channel.invokeMethod<void>('update', current).catchError((Object error) {
        debugPrint('Menu bar update unavailable: $error');
      }),
    );
  }

  Future<void> _handle(MethodCall call) async {
    if (_disposed) {
      return;
    }
    switch (call.method) {
      case 'toggle':
        if (controller.pendingAction != null) return;
        final displayed = call.arguments;
        // Older hosts sent no context. Current panels send the state attached
        // to the displayed button, so a queued Pause cannot become Start.
        if (displayed != null &&
            (displayed is! Map ||
                displayed['running'] is! bool ||
                displayed['cycleStep'] is! int ||
                !displayed.containsKey('sessionId') ||
                (displayed['sessionId'] != null &&
                    displayed['sessionId'] is! String))) {
          return;
        }
        final wasRunning = controller.timer.running;
        controller.tick();
        if (displayed is Map &&
            (displayed['running'] != controller.timer.running ||
                displayed['sessionId'] != controller.timer.sessionId ||
                displayed['cycleStep'] != controller.timer.cycleStep)) {
          return;
        }
        // A stale Pause click at expiry must not start the newly offered break.
        if (wasRunning && !controller.timer.running) {
          return;
        }
        controller.timer.running
            ? controller.pauseTimer()
            : controller.startTimer();
      case 'adjust':
        controller.tick();
        await (onAdjust ?? onSettings)?.call();
      case 'settings':
        controller.tick();
        await (onSettings ?? onAdjust)?.call();
      case 'progress':
        controller.tick();
        await onProgress?.call();
      case 'reset':
        controller.requestReset();
      case 'skip':
        controller.requestSkip();
      case 'jumpStep':
        final step = call.arguments;
        if (step is int && step >= 0 && step < 8) {
          controller.requestJumpTo(step);
        }
      case 'confirm':
        controller.confirmPending();
      case 'cancel':
        controller.cancelPending();
      case 'startNext':
      case 'skipOffered':
        final context = call.arguments;
        if (context is Map &&
            context['sessionId'] is String &&
            context['cycleStep'] is int) {
          final action = call.method == 'startNext'
              ? controller.startNextFromNotification
              : controller.skipOfferedFromNotification;
          action(
            sessionId: context['sessionId'] as String,
            cycleStep: context['cycleStep'] as int,
          );
        }
      case 'applyRoutine':
        final id = call.arguments;
        if (id is String && controller.routines.any((r) => r.id == id)) {
          controller.requestRoutine(id);
        }
      case 'musicToggle':
        final player = music;
        if (player != null) {
          await (player.wantsPlayback ? player.pause() : player.play());
        }
      case 'musicSelect':
        final id = call.arguments;
        final player = music;
        if (player != null &&
            id is String &&
            player.tracks.any((track) => track.id == id)) {
          await player.select(id);
        }
      case 'musicVolume':
        final value = call.arguments;
        if (value is num && value.isFinite) {
          await music?.saveVolume(value.toDouble().clamp(0, 1));
        }
      case 'followTimer':
        final value = call.arguments;
        if (value is bool) await music?.setFollowTimer(value);
      case 'refresh':
        controller.tick();
        _previous = null;
        _sync();
      case 'notificationError':
        controller.showNotice(
          call.arguments as String? ??
              'Notifications could not be enabled. Check Stint in System Settings → Notifications.',
        );
    }
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_sync);
    music?.removeListener(_sync);
    channel.setMethodCallHandler(null);
  }
}
