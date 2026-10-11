import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../blocker.dart';
import 'single_dialog.dart';
import 'theme.dart';

final _blockerDialog = SingleStintDialog();

Future<void> showBlockerSettings(
  BuildContext context,
  BlockerController controller,
) => _blockerDialog.show(
  context,
  (_) => BlockerSettingsDialog(controller: controller),
);

class BlockerSettingsDialog extends StatefulWidget {
  const BlockerSettingsDialog({super.key, required this.controller});

  final BlockerController controller;

  @override
  State<BlockerSettingsDialog> createState() => _BlockerSettingsDialogState();
}

class _BlockerSettingsDialogState extends State<BlockerSettingsDialog> {
  final domainInput = TextEditingController();
  final domainFocus = FocusNode();
  final apps = <BlockedApp>[];
  final domains = <String>[];
  bool loaded = false;
  bool enabled = false;
  bool busy = false;
  bool saving = false;
  String? error;
  String? domainError;

  bool get editing => loaded && !busy;

  @override
  void initState() {
    super.initState();
    loadDraft();
    widget.controller.addListener(controllerChanged);
  }

  @override
  void didUpdateWidget(BlockerSettingsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(controllerChanged);
      loaded = false;
      loadDraft();
      widget.controller.addListener(controllerChanged);
    }
  }

  void loadDraft() {
    if (loaded || !widget.controller.ready) return;
    final settings = widget.controller.settings;
    enabled = settings.enabled;
    apps
      ..clear()
      ..addAll(settings.apps);
    domains
      ..clear()
      ..addAll(settings.domains);
    loaded = true;
  }

  void controllerChanged() {
    if (!mounted) return;
    setState(loadDraft);
  }

  @override
  void dispose() {
    widget.controller.removeListener(controllerChanged);
    domainInput.dispose();
    domainFocus.dispose();
    super.dispose();
  }

  String failureMessage(Object failure, String fallback) {
    if (failure is PlatformException &&
        failure.message?.trim().isNotEmpty == true) {
      return failure.message!;
    }
    if (failure is MissingPluginException) {
      return 'This feature is available in the Stint Mac app.';
    }
    return fallback;
  }

  void close() {
    if (!busy) Navigator.of(context).pop();
  }

  bool addDomain({bool focusField = true}) {
    final input = domainInput.text.trim();
    if (input.isEmpty) return true;
    final domain = normalizeBlockedDomain(input);
    if (domain == null) {
      setState(() {
        domainError =
            'Enter a website such as reddit.com. Use a domain or an http/https URL.';
      });
      domainFocus.requestFocus();
      return false;
    }
    if (domains.contains(domain)) {
      setState(() => domainError = 'This website is already on your list.');
      domainFocus.requestFocus();
      return false;
    }
    if (domains.length >= 200) {
      setState(() => domainError = 'You can block up to 200 websites.');
      return false;
    }
    setState(() {
      domains.add(domain);
      domainError = null;
      error = null;
      domainInput.clear();
    });
    if (focusField) domainFocus.requestFocus();
    return true;
  }

  Future<void> chooseApps() async {
    if (!editing) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await widget.controller.chooseApps();
      if (!mounted) return;
      final merged = {for (final app in apps) app.bundleId: app};
      for (final app in selected) {
        merged[app.bundleId] = app;
      }
      if (merged.length > 100) {
        setState(
          () => error = 'You can block up to 100 apps. Choose fewer apps.',
        );
      } else {
        setState(() {
          apps
            ..clear()
            ..addAll(merged.values);
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failureMessage(
            failure,
            'Apps could not be selected. Try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm({
    required String title,
    required String message,
    required String action,
  }) async =>
      await _blockerDialog.withChild<bool?>(
        context,
        () => showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep blocking'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ),
      ) ??
      false;

  Future<void> save() async {
    if (!editing || !addDomain(focusField: false)) return;
    setState(() {
      busy = true;
      saving = true;
      error = null;
    });
    try {
      if (widget.controller.relaxesProtection(
        enabled: enabled,
        apps: apps,
        domains: domains,
      )) {
        final confirmedSession = widget.controller.sessionId;
        final accepted = await confirm(
          title: 'Change your active blocklist?',
          message:
              'These changes will make some distractions available during your current focus stint.',
          action: 'Save changes',
        );
        if (!mounted || !accepted) return;
        if (widget.controller.active &&
            widget.controller.sessionId != confirmedSession) {
          setState(
            () => error =
                'A new focus stint has started. Save again to confirm changes for this stint.',
          );
          return;
        }
      }
      await widget.controller.save(
        enabled: enabled,
        apps: List.of(apps),
        domains: List.of(domains),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failureMessage(
            failure,
            'Your blocklist could not be saved. Your draft is still here. Try again.',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          saving = false;
        });
      }
    }
  }

  Future<void> unblock() async {
    final session = widget.controller.sessionId;
    if (!editing || !widget.controller.active || session == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final accepted = await confirm(
        title: 'Unblock this stint?',
        message:
            'Your apps and websites will be available for the rest of this focus stint, including if you pause and resume. Blocking returns for your next stint.',
        action: 'Unblock this stint',
      );
      if (!mounted || !accepted) return;
      if (widget.controller.sessionId != session) {
        setState(
          () =>
              error = 'The focus stint has changed. No blocking was released.',
        );
        return;
      }
      await widget.controller.unblock(session);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failureMessage(
            failure,
            'This stint could not be unblocked. Try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> updateFilterSetup({
    bool enable = false,
    bool remove = false,
  }) async {
    if (!editing || widget.controller.checkingFilter) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (remove) {
        await widget.controller.removeFilter();
      } else if (!enable) {
        await widget.controller.refreshFilter();
      } else {
        await widget.controller.enableFilter();
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failureMessage(
            failure,
            'Website helper setup could not be checked. Try Refresh.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = StintColors.of(context);
    final controller = widget.controller;
    final visibleError = error ?? controller.error;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: PopScope(
        canPop: !busy,
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
                          'Block distractions',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close distraction blocking',
                        onPressed: busy ? null : close,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!loaded)
                          Semantics(
                            liveRegion: true,
                            child: const Text('Loading your blocklist…'),
                          ),
                        if (loaded) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              border: Border.all(color: colors.line),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      controller.active
                                          ? Icons.shield_outlined
                                          : Icons.shield_moon_outlined,
                                      color: colors.focusText,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        controller.statusLabel,
                                        key: const Key('blocker-status'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (controller.bypassed)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Blocking returns for your next focus stint.',
                                    ),
                                  ),
                                if (controller.active)
                                  TextButton(
                                    key: const Key('blocker-unblock'),
                                    onPressed: editing ? unblock : null,
                                    child: const Text('Unblock this stint'),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            key: const Key('blocker-enabled'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Block during focus'),
                            subtitle: const Text(
                              'Only while your focus timer is running. Pausing or taking a break releases blocking.',
                            ),
                            value: enabled,
                            onChanged: editing
                                ? (value) => setState(() => enabled = value)
                                : null,
                          ),
                          const SizedBox(height: 20),
                          sectionTitle(
                            'Mac apps',
                            '${apps.length}/100',
                            colors,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Selected apps are hidden when you switch to them. Your unsaved work stays open.',
                            style: TextStyle(color: colors.muted, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          if (apps.isEmpty)
                            Text(
                              'No apps selected.',
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 13,
                              ),
                            ),
                          for (final app in apps)
                            listItem(
                              title: app.name,
                              subtitle: app.bundleId,
                              icon: Icons.apps_outlined,
                              removeLabel: 'Remove ${app.name}',
                              removeKey: ValueKey(
                                'blocker-remove-app-${app.bundleId}',
                              ),
                              onRemove: () => setState(() => apps.remove(app)),
                              colors: colors,
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const Key('blocker-add-apps'),
                            onPressed: editing && apps.length < 100
                                ? chooseApps
                                : null,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Choose apps'),
                          ),
                          const SizedBox(height: 24),
                          sectionTitle(
                            'Websites',
                            '${domains.length}/200',
                            colors,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Blocks the domain and its subdomains, including www. Enter a domain without a wildcard.',
                            style: TextStyle(color: colors.muted, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('blocker-domain-input'),
                            controller: domainInput,
                            focusNode: domainFocus,
                            enabled: editing,
                            maxLength: 2048,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Website domain or URL',
                              hintText: 'reddit.com',
                              counterText: '',
                              errorText: domainError,
                              errorMaxLines: 3,
                              suffixIcon: IconButton(
                                key: const Key('blocker-add-domain'),
                                tooltip: 'Add website',
                                onPressed: editing ? addDomain : null,
                                icon: const Icon(Icons.add, size: 20),
                              ),
                            ),
                            onChanged: (_) {
                              if (domainError != null) {
                                setState(() => domainError = null);
                              }
                            },
                            onSubmitted: (_) => addDomain(),
                          ),
                          for (final domain in domains)
                            listItem(
                              title: domain,
                              icon: Icons.language,
                              removeLabel: 'Remove $domain',
                              removeKey: ValueKey(
                                'blocker-remove-domain-$domain',
                              ),
                              onRemove: () =>
                                  setState(() => domains.remove(domain)),
                              colors: colors,
                            ),
                          const SizedBox(height: 24),
                          sectionTitle('Website blocker', null, colors),
                          const SizedBox(height: 8),
                          filterCard(colors),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const Key('blocker-refresh-filter'),
                            onPressed: editing && !controller.checkingFilter
                                ? () => updateFilterSetup()
                                : null,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(
                              controller.checkingFilter
                                  ? 'Checking…'
                                  : 'Refresh',
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Browsers stay open. Proxy settings affect all accounts on this Mac, including Stint’s YouTube music. Use a built-in or local track while YouTube is blocked.',
                            style: TextStyle(color: colors.muted, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'For browsers using macOS proxy settings. Loaded pages and buffered media can remain visible. VPNs and custom proxy setups are unsupported. Reload failed pages after your break starts.',
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Save your list separately. Setup and removal reveal a command in Finder. Double-click it, then approve it in Terminal. No Apple subscription or browser extension is needed.',
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                        ],
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (visibleError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 90),
                            child: SingleChildScrollView(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  visibleError,
                                  key: const Key('blocker-error'),
                                  style: TextStyle(
                                    color: colors.error,
                                    fontSize: 13,
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
                            key: const Key('blocker-cancel'),
                            onPressed: busy ? null : close,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            key: const Key('blocker-save'),
                            onPressed: editing ? save : null,
                            child: Text(saving ? 'Saving…' : 'Save blocklist'),
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

  Widget filterCard(StintColors colors) {
    final filter = widget.controller.filter;
    return Container(
      key: const Key('blocker-filter'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              filter.label,
              key: const Key('blocker-filter-status'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: filter.configured ? colors.focusText : colors.muted,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filter.message,
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          if (filter.configured) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('blocker-remove-helper'),
              onPressed: !widget.controller.checkingFilter
                  ? () => updateFilterSetup(remove: true)
                  : null,
              child: const Text('Remove helper…'),
            ),
          ],
          if (filter.canEnable) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('blocker-enable-filter'),
              onPressed: editing && !widget.controller.checkingFilter
                  ? () => updateFilterSetup(enable: true)
                  : null,
              child: Text(
                widget.controller.enablingFilter
                    ? 'Setting up…'
                    : 'Set up website blocker',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget sectionTitle(String title, String? count, StintColors colors) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      if (count != null)
        Text(count, style: TextStyle(fontSize: 12, color: colors.muted)),
    ],
  );

  Widget listItem({
    required String title,
    String? subtitle,
    required IconData icon,
    required String removeLabel,
    required Key removeKey,
    required VoidCallback onRemove,
    required StintColors colors,
  }) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: colors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: colors.muted),
                ),
            ],
          ),
        ),
        IconButton(
          key: removeKey,
          tooltip: removeLabel,
          onPressed: editing ? onRemove : null,
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );
}
