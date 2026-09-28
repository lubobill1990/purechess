import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/app_theme.dart';
import 'package:purechess/features/home/study_theme.dart';
import 'package:purechess/widgets/board/chess_board.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? buildDarkTheme() : buildLightTheme();
    test('wood and knight ${theme.brightness} contrast and components', () {
      final colors = theme.colorScheme;
      for (final (foreground, background) in [
        (colors.onSurface, colors.surface),
        (colors.onSurface, colors.surfaceContainerLow),
        (colors.onSurfaceVariant, colors.surfaceContainerHighest),
        (colors.primary, colors.surface),
        (colors.onPrimary, colors.primary),
        (colors.onPrimaryContainer, colors.primaryContainer),
        (colors.onSecondaryContainer, colors.secondaryContainer),
        (colors.onTertiary, colors.tertiary),
        (colors.onTertiaryContainer, colors.tertiaryContainer),
        (colors.error, colors.surface),
        (colors.onInverseSurface, colors.inverseSurface),
      ]) {
        expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
      expect(theme.appBarTheme.centerTitle, isTrue);
      expect(theme.appBarTheme.backgroundColor, Colors.transparent);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.appBarTheme.titleTextStyle!.fontFamily, 'Georgia');
      expect(
        theme.textTheme.headlineLarge!.fontFamilyFallback,
        contains('Songti SC'),
      );
      expect(theme.textTheme.bodyLarge!.fontFamily, isNot('Georgia'));
      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(16),
      );
      for (final style in [
        theme.filledButtonTheme.style!,
        theme.outlinedButtonTheme.style!,
        theme.segmentedButtonTheme.style!,
      ]) {
        expect(
          (style.shape!.resolve({})! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(12),
        );
        expect(style.enableFeedback, isFalse);
      }
      expect(theme.listTileTheme.enableFeedback, isFalse);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      final lightSquare = dark
          ? BoardPainter.nightLightSquare
          : BoardPainter.lightSquare;
      final darkSquare = dark
          ? BoardPainter.nightDarkSquare
          : BoardPainter.darkSquare;
      expect(contrast(BoardPainter.ink, lightSquare), greaterThan(4.5));
      expect(contrast(BoardPainter.ivory, darkSquare), greaterThan(4.5));
    });

    testWidgets('reading wrapper inherits explicit ${theme.brightness}', (
      tester,
    ) async {
      // An explicit app theme must win over the opposite platform preference.
      tester.binding.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.light
          : Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const StudyTheme(child: Scaffold(body: Text('阅读'))),
        ),
      );
      final inherited = Theme.of(tester.element(find.text('阅读')));
      expect(inherited.brightness, theme.brightness);
      expect(inherited.colorScheme, theme.colorScheme);
      expect(inherited.filledButtonTheme.style!.enableFeedback, isFalse);
    });
  }
}
