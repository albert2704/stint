import 'dart:async';
import 'data/controller.dart';
import 'data/models.dart';
import 'music.dart';

/// Reacts to deliberate timer transitions, never to countdown ticks or startup.
class TimerMusicCoordinator {
  TimerMusicCoordinator(this.controller, this.music) {
    _lastTimer = _timerState;
    _lastFollow = music.followTimer;
    controller.addListener(_onTimer);
    music.addListener(_onMusic);
  }

  final StintController controller;
  final FocusMusic music;
  late ({TimerPhase phase, bool running, String? session}) _lastTimer;
  late bool _lastFollow;
  bool? _pending;
  int _generation = 0;
  bool _processing = false;
  bool _disposed = false;

  ({TimerPhase phase, bool running, String? session}) get _timerState => (
    phase: controller.timer.phase,
    running: controller.timer.running,
    session: controller.timer.sessionId,
  );

  bool get _shouldPlay => controller.timer.running;

  void _onTimer() {
    final current = _timerState;
    if (current == _lastTimer) return;
    _lastTimer = current;
    if (music.followTimer) _request(_shouldPlay);
  }

  void _onMusic() {
    if (_lastFollow != music.followTimer) {
      _lastFollow = music.followTimer;
      if (music.followTimer) {
        _request(_shouldPlay);
      } else {
        _generation++;
        _pending = null;
      }
    }
    _drain();
  }

  void _request(bool play) {
    _generation++;
    _pending = play;
    _drain();
  }

  void _drain() {
    if (_disposed || _processing || music.busy || _pending == null) return;
    final play = _pending!;
    final generation = _generation;
    _pending = null;
    _processing = true;
    unawaited(() async {
      try {
        if (play) {
          await music.play(
            fade: true,
            shouldPlay: () =>
                !_disposed &&
                generation == _generation &&
                music.followTimer &&
                _shouldPlay,
          );
        } else if (music.wantsPlayback) {
          await music.fadePause();
        }
      } finally {
        _processing = false;
        _drain();
      }
    }());
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _pending = null;
    controller.removeListener(_onTimer);
    music.removeListener(_onMusic);
  }
}
