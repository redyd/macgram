import 'package:flutter/material.dart';

/// Follows the system until the toolbar button is used. Not persisted across launches.
final themeMode = ValueNotifier(ThemeMode.system);

/// Flat editor look: thin borders, small radii, no ripples, no elevation tints.
ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = Color(dark ? 0xFF1B1E25 : 0xFFFBFBF9);
  final field = Color(dark ? 0xFF14171C : 0xFFFFFFFF);
  final line = Color(dark ? 0xFF313743 : 0xFFDAD9D2);
  final fg = Color(dark ? 0xFFE4E7EE : 0xFF22262B);
  final muted = Color(dark ? 0xFF8892A6 : 0xFF6B7280);
  final accent = Color(dark ? 0xFF7AB7FF : 0xFF2563C9);
  final onAccent = dark ? const Color(0xFF0E1116) : Colors.white;

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  final panel = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    side: BorderSide(color: line),
  );
  OutlineInputBorder input(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: accent.withValues(alpha: 0.18),
      onSecondaryContainer: fg,
      error: Color(dark ? 0xFFFF7B72 : 0xFFC62828),
      onError: Colors.white,
      surface: bg,
      onSurface: fg,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: line,
    ),
    scaffoldBackgroundColor: bg,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerTheme: DividerThemeData(color: line, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: panel,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: panel,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: Color(dark ? 0xFF3A4150 : 0xFF22262B),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      isDense: true,
      filled: true,
      fillColor: field,
      hintStyle: TextStyle(color: muted),
      border: input(line),
      enabledBorder: input(line),
      focusedBorder: input(accent, 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape, foregroundColor: fg),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: shape, foregroundColor: fg),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: shape,
        side: BorderSide(color: line),
        foregroundColor: muted,
        selectedForegroundColor: accent,
        selectedBackgroundColor: accent.withValues(alpha: 0.18),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      side: BorderSide(color: muted, width: 1.5),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: accent.withValues(alpha: 0.12),
    ),
  );
}
