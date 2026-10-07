import 'package:flutter/material.dart';

/// Follows the system until the toolbar button is used. Not persisted across launches.
final themeMode = ValueNotifier(ThemeMode.system);

/// Interface font; the diagram font is `monoFont` in scene.dart.
const uiFont = 'Inter';

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
  final tip = Color(dark ? 0xFF3A4150 : 0xFF22262B);

  const radius = BorderRadius.all(Radius.circular(6));
  const shape = RoundedRectangleBorder(borderRadius: radius);
  final panel = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    side: BorderSide(color: line),
  );
  OutlineInputBorder input(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: c, width: w),
  );
  TextStyle text(double size, [FontWeight w = FontWeight.w400, Color? c]) =>
      TextStyle(fontSize: size, fontWeight: w, color: c ?? fg, height: 1.35);
  const button = Size(32, 32);

  return ThemeData(
    fontFamily: uiFont,
    // Desktop scale: 14 px body, where Material defaults to 14–16.
    textTheme: TextTheme(
      bodyLarge: text(14),
      bodyMedium: text(14),
      bodySmall: text(13, FontWeight.w400, muted),
      labelLarge: text(14, FontWeight.w500),
      labelMedium: text(12.5, FontWeight.w500, muted),
      titleLarge: text(17, FontWeight.w600),
      titleMedium: text(15, FontWeight.w600),
      titleSmall: text(14, FontWeight.w600),
    ),
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
      surfaceContainerLowest: field,
      onSurface: fg,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: line,
    ),
    scaffoldBackgroundColor: bg,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: fg.withValues(alpha: 0.06),
    focusColor: accent.withValues(alpha: 0.12),
    iconTheme: IconThemeData(size: 18, color: fg),
    dividerTheme: DividerThemeData(color: line, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: panel,
      titleTextStyle: text(16, FontWeight.w600).copyWith(fontFamily: uiFont),
      contentTextStyle: text(14).copyWith(fontFamily: uiFont),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: panel,
      textStyle: text(14).copyWith(fontFamily: uiFont),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tip,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(
        fontFamily: uiFont,
        color: Colors.white,
        fontSize: 13,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 520,
      elevation: 4,
      backgroundColor: tip,
      shape: shape,
      contentTextStyle: const TextStyle(
        fontFamily: uiFont,
        color: Colors.white,
        fontSize: 14,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(muted.withValues(alpha: 0.45)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.3),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: line,
      linearMinHeight: 4,
      borderRadius: BorderRadius.circular(2),
    ),
    listTileTheme: const ListTileThemeData(dense: true, horizontalTitleGap: 8),
    inputDecorationTheme: InputDecorationThemeData(
      isDense: true,
      filled: true,
      fillColor: field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      hintStyle: TextStyle(color: muted),
      labelStyle: TextStyle(color: muted),
      floatingLabelStyle: TextStyle(color: accent),
      border: input(line),
      enabledBorder: input(line),
      focusedBorder: input(accent, 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        minimumSize: button,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shape,
        foregroundColor: fg,
        minimumSize: button,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: shape,
        foregroundColor: fg,
        disabledForegroundColor: muted.withValues(alpha: 0.5),
        iconSize: 18,
        minimumSize: button,
        padding: EdgeInsets.zero,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: shape,
        side: BorderSide(color: line),
        foregroundColor: muted,
        selectedForegroundColor: accent,
        selectedBackgroundColor: accent.withValues(alpha: 0.18),
        minimumSize: button,
        padding: const EdgeInsets.symmetric(horizontal: 10),
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
