import 'package:flutter/material.dart';

/// A local reading palette; unrelated routes keep their existing app theme.
class StudyTheme extends StatelessWidget {
  const StudyTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF315B78),
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: dark ? const Color(0xFFA5CCE5) : const Color(0xFF244D69),
      surface: dark ? const Color(0xFF141E28) : const Color(0xFFF3F6F8),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: scheme.surface,
        textTheme: base.textTheme.copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontFamily: 'Georgia',
            fontFamilyFallback: const ['Songti SC', 'serif'],
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      child: child,
    );
  }
}
