import 'package:flutter/material.dart';
import '../focus_profiles.dart';
import '../data/models.dart';
import 'single_dialog.dart';
import 'theme.dart';

final _profilesDialog = SingleStintDialog();

Future<void> showFocusProfiles(BuildContext context, FocusProfiles profiles) {
  profiles.initialize();
  return _profilesDialog.show(
    context,
    (_) => FocusProfilesSheet(profiles: profiles),
  );
}

class FocusProfileSelector extends StatelessWidget {
  const FocusProfileSelector({super.key, required this.profiles});
  final FocusProfiles profiles;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: profiles,
    builder: (context, _) => TextButton.icon(
      key: const Key('focus-profiles'),
      onPressed: profiles.busy
          ? null
          : () => showFocusProfiles(context, profiles),
      icon: const Icon(Icons.layers_outlined, size: 16),
      label: Text(
        profiles.busy
            ? 'Applying profile…'
            : profiles.activeProfile?.name ?? 'Focus profiles',
      ),
    ),
  );
}

class FocusProfilesSheet extends StatefulWidget {
  const FocusProfilesSheet({super.key, required this.profiles});
  final FocusProfiles profiles;
  @override
  State<FocusProfilesSheet> createState() => _FocusProfilesSheetState();
}

class _FocusProfilesSheetState extends State<FocusProfilesSheet> {
  Future<void> _name({FocusProfile? profile}) async {
    final text = TextEditingController(text: profile?.name ?? '');
    String? validation;
    await _profilesDialog.withChild(
      context,
      () => showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              profile == null ? 'Save current setup' : 'Rename profile',
            ),
            content: TextField(
              key: const Key('profile-name'),
              controller: text,
              autofocus: true,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Profile name',
                errorText: validation,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = text.text.trim();
                  if (name.isEmpty) {
                    update(() => validation = 'Enter a name.');
                    return;
                  }
                  final saved = profile == null
                      ? widget.profiles.saveCurrent(name)
                      : widget.profiles.rename(profile.id, name);
                  if (saved) {
                    Navigator.pop(context);
                  } else {
                    update(() => validation = widget.profiles.error);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    // Dialog transitions can still hold the text controller for one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
  }

  Future<void> _delete(FocusProfile profile) async {
    final confirmed = await _profilesDialog.withChild(
      context,
      () => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${profile.name}?'),
          content: const Text(
            'Your current timer, sound and blocker settings stay as they are.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) widget.profiles.delete(profile.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final profiles = widget.profiles;
    return ListenableBuilder(
      listenable: profiles,
      builder: (context, _) => Dialog.fullscreen(
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
                        'Focus profiles',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close profiles',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Divider(color: colors.line),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'One choice for your timing, sound and distractions.',
                        style: TextStyle(color: colors.ink2, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Applying a profile prepares an idle focus session. Sound follows its saved Play with timer setting. Blocking begins when you start focus; websites need the helper set up separately.',
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (final profile in profiles.profiles) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            border: Border.all(color: colors.line),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      profile.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (profiles.activeProfile?.id == profile.id)
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: colors.focusText,
                                      size: 19,
                                    ),
                                  PopupMenuButton<String>(
                                    tooltip: '${profile.name} options',
                                    enabled:
                                        !profiles.busy && profiles.available,
                                    onSelected: (action) {
                                      if (action == 'rename') {
                                        _name(profile: profile);
                                      }
                                      if (action == 'update') {
                                        profiles.updateCurrent(profile.id);
                                      }
                                      if (action == 'delete') _delete(profile);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'update',
                                        child: Text(
                                          'Update from current setup',
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'rename',
                                        child: Text('Rename…'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete…'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                profile.mode == FocusMode.flow
                                    ? 'Flow · break when you are ready'
                                    : '${profile.focusMinutes} min focus · ${profile.shortBreakMinutes} / ${profile.longBreakMinutes} min breaks',
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${profile.blockingEnabled ? '${profile.apps.length} apps · ${profile.domains.length} websites' : 'Blocking off'} · ${profile.followTimer ? 'Sound follows timer' : 'Manual sound'}',
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${profiles.music.tracks.where((track) => track.id == profile.trackId).firstOrNull?.title ?? 'Unavailable sound: Quiet Keys fallback'} · ${(profile.volume * 100).round()}% volume',
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (profile.blockingEnabled &&
                                  profile.domains.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${profile.domains.take(3).join(', ')}${profile.domains.length > 3 ? ' +${profile.domains.length - 3} more' : ''}',
                                  style: TextStyle(
                                    color: colors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: profiles.busy
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        profiles.requestApply(profile.id);
                                      },
                                child: Text('Use ${profile.name}'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (profiles.error != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            profiles.error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      if (profiles.warning != null)
                        Text(
                          profiles.warning!,
                          style: TextStyle(color: colors.muted),
                        ),
                      if (profiles.available && profiles.needsInitialization)
                        TextButton(
                          onPressed: profiles.initialize,
                          child: const Text('Load starter profiles'),
                        ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('save-current-profile'),
                        onPressed: profiles.busy || !profiles.available
                            ? null
                            : _name,
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('Save current setup…'),
                      ),
                    ],
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
