import 'package:flutter/material.dart';

@immutable
class StintColors {
  const StintColors({
    required this.ground,
    required this.surface,
    required this.raised,
    required this.line,
    required this.line2,
    required this.track,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.focus,
    required this.focusText,
    required this.breakColor,
    required this.breakText,
    required this.onAccent,
    required this.error,
    required this.chart,
  });
  final Color ground, surface, raised, line, line2, track, ink, ink2, muted;
  final Color focus, focusText, breakColor, breakText, onAccent, error;

  /// Progress chart bars: at least 3:1 against surface in both themes.
  final Color chart;
  static const dark = StintColors(
    ground: Color(0xFF111214),
    surface: Color(0xFF1A1B1F),
    raised: Color(0xFF222429),
    line: Color(0xFF2C2F35),
    line2: Color(0xFF3A3D44),
    track: Color(0xFF2C2F35),
    ink: Color(0xFFEDEBE6),
    ink2: Color(0xFFC9C8C3),
    muted: Color(0xFF9C9FA6),
    focus: Color(0xFFF2893B),
    focusText: Color(0xFFF2893B),
    breakColor: Color(0xFF6CB4EE),
    breakText: Color(0xFF6CB4EE),
    onAccent: Color(0xFF16110C),
    error: Color(0xFFFF8A80),
    chart: Color(0xFFF2893B),
  );
  static const light = StintColors(
    ground: Color(0xFFF4F3F0),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFECEBE7),
    line: Color(0xFFDEDCD6),
    line2: Color(0xFFC9C7C0),
    track: Color(0xFFE2E0DA),
    ink: Color(0xFF17181B),
    ink2: Color(0xFF3A3C41),
    muted: Color(0xFF5E6168),
    focus: Color(0xFFEE7F2D),
    focusText: Color(0xFFA84E0B),
    breakColor: Color(0xFF4A9FE0),
    breakText: Color(0xFF1F5F94),
    onAccent: Color(0xFF1A0F05),
    error: Color(0xFFB3261E),
    chart: Color(0xFFD9681A),
  );
  static StintColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
  Color accent(bool isFocus) => isFocus ? focus : breakColor;
  Color accentText(bool isFocus) => isFocus ? focusText : breakText;
}

ThemeData deskTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? StintColors.dark
      : StintColors.light;
  final scheme =
      ColorScheme.fromSeed(seedColor: c.focus, brightness: brightness).copyWith(
        primary: c.focus,
        onPrimary: c.onAccent,
        secondary: c.breakColor,
        onSecondary: c.onAccent,
        surface: c.surface,
        onSurface: c.ink,
        onSurfaceVariant: c.muted,
        surfaceContainerHighest: c.raised,
        outline: c.line2,
        outlineVariant: c.line,
        error: c.error,
      );
  const pill = StadiumBorder();
  WidgetStateProperty<BorderSide?> focusRing({BorderSide? resting}) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          // Two pixels of clear space, then a two-pixel keyboard outline.
          return BorderSide(color: c.focusText, width: 2, strokeAlign: 3);
        }
        return resting;
      });
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'HankenGrotesk',
    scaffoldBackgroundColor: c.ground,
    splashFactory: NoSplash.splashFactory,
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: c.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: c.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: c.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.4, color: c.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: c.ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.ink2,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.line2),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.line2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.line2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.focus, width: 2),
      ),
      labelStyle: TextStyle(color: c.muted),
      hintStyle: TextStyle(color: c.muted, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.focus,
        foregroundColor: c.onAccent,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: pill,
      ).copyWith(side: focusRing()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: c.ink2,
            minimumSize: const Size(40, 40),
            side: BorderSide(color: c.line2),
            shape: pill,
          ).copyWith(
            side: focusRing(resting: BorderSide(color: c.line2)),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink2,
        minimumSize: const Size(40, 40),
        shape: pill,
      ).copyWith(side: focusRing()),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.ink2,
        minimumSize: const Size(40, 40),
        shape: pill,
        focusColor: c.focus.withValues(alpha: .24),
      ).copyWith(side: focusRing()),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.focus : c.line2,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.onAccent : c.muted,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.focus,
      thumbColor: c.focus,
      inactiveTrackColor: c.track,
      trackHeight: 4,
      overlayColor: c.focus.withValues(alpha: .16),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.raised,
      selectedColor: c.ink,
      side: BorderSide(color: c.line2),
      shape: pill,
      labelStyle: TextStyle(fontSize: 12, color: c.ink2),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        color: c.ground,
        fontFamily: 'HankenGrotesk',
        fontSize: 12,
      ),
    ),
  );
}

class DeskPanel extends StatelessWidget {
  const DeskPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? StintColors.of(context).surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: StintColors.of(context).line),
    ),
    child: child,
  );
}
