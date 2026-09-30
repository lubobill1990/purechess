import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/router.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/features/puzzle/puzzle_catalog.dart';
import 'package:purechess/features/puzzle/puzzle_repository.dart';
import 'package:purechess/features/puzzle/puzzle_screen.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';
import 'fixtures.dart';

void main() {
  late SharedPreferences prefs;
  late PuzzleRepository repository;
  late FailingPreferencesStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    repository = PuzzleRepository(prefs: prefs, catalog: catalog());
  });
  tearDown(() => repository.dispose());

  Future<void> launch(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  PuzzleSolveScreen solver() => PuzzleSolveScreen(
    repository: repository,
    ids: repository.catalog.byId.keys.toList(),
  );

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> move(WidgetTester tester, String from, String to) async {
    await tester.tap(
      find.byKey(ValueKey('square-$from')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.tap(
      find.byKey(ValueKey('square-$to')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'collection -> list -> solve and back updates collection progress',
    (tester) async {
      await launch(
        tester,
        PuzzleScreen(prefs: prefs, loadCatalog: () async => catalog()),
      );
      await tapText(tester, '双重攻击');
      await tapText(tester, '入门 · <1200');
      expect(find.byType(PuzzleListScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('puzzle-p0')));
      await tester.pumpAndSettle();
      expect(find.byType(ChessBoard), findsOneWidget);
      await move(tester, 'e2', 'e4');
      await move(tester, 'g1', 'f3');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 / 24 已完成'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('已完成 1 / 24 题 · 离线练习'), findsOneWidget);
    },
  );
  testWidgets('two hint taps illuminate only the source; board never shifts', (
    tester,
  ) async {
    await launch(tester, solver());
    final rect = tester.getRect(find.byType(ChessBoard));
    await tapText(tester, '提示思路');
    expect(find.textContaining('同时攻击两个目标'), findsOneWidget);
    expect(find.byKey(const ValueKey('puzzle-hint-square')), findsNothing);
    await tapText(tester, '亮起点格');
    final highlight = tester.getRect(
      find.byKey(const ValueKey('puzzle-hint-square')),
    );
    expect(highlight.left, closeTo(rect.left + rect.width * 4 / 8, .01));
    expect(highlight.top, closeTo(rect.top + rect.height * 6 / 8, .01));
    expect(tester.getRect(find.byType(ChessBoard)), rect);
    await move(tester, 'e2', 'e4');
    expect(find.byKey(const ValueKey('puzzle-hint-square')), findsNothing);
    expect(tester.getRect(find.byType(ChessBoard)), rect);
    final board = tester.widget<ChessBoard>(find.byType(ChessBoard)).board;
    expect(
      board.pieceAt(chess.parseSquare('e5')),
      const chess.Piece(chess.Color.black, chess.PieceType.pawn),
    );
    expect(board.turn, chess.Color.white);
  });
  testWidgets('wrong -> retry -> right removes notebook entry and advances', (
    tester,
  ) async {
    await launch(tester, solver());
    await move(tester, 'd2', 'd4');
    expect(repository.mistakes, {'p0'});
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isFalse);
    await tapText(tester, '再试一次');
    await move(tester, 'e2', 'e4');
    await move(tester, 'g1', 'f3');
    expect(repository.mistakes, isEmpty);
    expect(repository.solved, {'p0'});
    await tapText(tester, '下一题');
    expect(find.text('第 2 / 24 题 · 1000'), findsOneWidget);
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isTrue);
  });
  testWidgets('notebook list removes solved entry when returning', (
    tester,
  ) async {
    await repository.record('p0', correct: false);
    await launch(
      tester,
      PuzzleListScreen(
        repository: repository,
        title: '错题本',
        ids: const ['p0'],
        mistakesOnly: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('puzzle-p0')));
    await tester.pumpAndSettle();
    await move(tester, 'e2', 'e4');
    await move(tester, 'g1', 'f3');
    await tapText(tester, '返回题目列表');
    expect(find.textContaining('暂时没有错题'), findsOneWidget);
  });
  testWidgets('daily route keeps ten saved IDs and updates per-day progress', (
    tester,
  ) async {
    await launch(
      tester,
      PuzzleScreen(
        prefs: prefs,
        loadCatalog: () async => catalog(),
        now: () => DateTime(2026, 9, 28),
      ),
    );
    await tapText(tester, '每日 10 题');
    final ids = (jsonDecode(
      prefs.getString('daily_20260928')!,
    ) as List<dynamic>).cast<String>();
    expect(ids.length, 10);
    expect(find.text('2026-09-28 · 0 / 10 已完成'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('puzzle-${ids.first}')));
    await tester.pumpAndSettle();
    await move(tester, 'e2', 'e4');
    await move(tester, 'g1', 'f3');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2026-09-28 · 1 / 10 已完成'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('今天已完成 1 / 10'), findsOneWidget);
    await tapText(tester, '每日 10 题');
    expect(jsonDecode(prefs.getString('daily_20260928')!), ids);
  });
  testWidgets('daily chooses current local date on tap, including midnight', (
    tester,
  ) async {
    var now = DateTime(2026, 12, 31, 23, 59);
    await launch(
      tester,
      PuzzleScreen(
        prefs: prefs,
        loadCatalog: () async => catalog(),
        now: () => now,
      ),
    );
    await tapText(tester, '每日 10 题');
    expect(prefs.getString('daily_20261231'), isNotNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    now = DateTime(2027, 1, 1);
    await tapText(tester, '每日 10 题');
    expect(prefs.getString('daily_20270101'), isNotNull);
    expect(find.text('2027-01-01 · 0 / 10 已完成'), findsOneWidget);
  });
  testWidgets('save failure is explicit and retry preserves the solved board', (
    tester,
  ) async {
    store.failKey = 'flutter.${PuzzleRepository.progressKey}';
    await launch(tester, solver());
    await move(tester, 'e2', 'e4');
    await move(tester, 'g1', 'f3');
    expect(find.text('进度保存失败，请重试保存'), findsOneWidget);
    expect(repository.solved, isEmpty);
    expect(find.text('下一题'), findsNothing);
    final fen = tester
        .widget<ChessBoard>(find.byType(ChessBoard))
        .board
        .toFen();
    store.failKey = null;
    await tapText(tester, '重试保存');
    expect(repository.solved, {'p0'});
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).board.toFen(),
      fen,
    );
    expect(find.text('下一题'), findsOneWidget);
  });
  testWidgets('load failure has an actionable retry', (tester) async {
    var fail = true;
    await launch(
      tester,
      PuzzleScreen(
        prefs: prefs,
        loadCatalog: () async {
          if (fail) throw const FormatException('bad asset');
          return catalog();
        },
      ),
    );
    expect(find.text('题库或进度读取失败，请重试'), findsOneWidget);
    fail = false;
    await tapText(tester, '重试');
    expect(find.text('每日 10 题'), findsOneWidget);
  });
  testWidgets('failed save can be cancelled or explicitly abandoned', (
    tester,
  ) async {
    store.failKey = 'flutter.${PuzzleRepository.progressKey}';
    await launch(
      tester,
      PuzzleListScreen(repository: repository, title: '练习', ids: const ['p0']),
    );
    await tester.tap(find.byKey(const ValueKey('puzzle-p0')));
    await tester.pumpAndSettle();
    await move(tester, 'd2', 'd4');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('进度尚未保存'), findsOneWidget);
    await tapText(tester, '取消');
    expect(find.byType(PuzzleSolveScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, '放弃本次结果');
    expect(find.byType(PuzzleSolveScreen), findsNothing);
    expect(repository.mistakes, isEmpty);
  });
  testWidgets(
    'result telemetry has allowed fields and no duplicate on save retry',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'puzzle-telemetry-',
      );
      final analytics = Analytics.testing(directory: directory);
      addTearDown(() async {
        analytics.dispose();
        await directory.delete(recursive: true);
      });
      await tester.runAsync(() => analytics.init(prefs));
      await launch(
        tester,
        PuzzleSolveScreen(
          repository: repository,
          ids: const ['p0'],
          analytics: analytics,
        ),
      );
      await move(tester, 'd2', 'd4');
      await tapText(tester, '再试一次');
      store.failKey = 'flutter.${PuzzleRepository.progressKey}';
      await move(tester, 'e2', 'e4');
      await move(tester, 'g1', 'f3');
      store.failKey = null;
      await tapText(tester, '重试保存');
      final events =
          File('${directory.path}${Platform.pathSeparator}pending_events.jsonl')
              .readAsLinesSync()
              .map((line) => jsonDecode(line) as Map<String, dynamic>)
              .where((event) => event['name'] == 'puzzle_result')
              .toList();
      expect(events.length, 2);
      final first = events.first['params'] as Map<String, dynamic>;
      final last = events.last['params'] as Map<String, dynamic>;
      expect(first['correct'], 0);
      expect(first['attempts'], 1);
      expect(last['correct'], 1);
      expect(last['attempts'], 2);
      expect(last['rating'], 1000);
      expect(last['duration_ms'], isNonNegative);
      expect(last.keys, isNot(contains('fen')));
      expect(last.keys, isNot(contains('line')));
      expect(last.keys, isNot(contains('id')));
    },
  );
  testWidgets('daily save failure remains on collection and can retry', (
    tester,
  ) async {
    store.failKey = 'flutter.daily_20260928';
    await launch(
      tester,
      PuzzleScreen(
        prefs: prefs,
        loadCatalog: () async => catalog(),
        now: () => DateTime(2026, 9, 28),
      ),
    );
    await tapText(tester, '每日 10 题');
    expect(find.text('每日题单读取或保存失败，请重试'), findsOneWidget);
    expect(find.byType(PuzzleListScreen), findsNothing);
    store.failKey = null;
    await tapText(tester, '每日 10 题');
    expect(find.byType(PuzzleListScreen), findsOneWidget);
  });
  testWidgets('black solver faces black and hint follows flipped coordinates', (
    tester,
  ) async {
    final black = mate(black: true);
    final blackRepository = PuzzleRepository(
      prefs: prefs,
      catalog: PuzzleCatalog([
        PuzzlePack(theme: 'mateIn1', band: 'under1200', puzzles: [black]),
      ]),
    );
    addTearDown(blackRepository.dispose);
    await launch(
      tester,
      PuzzleSolveScreen(repository: blackRepository, ids: [black.id]),
    );
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).flipped, isTrue);
    await tapText(tester, '提示思路');
    await tapText(tester, '亮起点格');
    final rect = tester.getRect(find.byType(ChessBoard));
    final hint = tester.getRect(
      find.byKey(const ValueKey('puzzle-hint-square')),
    );
    expect(hint.left, closeTo(rect.left + rect.width * 2 / 8, .01));
    expect(hint.top, closeTo(rect.top + rect.height / 8, .01));
    await move(tester, 'f2', 'f1');
    expect(blackRepository.solved, {black.id});
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets('solver layout and fixed feedback area at $size', (
      tester,
    ) async {
      await launch(tester, solver(), size: size);
      final before = tester.getRect(find.byType(ChessBoard));
      final height = tester
          .getSize(find.byKey(const ValueKey('puzzle-result-area')))
          .height;
      expect(height, 80);
      await move(tester, 'd2', 'd4');
      expect(tester.getRect(find.byType(ChessBoard)), before);
      expect(tester.takeException(), isNull);
      await tapText(tester, '再试一次');
      expect(tester.takeException(), isNull);
    });
  }
  test('named router exposes puzzle collection without changing home', () {
    final routes = AppRouter.routes(
      prefs: prefs,
      analytics: Analytics.instance,
    );
    expect(AppRouter.puzzles, '/puzzles');
    expect(routes.containsKey(AppRouter.puzzles), isTrue);
  });
}
