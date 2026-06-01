import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../keymap.dart';
import 'theme.dart';

Future<void> showKeymapSettings(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const KeymapSettings(),
);

class KeymapSettings extends StatefulWidget {
  const KeymapSettings({super.key, this.keymap = const StintKeymap()});

  final StintKeymap keymap;

  @override
  State<KeymapSettings> createState() => _KeymapSettingsState();
}

class _KeymapSettingsState extends State<KeymapSettings> {
  ShortcutSettings? settings;
  final bindings = <StintShortcutAction, ShortcutBinding?>{};
  bool global = true;
  bool loading = true;
  bool saving = false;
  bool unavailable = false;
  bool cancelling = false;
  StintShortcutAction? recording;
  String? error;
  int recordingGeneration = 0;

  bool get editing =>
      settings != null && !loading && !saving && recording == null;

  @override
  void initState() {
    super.initState();
    load();
  }

  String errorMessage(Object failure, String fallback) {
    if (failure is MissingPluginException) {
      return 'Keyboard shortcuts are unavailable on this platform.';
    }
    if (failure is PlatformException &&
        failure.message?.trim().isNotEmpty == true) {
      return failure.message!;
    }
    return fallback;
  }

  void useConfiguration(ShortcutConfiguration configuration) {
    global = configuration.global;
    bindings
      ..clear()
      ..addAll(configuration.bindings);
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      unavailable = false;
      error = null;
    });
    try {
      final loaded = await widget.keymap.load();
      if (!mounted) return;
      setState(() {
        settings = loaded;
        useConfiguration(loaded.configuration);
        error = loaded.error;
      });
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        unavailable = failure is MissingPluginException;
        error = errorMessage(
          failure,
          'Keyboard shortcuts could not be loaded. Try again.',
        );
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> record(StintShortcutAction action) async {
    if (!editing) return;
    final generation = ++recordingGeneration;
    setState(() {
      recording = action;
      error = null;
    });
    try {
      final binding = await widget.keymap.record();
      if (!mounted || generation != recordingGeneration) return;
      if (binding != null) setState(() => bindings[action] = binding);
    } catch (failure) {
      if (!mounted || generation != recordingGeneration) return;
      setState(() {
        error = errorMessage(failure, 'This shortcut could not be recorded.');
      });
    } finally {
      if (mounted && generation == recordingGeneration) {
        setState(() => recording = null);
      }
    }
  }

  Future<bool> cancelRecording() async {
    if (recording == null) return true;
    if (cancelling) return false;
    ++recordingGeneration;
    setState(() => cancelling = true);
    try {
      await widget.keymap.cancelRecording();
      return true;
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = errorMessage(
            failure,
            'Shortcut recording could not be cancelled. Try again.',
          );
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          cancelling = false;
          recording = null;
        });
      }
    }
  }

  Future<void> close() async {
    if (saving || cancelling) return;
    if (recording != null && !await cancelRecording()) return;
    if (mounted) Navigator.pop(context);
  }

  Future<void> save() async {
    if (!editing) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await widget.keymap.save(
        ShortcutConfiguration(global: global, bindings: Map.of(bindings)),
      );
      if (!mounted) return;
      if (saved.error != null) {
        setState(() => error = saved.error);
      } else {
        Navigator.pop(context);
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = errorMessage(
            failure,
            'Your shortcuts could not be saved. Your draft is still here. Try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    ++recordingGeneration;
    if (recording != null) {
      unawaited(widget.keymap.cancelRecording().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (recording != null) {
            cancelRecording();
          } else {
            close();
          }
        },
      },
      child: PopScope(
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
                          'Keyboard shortcuts',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close keyboard shortcuts',
                        onPressed: saving || cancelling ? null : close,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (loading)
                          Semantics(
                            liveRegion: true,
                            child: const Text('Loading keyboard shortcuts…'),
                          ),
                        if (settings != null) ...[
                          DropdownButtonFormField<bool>(
                            key: ValueKey('shortcut-scope-$global'),
                            initialValue: global,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Shortcut scope',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: true,
                                child: Text('Everywhere on this Mac'),
                              ),
                              DropdownMenuItem(
                                value: false,
                                child: Text('Only in Stint'),
                              ),
                            ],
                            onChanged: !editing
                                ? null
                                : (value) => setState(() {
                                    global = value!;
                                    error = null;
                                  }),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Stint must be running to use shortcuts. Include Control or Command when recording.',
                            style: TextStyle(fontSize: 13, color: colors.muted),
                          ),
                          const SizedBox(height: 20),
                          for (final action in StintShortcutAction.values)
                            shortcutRow(action, colors),
                          TextButton(
                            onPressed: !editing
                                ? null
                                : () => setState(() {
                                    useConfiguration(settings!.defaults);
                                    error = null;
                                  }),
                            child: const Text('Restore defaults'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Changes apply when you save shortcuts.',
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ],
                        if (!loading && !unavailable && settings == null)
                          TextButton(
                            onPressed: load,
                            child: const Text('Retry keyboard shortcuts'),
                          ),
                      ],
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
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: SingleChildScrollView(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  key: const Key('shortcut-error'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: unavailable
                                        ? colors.muted
                                        : colors.error,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            key: const Key('shortcut-cancel'),
                            onPressed: saving || cancelling ? null : close,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: editing ? save : null,
                            child: Text(saving ? 'Saving…' : 'Save shortcuts'),
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
      ),
    );
  }

  Widget shortcutRow(StintShortcutAction action, StintColors colors) {
    final isRecording = recording == action;
    final binding = bindings[action];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            action.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  enabled: editing,
                  onTap: editing ? () => record(action) : null,
                  label: 'Record shortcut for ${action.label}',
                  value: isRecording
                      ? 'Press shortcut. Escape cancels.'
                      : binding?.label ?? 'Not set',
                  excludeSemantics: true,
                  child: OutlinedButton(
                    key: ValueKey('shortcut-record-${action.name}'),
                    onPressed: editing ? () => record(action) : null,
                    child: Text(
                      isRecording
                          ? 'Press shortcut…'
                          : binding?.label ?? 'Record shortcut',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isRecording)
                TextButton(
                  key: const Key('shortcut-cancel-recording'),
                  onPressed: cancelling ? null : cancelRecording,
                  child: const Text('Cancel'),
                )
              else
                Semantics(
                  button: true,
                  enabled: editing && binding != null,
                  onTap: editing && binding != null
                      ? () => setState(() {
                          bindings[action] = null;
                          error = null;
                        })
                      : null,
                  label: 'Clear shortcut for ${action.label}',
                  excludeSemantics: true,
                  child: TextButton(
                    key: ValueKey('shortcut-clear-${action.name}'),
                    onPressed: editing && binding != null
                        ? () => setState(() {
                            bindings[action] = null;
                            error = null;
                          })
                        : null,
                    child: const Text('Clear'),
                  ),
                ),
            ],
          ),
          if (isRecording)
            Semantics(
              liveRegion: true,
              child: const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Escape cancels.', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}
