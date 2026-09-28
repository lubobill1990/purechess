/// The 「木与骑士」 design system: walnut, gold and warm paper.
library;

import 'package:flutter/material.dart';

import 'sound.dart';

const kDisplayFontFamily = 'Georgia';
const kDisplayFontFallback = ['Songti SC', 'serif'];

ThemeData buildLightTheme() => _base(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFF62431F),
    surface: const Color(0xFFF7F0E0),
  ).copyWith(
    primary: const Color(0xFF62431F),
    onPrimary: const Color(0xFFFFF8EA),
    primaryContainer: const Color(0xFFEED6A0),
    onPrimaryContainer: const Color(0xFF352412),
    secondary: const Color(0xFF6D593B),
    onSecondary: const Color(0xFFFFF8EA),
    secondaryContainer: const Color(0xFFEBDDC0),
    onSecondaryContainer: const Color(0xFF302718),
    tertiary: const Color(0xFF775222),
    onTertiary: const Color(0xFFFFF8EA),
    tertiaryContainer: const Color(0xFFEFDAAA),
    onTertiaryContainer: const Color(0xFF3B2912),
    surfaceContainerLowest: const Color(0xFFFFF8EA),
    surfaceContainerLow: const Color(0xFFF3E7CE),
    surfaceContainer: const Color(0xFFEFE1C5),
    surfaceContainerHigh: const Color(0xFFE9DABE),
    surfaceContainerHighest: const Color(0xFFE3D4B8),
    onSurface: const Color(0xFF302418),
    onSurfaceVariant: const Color(0xFF64543F),
    outline: const Color(0xFF847158),
    outlineVariant: const Color(0xFFCDBB9A),
  ),
);

ThemeData buildDarkTheme() => _base(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFFD8AD55),
    brightness: Brightness.dark,
    surface: const Color(0xFF191510),
  ).copyWith(
    primary: const Color(0xFFD8AD55),
    onPrimary: const Color(0xFF38270F),
    primaryContainer: const Color(0xFF574020),
    onPrimaryContainer: const Color(0xFFF2DDAF),
    secondary: const Color(0xFFD1BB94),
    onSecondary: const Color(0xFF382D1C),
    secondaryContainer: const Color(0xFF4B3D29),
    onSecondaryContainer: const Color(0xFFEBDDC0),
    tertiary: const Color(0xFFD9BD86),
    onTertiary: const Color(0xFF3E2D12),
    tertiaryContainer: const Color(0xFF594522),
    onTertiaryContainer: const Color(0xFFF4E0B7),
    surfaceContainerLowest: const Color(0xFF14110D),
    surfaceContainerLow: const Color(0xFF241E16),
    surfaceContainer: const Color(0xFF2C251B),
    surfaceContainerHigh: const Color(0xFF352D22),
    surfaceContainerHighest: const Color(0xFF403629),
    onSurface: const Color(0xFFEDE0C8),
    onSurfaceVariant: const Color(0xFFCABDA5),
    outline: const Color(0xFFA2937A),
    outlineVariant: const Color(0xFF5C4D38),
  ),
);

ThemeData _base(ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  TextStyle display(TextStyle style) => style.copyWith(
    fontFamily: kDisplayFontFamily,
    fontFamilyFallback: kDisplayFontFallback,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  return quietControlsTheme(
    base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      disabledColor: scheme.onSurfaceVariant,
      textTheme: base.textTheme.copyWith(
        displayLarge: display(base.textTheme.displayLarge!),
        displayMedium: display(base.textTheme.displayMedium!),
        displaySmall: display(base.textTheme.displaySmall!),
        headlineLarge: display(base.textTheme.headlineLarge!),
        headlineMedium: display(base.textTheme.headlineMedium!),
        headlineSmall: display(base.textTheme.headlineSmall!),
        titleLarge: display(base.textTheme.titleLarge!),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: display(base.textTheme.titleLarge!)
            .copyWith(fontSize: 20),
      ),
      cardTheme: CardThemeData(
        elevation: dark ? 1 : 2,
        shadowColor: const Color(0xFF302418).withValues(alpha: dark ? .6 : .18),
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerLow,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          disabledForegroundColor: scheme.onSurfaceVariant,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          shape: rounded,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          disabledForegroundColor: scheme.onSurfaceVariant,
          shape: rounded,
          side: BorderSide(color: scheme.outline.withValues(alpha: .5)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: rounded),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          disabledForegroundColor: scheme.onSurfaceVariant,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          disabledForegroundColor: scheme.onSurfaceVariant,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
