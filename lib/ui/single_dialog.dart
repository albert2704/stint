import 'package:flutter/material.dart';

class SingleStintDialog {
  static final _childDialogs = <NavigatorState, int>{};
  final _routes = <NavigatorState, (DialogRoute<void>, GlobalKey)>{};

  Future<T> withChild<T>(
    BuildContext context,
    Future<T> Function() open,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    _childDialogs[navigator] = (_childDialogs[navigator] ?? 0) + 1;
    try {
      return await open();
    } finally {
      final remaining = _childDialogs[navigator]! - 1;
      if (remaining == 0) {
        _childDialogs.remove(navigator);
      } else {
        _childDialogs[navigator] = remaining;
      }
    }
  }

  Future<void> show(BuildContext context, WidgetBuilder builder) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    // Finish the current confirmation before a native menu action can cover it
    // with its parent or another settings dialog.
    if (_childDialogs.containsKey(navigator)) return;
    final previous = _routes[navigator];
    if (previous?.$1.isCurrent ?? false) return;

    final covered = previous != null && previous.$1.isActive;
    final key = covered ? previous.$2 : GlobalKey();
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (context) => KeyedSubtree(
        key: key,
        child: Builder(builder: builder),
      ),
    );
    _routes[navigator] = (route, key);
    // Reparent the keyed content in the same frame. The existing dialog keeps
    // its State and draft; the covering dialog stays in the stack with its own
    // edits intact. Only the obsolete route is removed.
    if (covered) navigator.removeRoute(previous.$1);
    try {
      await navigator.push<void>(route);
    } finally {
      // Removing a covered route completes its old Future too. It must not
      // unregister the new presentation that now owns the same content.
      if (identical(_routes[navigator]?.$1, route)) _routes.remove(navigator);
    }
  }
}
