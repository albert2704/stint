import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../alert_sounds.dart';
import '../data/controller.dart';
import '../data/models.dart';
import 'theme.dart';
import 'menu_focus.dart';
import 'keymap_settings.dart';
import '../blocker.dart';
import 'blocker_settings.dart';
import 'single_dialog.dart';

String rhythmDigits(FocusRoutine rhythm) =>
    '${rhythm.focusMinutes}·${rhythm.shortBreakMinutes}·${rhythm.longBreakMinutes}';

class RhythmSelector extends StatelessWidget {
  const RhythmSelector({
    super.key,
    required this.controller,
    required this.onEdit,
  });
  final StintController controller;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final colors = StintColors.of(context);
      final selected = controller.routines
          .where((r) => r.id == controller.activeRoutineId)
          .firstOrNull;
      final settings = controller.workspace.settings;
      return MenuFocusRing(
        child: Semantics(
          button: true,
          label: 'Rhythms',
          child: PopupMenuButton<String>(
            key: const Key('routine-selection'),
            tooltip: 'Rhythms',
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints.tightFor(width: 252),
            color: colors.raised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.line2),
            ),
            onSelected: (id) {
              if (id == '_edit') {
                onEdit();
              } else {
                controller.requestRoutine(id);
              }
            },
            itemBuilder: (_) => [
              for (final rhythm in controller.routines)
                PopupMenuItem(
                  value: rhythm.id,
                  child: Row(
                    children: [
                      Icon(
                        rhythm.id == selected?.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 17,
                        color: rhythm.id == selected?.id
                            ? colors.focusText
                            : colors.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          rhythm.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        rhythmDigits(rhythm),
                        style: TextStyle(
                          fontFamily: 'MartianMono',
                          fontSize: 10,
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: '_edit', child: Text('Edit rhythms…')),
            ],
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40, maxWidth: 222),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        selected?.name ?? 'Custom timing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      selected == null
                          ? '${settings.focusMinutes}·${settings.shortBreakMinutes}·${settings.longBreakMinutes}'
                          : rhythmDigits(selected),
                      style: TextStyle(
                        fontFamily: 'MartianMono',
                        fontSize: 10,
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

final _settingsDialog = SingleStintDialog();

Future<void> showStintSettings(
  BuildContext context,
  StintController controller, {
  BlockerController? blocker,
}) => _settingsDialog.show(
  context,
  (_) => StintSettings(controller: controller, blocker: blocker),
);

class StintSettings extends StatefulWidget {
  const StintSettings({super.key, required this.controller, this.blocker});
  final BlockerController? blocker;
  final StintController controller;
  @override
  State<StintSettings> createState() => _StintSettingsState();
}

class _StintSettingsState extends State<StintSettings> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final alertSounds = const AlertSounds();
  late final fields = [
    TextEditingController(
      text: '${widget.controller.workspace.settings.focusMinutes}',
    ),
    TextEditingController(
      text: '${widget.controller.workspace.settings.shortBreakMinutes}',
    ),
    TextEditingController(
      text: '${widget.controller.workspace.settings.longBreakMinutes}',
    ),
  ];
  late final customs = List<FocusRoutine>.of(
    widget.controller.workspace.settings.customRoutines,
  );
  late String appearance = widget.controller.workspace.settings.appearance;
  late String? preferred = widget.controller.activeRoutineId;
  AlertSoundSettings? soundSettings;
  String? selectedSound;
  String? previewingSound;
  String? soundError;
  String? saveError;
  bool loadingSounds = true;
  bool soundsUnavailable = false;
  bool saving = false;
  bool naming = false;
  Timer? previewTimer;
  int previewGeneration = 0;

  List<FocusRoutine> get rhythms => [...FocusRoutine.builtIns, ...customs];
  bool matches(FocusRoutine r) =>
      int.tryParse(fields[0].text.trim()) == r.focusMinutes &&
      int.tryParse(fields[1].text.trim()) == r.shortBreakMinutes &&
      int.tryParse(fields[2].text.trim()) == r.longBreakMinutes;
  String? get selectedRhythm {
    final matching = rhythms.where(matches);
    return matching.where((r) => r.id == preferred).firstOrNull?.id ??
        matching.firstOrNull?.id;
  }

  bool get canSave =>
      !saving && !loadingSounds && (soundsUnavailable || soundSettings != null);

  @override
  void initState() {
    super.initState();
    loadSounds();
  }

  Future<void> loadSounds() async {
    setState(() {
      loadingSounds = true;
      soundsUnavailable = false;
      soundError = null;
    });
    try {
      final loaded = await alertSounds.load();
      if (mounted) {
        setState(() {
          soundSettings = loaded;
          selectedSound = loaded.selectedSound;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          soundsUnavailable = true;
          soundError = 'Alert sounds are unavailable on this platform.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => soundError = 'Alert sounds could not be loaded. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loadingSounds = false);
    }
  }

  Future<void> preview(String sound) async {
    if (saving) return;
    final generation = ++previewGeneration;
    previewTimer?.cancel();
    setState(() {
      previewingSound = sound;
      soundError = null;
    });
    try {
      final duration = await alertSounds.preview(sound);
      if (!mounted || generation != previewGeneration) return;
      previewTimer = Timer(duration, () {
        if (mounted && generation == previewGeneration) {
          setState(() => previewingSound = null);
        }
      });
    } catch (_) {
      if (mounted && generation == previewGeneration) {
        setState(() {
          previewingSound = null;
          soundError = 'This alert sound could not be previewed. Try again.';
        });
      }
    }
  }

  void chooseRhythm(FocusRoutine rhythm) {
    setState(() {
      preferred = rhythm.id;
      fields[0].text = '${rhythm.focusMinutes}';
      fields[1].text = '${rhythm.shortBreakMinutes}';
      fields[2].text = '${rhythm.longBreakMinutes}';
    });
  }

  void saveRhythmDraft() {
    if (!form.currentState!.validate()) return;
    final rhythm = FocusRoutine(
      id: newId(),
      name: name.text.trim(),
      focusMinutes: int.parse(fields[0].text.trim()),
      shortBreakMinutes: int.parse(fields[1].text.trim()),
      longBreakMinutes: int.parse(fields[2].text.trim()),
    );
    setState(() {
      customs.add(rhythm);
      preferred = rhythm.id;
      naming = false;
      name.clear();
    });
  }

  Future<void> save() async {
    if (!canSave || !form.currentState!.validate()) return;
    if (naming) {
      saveRhythmDraft();
    }
    final durations = fields
        .map((field) => int.parse(field.text.trim()))
        .toList();
    setState(() {
      saving = true;
      soundError = null;
      saveError = null;
    });
    final originalSound = soundSettings;
    var changedNativeSound = false;
    try {
      if (soundSettings != null &&
          selectedSound != soundSettings!.selectedSound) {
        final saved = await alertSounds.save(selectedSound!);
        if (!mounted) return;
        if (saved.selectedSound != selectedSound) {
          throw const FormatException('Alert sound was not saved.');
        }
        soundSettings = saved;
        changedNativeSound = true;
      }
      if (!mounted) return;
      widget.controller.updateSettings(
        focus: durations[0],
        shortBreak: durations[1],
        longBreak: durations[2],
        appearance: appearance,
        customRoutines: customs,
        preferredRoutineId: selectedRhythm,
      );
      if (widget.controller.saveError != null) {
        var message =
            'Your settings could not be saved. Your draft is still here; try Save settings again.';
        if (changedNativeSound && originalSound != null) {
          try {
            final restored = await alertSounds.save(
              originalSound.selectedSound,
            );
            if (restored.selectedSound != originalSound.selectedSound) {
              throw const FormatException(
                'Previous alert sound was not restored.',
              );
            }
            soundSettings = restored;
          } catch (_) {
            message +=
                ' The alert sound may have changed and could not be restored. Select your preferred sound and save again.';
          }
        }
        if (mounted) setState(() => saveError = message);
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError = 'Your alert sound could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    previewGeneration++;
    previewTimer?.cancel();
    name.dispose();
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    return PopScope(
      canPop: !saving,
      child: Dialog.fullscreen(
        backgroundColor: colors.ground,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    MergeSemantics(
                      child: Semantics(
                        button: true,
                        label: 'Close settings',
                        child: IconButton(
                          tooltip: 'Close settings',
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading('Rhythm'),
                        Text(
                          'Applies from your next stint. A long break follows every fourth focus.',
                          style: TextStyle(fontSize: 13, color: colors.muted),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < fields.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  key: ValueKey(
                                    'routine-${TimerPhase.values[i].name}',
                                  ),
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    12,
                                    10,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surface,
                                    border: Border.all(color: colors.line),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        TimerPhase.values[i].label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: i == 0
                                              ? colors.focusText
                                              : colors.breakText,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      MergeSemantics(
                                        child: Semantics(
                                          textField: true,
                                          label:
                                              '${TimerPhase.values[i].label} duration in minutes',
                                          child: TextFormField(
                                            key: ValueKey(
                                              'duration-${TimerPhase.values[i].name}',
                                            ),
                                            controller: fields[i],
                                            enabled: !saving,
                                            style: const TextStyle(
                                              fontFamily: 'MartianMono',
                                              fontSize: 28,
                                              fontWeight: FontWeight.w300,
                                            ),
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              filled: false,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder:
                                                  UnderlineInputBorder(),
                                              errorMaxLines: 3,
                                            ),
                                            onChanged: (_) => setState(() {}),
                                            validator: (text) {
                                              final value = int.tryParse(
                                                text?.trim() ?? '',
                                              );
                                              final max = i == 0 ? 120 : 60;
                                              return value == null ||
                                                      value < 1 ||
                                                      value > max
                                                  ? 'Enter 1 to $max minutes.'
                                                  : null;
                                            },
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'min',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 26),
                        heading('Saved rhythms'),
                        Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            border: Border.all(color: colors.line),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < rhythms.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  Divider(height: 1, color: colors.line),
                                _RhythmRow(
                                  rhythm: rhythms[index],
                                  selected: selectedRhythm == rhythms[index].id,
                                  onChoose: saving
                                      ? null
                                      : () => chooseRhythm(rhythms[index]),
                                  onDelete:
                                      customs.any(
                                            (r) => r.id == rhythms[index].id,
                                          ) &&
                                          !saving
                                      ? () => setState(() {
                                          final id = rhythms[index].id;
                                          customs.removeWhere(
                                            (r) => r.id == id,
                                          );
                                          if (preferred == id) preferred = null;
                                        })
                                      : null,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (!naming)
                          OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () {
                                    if (form.currentState!.validate()) {
                                      setState(() => naming = true);
                                    }
                                  },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Save these durations'),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                key: const Key('routine-name'),
                                controller: name,
                                autofocus: true,
                                enabled: !saving,
                                decoration: const InputDecoration(
                                  labelText: 'Rhythm name',
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Enter a rhythm name.'
                                    : value.trim().length > 80
                                    ? 'Use 80 characters or fewer.'
                                    : null,
                                onFieldSubmitted: (_) => saveRhythmDraft(),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  FilledButton(
                                    onPressed: saving ? null : saveRhythmDraft,
                                    child: const Text('Save'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: saving
                                        ? null
                                        : () => setState(() {
                                            naming = false;
                                            name.clear();
                                          }),
                                    child: const Text('Cancel'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        const SizedBox(height: 26),
                        heading("Time’s up sound"),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            previewingSound == null
                                ? 'Plays twice when a stint or break ends.'
                                : 'Playing $previewingSound twice…',
                            style: TextStyle(fontSize: 13, color: colors.muted),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (loadingSounds) const Text('Loading alert sounds…'),
                        if (soundSettings != null)
                          LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                              key: const Key('alert-sound-selection'),
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final sound in soundSettings!.sounds)
                                  SizedBox(
                                    width: (constraints.maxWidth - 8) / 2,
                                    child: _SoundChoice(
                                      sound: sound,
                                      selected: selectedSound == sound,
                                      enabled: !saving,
                                      onChoose: () => setState(() {
                                        selectedSound = sound;
                                        soundError = null;
                                      }),
                                      onPreview: () => preview(sound),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (soundError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                soundError!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: soundsUnavailable
                                      ? colors.muted
                                      : colors.error,
                                ),
                              ),
                            ),
                          ),
                        if (!loadingSounds &&
                            !soundsUnavailable &&
                            soundSettings == null)
                          TextButton(
                            onPressed: loadSounds,
                            child: const Text('Retry alert sounds'),
                          ),
                        const SizedBox(height: 26),
                        if (widget.blocker != null) ...[
                          heading('Distractions'),
                          OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () => showBlockerSettings(
                                    context,
                                    widget.blocker!,
                                  ),
                            icon: const Icon(Icons.shield_outlined, size: 18),
                            label: const Text('Block distractions…'),
                          ),
                          const SizedBox(height: 24),
                        ],
                        heading('Keyboard shortcuts'),
                        OutlinedButton.icon(
                          key: const Key('open-keyboard-shortcuts'),
                          onPressed: saving
                              ? null
                              : () => showKeymapSettings(context),
                          icon: const Icon(Icons.keyboard_outlined, size: 18),
                          label: const Text('Keyboard shortcuts…'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Keyboard shortcuts save separately.',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                        const SizedBox(height: 26),
                        heading('Appearance'),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'system',
                                label: Text('System'),
                              ),
                              ButtonSegment(
                                value: 'light',
                                label: Text('Light'),
                              ),
                              ButtonSegment(value: 'dark', label: Text('Dark')),
                            ],
                            selected: {appearance},
                            showSelectedIcon: false,
                            onSelectionChanged: saving
                                ? null
                                : (values) => setState(
                                    () => appearance = values.single,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: colors.ground,
                  border: Border(top: BorderSide(color: colors.line)),
                ),
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (saveError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            saveError!,
                            style: TextStyle(fontSize: 12, color: colors.error),
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.ink,
                            foregroundColor: colors.ground,
                          ),
                          onPressed: canSave ? save : null,
                          child: Text(saving ? 'Saving…' : 'Save settings'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RhythmRow extends StatelessWidget {
  const _RhythmRow({
    required this.rhythm,
    required this.selected,
    this.onChoose,
    this.onDelete,
  });
  final FocusRoutine rhythm;
  final bool selected;
  final VoidCallback? onChoose;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            checked: selected,
            inMutuallyExclusiveGroup: true,
            child: TextButton(
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                shape: const RoundedRectangleBorder(),
              ),
              onPressed: onChoose,
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: selected ? colors.focusText : colors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rhythm.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    rhythmDigits(rhythm),
                    style: TextStyle(
                      fontFamily: 'MartianMono',
                      fontSize: 11,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onDelete != null)
          MergeSemantics(
            child: Semantics(
              button: true,
              label: 'Delete ${rhythm.name}',
              child: IconButton(
                tooltip: 'Delete ${rhythm.name}',
                onPressed: onDelete,
                icon: const Icon(Icons.close, size: 17),
              ),
            ),
          ),
      ],
    );
  }
}

class _SoundChoice extends StatelessWidget {
  const _SoundChoice({
    required this.sound,
    required this.selected,
    required this.enabled,
    required this.onChoose,
    required this.onPreview,
  });
  final String sound;
  final bool selected;
  final bool enabled;
  final VoidCallback onChoose;
  final VoidCallback onPreview;
  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? colors.focus : colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              checked: selected,
              inMutuallyExclusiveGroup: true,
              child: TextButton(
                key: ValueKey('alert-sound-$sound'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(left: 10, right: 2),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: enabled ? onChoose : null,
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 16,
                      color: selected ? colors.focusText : colors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sound,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: colors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          MergeSemantics(
            child: Semantics(
              button: true,
              label: 'Preview $sound',
              child: IconButton(
                key: selected
                    ? const Key('preview-alert-sound')
                    : ValueKey('preview-alert-$sound'),
                tooltip: 'Preview $sound',
                onPressed: enabled ? onPreview : null,
                icon: Icon(
                  Icons.volume_up_outlined,
                  size: 17,
                  color: colors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
