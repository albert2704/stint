import 'package:flutter/material.dart';
import '../music.dart';
import 'theme.dart';

Future<void> showAmbientMixer(BuildContext context, FocusMusic music) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: AmbientMixer(
            music: music,
            initiallyExpanded: true,
            showError: true,
          ),
        ),
      ),
    );

/// Compact independent layers within the existing Sound card.
class AmbientMixer extends StatelessWidget {
  const AmbientMixer({
    super.key,
    required this.music,
    this.initiallyExpanded = false,
    this.showError = false,
  });
  final FocusMusic music;
  final bool initiallyExpanded;
  final bool showError;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: music,
    builder: (context, _) {
      final colors = StintColors.of(context);
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('ambient-mixer'),
          initiallyExpanded: initiallyExpanded,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          title: Text(
            'Ambient mix',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.ink2,
            ),
          ),
          subtitle: Text(
            music.ambientPlaying
                ? music.wantsPlayback
                      ? 'Playing with music'
                      : 'Playing ambience only'
                : music.hasAmbient
                ? 'Mix saved · paused'
                : 'Rain, café hum and brown noise',
            style: TextStyle(fontSize: 11, color: colors.muted),
          ),
          children: [
            for (final layer in FocusMusic.ambientLayers.entries)
              Row(
                children: [
                  SizedBox(
                    width: 86,
                    child: Text(
                      layer.value.$1,
                      style: TextStyle(fontSize: 12, color: colors.ink2),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      key: ValueKey('ambient-level-${layer.key}'),
                      value: music.ambientLevels[layer.key] ?? 0,
                      label:
                          '${((music.ambientLevels[layer.key] ?? 0) * 100).round()}%',
                      semanticFormatterCallback: (value) =>
                          '${layer.value.$1} ${(value * 100).round()} percent',
                      onChanged: music.busy
                          ? null
                          : (value) =>
                                music.previewAmbientLevel(layer.key, value),
                      onChangeEnd: (value) =>
                          music.setAmbientLevel(layer.key, value),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${((music.ambientLevels[layer.key] ?? 0) * 100).round()}',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontFamily: 'MartianMono',
                        fontSize: 10,
                        color: colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('ambient-toggle'),
                onPressed: music.busy || !music.hasAmbient
                    ? null
                    : music.toggleAmbient,
                icon: Icon(
                  music.ambientPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 18,
                ),
                label: Text(
                  music.ambientPlaying ? 'Pause ambience' : 'Play ambience',
                ),
              ),
            ),
            if (showError && music.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    music.error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Original synthetic ambience. Café hum includes soft voices '
                'and cups, with no words.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: colors.muted,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
