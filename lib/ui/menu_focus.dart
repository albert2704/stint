import 'package:flutter/material.dart';
import 'theme.dart';

/// Supplies the keyboard ring for a popup with a custom child. The popup keeps
/// its own focus node, keyboard shortcuts, semantics, and hover treatment.
class MenuFocusRing extends StatefulWidget {
  const MenuFocusRing({super.key, required this.child, this.radius = 12});
  final Widget child;
  final double radius;
  @override
  State<MenuFocusRing> createState() => _MenuFocusRingState();
}

class _MenuFocusRingState extends State<MenuFocusRing> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (value) => setState(() => focused = value),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        border: focused
            ? Border.all(
                color: StintColors.of(context).focusText,
                width: 2,
                strokeAlign: 3,
              )
            : null,
      ),
      child: widget.child,
    ),
  );
}
