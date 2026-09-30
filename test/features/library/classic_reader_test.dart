import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/app_theme.dart';
import 'package:purechess/features/library/classic_library.dart';
import 'package:purechess/features/library/classic_library_screen.dart';
import 'package:purechess/features/library/classic_reader_screen.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';

void main() {
  final games = ClassicLibrary.parse(
    File(ClassicLibrary.asset).readAsStringSync(),
  );
  final game = games.first;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> reader(
    WidgetTester tester, {
    int ply = 0,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ClassicReaderScreen(game: game, prefs: prefs, initialPly: ply),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reader steps change the board, progress, comment and saved cursor',
    (tester) async {
      await reader(tester);
      expect(find.text('0 / 33 半回合'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '上一步'))
            .onPressed,
        isNull,
      );
      final initial = tester
          .widget<ChessBoard>(find.byType(ChessBoard))
          .board
          .toFen();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 33 半回合'), findsOneWidget);
      final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
      expect(board.board.toFen(), isNot(initial));
      expect(board.enabled, false);
      expect(ReadingProgress.read(prefs).ply, 1);
      await tester.tap(find.text('上一步'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).board.toFen(),
        initial,
      );
      expect(ReadingProgress.read(prefs).ply, 0);
    },
  );

  testWidgets(
    'final position disables next and supports backwards keyboard navigation',
    (tester) async {
      await reader(tester, ply: game.plies);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
            .onPressed,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(ReadingProgress.read(prefs).ply, 32);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(ReadingProgress.read(prefs).ply, 33);
    },
  );

  testWidgets(
    'slider seeks to actual annotated position and survives remount',
    (tester) async {
      await reader(tester);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(15);
      await tester.pumpAndSettle();
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('reader-comment')))
          .data!;
      expect(text, contains('先出马'));
      expect(ReadingProgress.read(prefs).ply, 15);
      await tester.pumpWidget(const SizedBox());
      await reader(tester, ply: ReadingProgress.read(prefs).ply);
      expect(find.text('15 / 33 半回合'), findsOneWidget);
    },
  );

  testWidgets(
    'saving failure is visible and retry persists without losing the position',
    (tester) async {
      final store = FailingPreferencesStore()
        ..failKey = 'flutter.${ReadingProgress.key}';
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      prefs = await SharedPreferences.getInstance();
      await reader(tester, ply: 15);
      expect(find.text('阅读进度保存失败，请重试。'), findsOneWidget);
      store.failKey = null;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('阅读进度保存失败，请重试。'), findsNothing);
      expect(
        store.getAll(),
        completion(
          containsPair(
            'flutter.${ReadingProgress.key}',
            '{"id":"opera-1858","ply":15}',
          ),
        ),
      );
    },
  );

  testWidgets('library lists 21 games, opens selection, resumes exactly', (
    tester,
  ) async {
    await ReadingProgress.save(prefs, game, 17);
    await tester.pumpWidget(
      MaterialApp(
        home: ClassicLibraryScreen(prefs: prefs, load: () async => games),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('21 盘名局'), findsOneWidget);
    await tester.tap(find.text('歌剧院局'));
    await tester.pumpAndSettle();
    expect(find.text('17 / 33 半回合'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('继续阅读 · 17 / 33'), findsOneWidget);
  });

  testWidgets('reading route resumes saved game instead of catalogue', (
    tester,
  ) async {
    await ReadingProgress.save(prefs, games[1], 20);
    await tester.pumpWidget(
      MaterialApp(
        home: ClassicLibraryScreen(
          prefs: prefs,
          resume: true,
          load: () async => games,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('不朽局'), findsOneWidget);
    expect(find.text('20 / 45 半回合'), findsOneWidget);
  });

  testWidgets('new reading route starts opera game', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClassicLibraryScreen(
          prefs: prefs,
          resume: true,
          load: () async => games,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 / 33 半回合'), findsOneWidget);
  });

  for (final raw in [
    'broken',
    '{"id":"removed","ply":3}',
    '{"id":"opera-1858","ply":999}',
  ]) {
    testWidgets('invalid saved reading falls back visibly to catalogue: $raw', (
      tester,
    ) async {
      await prefs.setString(ReadingProgress.key, raw);
      await tester.pumpWidget(
        MaterialApp(
          home: ClassicLibraryScreen(
            prefs: prefs,
            resume: true,
            load: () async => games,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('名局库'), findsOneWidget);
      expect(find.byType(ClassicReaderScreen), findsNothing);
      expect(
        find.textContaining(raw == 'broken' ? '阅读进度无法识别' : '上次阅读的位置已失效'),
        findsOneWidget,
      );
      expect(prefs.getString(ReadingProgress.key), raw);
    });
  }

  testWidgets('asset failure is visible and can be retried', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ClassicLibraryScreen(
          prefs: prefs,
          load: () async {
            if (fail) throw const FormatException('Bad PGN');
            return games;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('名局库读取失败，请重试。'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('歌剧院局'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(844, 390),
      const Size(1024, 1366),
    ]) {
      testWidgets('reader layout $brightness $size with enlarged text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.binding.platformDispatcher.platformBrightnessTestValue =
            brightness;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();
        });
        await reader(tester, scale: 2);
        expect(tester.takeException(), isNull);
        expect(
          Theme.of(tester.element(find.byType(Scaffold))).brightness,
          brightness,
        );
        await tester.ensureVisible(find.text('下一步'));
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
        expect(find.text('1 / 33 半回合'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test(
    'reading progress accepts only valid atomic id and nonnegative ply',
    () async {
      for (final invalid in <Object>[
        true,
        1,
        '{"id":"","ply":1}',
        '{"id":"x","ply":-1}',
        '{"id":"x","ply":"3"}',
      ]) {
        SharedPreferences.setMockInitialValues({ReadingProgress.key: invalid});
        final store = await SharedPreferences.getInstance();
        expect(ReadingProgress.read(store).error, isNotNull);
      }
      await expectLater(
        ReadingProgress.save(prefs, game, -1),
        throwsRangeError,
      );
      await expectLater(
        ReadingProgress.save(prefs, game, 34),
        throwsRangeError,
      );
    },
  );
}
