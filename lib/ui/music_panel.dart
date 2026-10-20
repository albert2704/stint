import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../music.dart';
import 'ambient_mixer.dart';
import 'youtube_link.dart';
import 'components.dart';
import 'theme.dart';
import 'menu_focus.dart';

class MusicPanel extends StatelessWidget {
  const MusicPanel({super.key, required this.music});
  final FocusMusic music;

  Future<void> remove(BuildContext context) async {
    final track = music.selected;
    if (await confirmAction(
      context,
      'Remove this sound?',
      'Remove ${track.title} from your sound list?',
      action: 'Remove',
    )) {
      if (track.isYouTube) {
        await music.removeYouTube(track.id);
      } else {
        await music.removeCustom(track.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: music,
    builder: (context, _) {
      final colors = StintColors.of(context);
      final track = music.selected;
      final source = track.isYouTube
          ? 'YouTube · plays in the menu bar panel'
          : '${track.asset == null ? 'Your audio file' : 'Built-in loop'} · ${music.followTimer ? 'starts and fades with the timer' : 'you control playback'}';
      return Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'SOUND',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.76,
                      color: colors.muted,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    toggled: music.followTimer,
                    child: TextButton(
                      key: const Key('music-follow-timer'),
                      onPressed: music.busy
                          ? null
                          : () => music.setFollowTimer(!music.followTimer),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.only(left: 8),
                        minimumSize: const Size(0, 40),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Play with timer',
                            style: TextStyle(fontSize: 12, color: colors.ink2),
                          ),
                          const SizedBox(width: 8),
                          ExcludeSemantics(
                            child: Container(
                              width: 38,
                              height: 22,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: music.followTimer
                                    ? colors.focus
                                    : colors.line2,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Align(
                                alignment: music.followTimer
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: music.followTimer
                                        ? colors.onAccent
                                        : colors.muted,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SoundEqualizer(playing: music.playing),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            music.starting ? 'Connecting to YouTube…' : source,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: colors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  MergeSemantics(
                    child: Semantics(
                      button: true,
                      label: music.wantsPlayback ? 'Pause sound' : 'Play sound',
                      child: IconButton.filledTonal(
                        tooltip: music.wantsPlayback
                            ? 'Pause sound'
                            : 'Play sound',
                        onPressed: music.busy
                            ? null
                            : music.wantsPlayback
                            ? music.pause
                            : music.play,
                        style: IconButton.styleFrom(
                          backgroundColor: colors.raised,
                          foregroundColor: colors.ink,
                          fixedSize: const Size(44, 44),
                        ),
                        icon: music.busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                music.wantsPlayback
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              if (track.asset == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (track.isYouTube)
                        OutlinedButton.icon(
                          onPressed: music.busy ? null : music.showYouTube,
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('Show player'),
                        ),
                      OutlinedButton.icon(
                        onPressed: music.busy ? null : () => remove(context),
                        icon: const Icon(Icons.close, size: 14),
                        label: const Text('Remove'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final source in music.tracks)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Semantics(
                        selected: source.id == track.id,
                        child: OutlinedButton(
                          key: ValueKey('music-${source.id}'),
                          onPressed: music.busy
                              ? null
                              : () => music.select(source.id),
                          style:
                              OutlinedButton.styleFrom(
                                backgroundColor: source.id == track.id
                                    ? colors.ink
                                    : Colors.transparent,
                                foregroundColor: source.id == track.id
                                    ? colors.ground
                                    : colors.ink2,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                minimumSize: const Size(0, 40),
                                textStyle: const TextStyle(
                                  fontFamily: 'HankenGrotesk',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ).copyWith(
                                side:
                                    WidgetStateProperty.resolveWith<BorderSide>(
                                      (states) =>
                                          states.contains(WidgetState.focused)
                                          ? BorderSide(
                                              color: colors.focusText,
                                              width: 2,
                                              strokeAlign: 3,
                                            )
                                          : BorderSide(
                                              color: source.id == track.id
                                                  ? colors.ink
                                                  : colors.line,
                                            ),
                                    ),
                              ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (source.isYouTube) ...[
                                const Icon(Icons.link, size: 14),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  source.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  MenuFocusRing(
                    radius: 24,
                    child: MergeSemantics(
                      child: Semantics(
                        button: true,
                        child: PopupMenuButton<String>(
                          tooltip: 'Add',
                          enabled: !music.busy,
                          onSelected: (value) {
                            if (value == 'audio') {
                              music.importFiles();
                            } else {
                              addYouTubeLink(context, music);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'audio',
                              child: Text('Audio file…'),
                            ),
                            PopupMenuItem(
                              value: 'youtube',
                              child: Text('YouTube link…'),
                            ),
                          ],
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 40),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: colors.line),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, size: 15, color: colors.ink2),
                                const SizedBox(width: 4),
                                Text(
                                  'Add',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.ink2,
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Tooltip(
                    message: 'Volume',
                    child: Icon(
                      music.volume == 0
                          ? Icons.volume_off_outlined
                          : Icons.volume_down_rounded,
                      semanticLabel: 'Volume',
                      size: 19,
                      color: colors.muted,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: music.volume,
                      activeColor: colors.focus,
                      inactiveColor: colors.track,
                      label: '${(music.volume * 100).round()}%',
                      semanticFormatterCallback: (value) =>
                          'Volume ${(value * 100).round()} percent',
                      onChanged: music.busy ? null : music.previewVolume,
                      onChangeEnd: music.busy ? null : music.saveVolume,
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${(music.volume * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'MartianMono',
                        fontSize: 10,
                        color: colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AmbientMixer(music: music),
              if (music.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      music.error!,
                      style: TextStyle(fontSize: 12, color: colors.error),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Decorative audio bars; platform Reduce Motion keeps the static mark.
class SoundEqualizer extends StatefulWidget {
  const SoundEqualizer({super.key, required this.playing});
  final bool playing;
  @override
  State<SoundEqualizer> createState() => _SoundEqualizerState();
}

class _SoundEqualizerState extends State<SoundEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(SoundEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  void sync() {
    if (widget.playing && !MediaQuery.disableAnimationsOf(context)) {
      if (!animation.isAnimating) animation.repeat();
    } else {
      animation.stop();
      animation.value = 0;
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.raised,
          borderRadius: BorderRadius.circular(10),
        ),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: 3,
                    height: animation.isAnimating
                        ? 8 +
                              16 *
                                  ((math.sin(
                                            animation.value * math.pi * 2 +
                                                i * 1.8,
                                          ) +
                                          1) /
                                      2)
                        : [12.0, 22.0, 16.0][i],
                    decoration: BoxDecoration(
                      color: colors.focus,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
