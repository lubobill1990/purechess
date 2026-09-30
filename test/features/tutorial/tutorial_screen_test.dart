import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/router.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/features/tutorial/tutorial_controller.dart';
import 'package:purechess/features/tutorial/tutorial_engine.dart';
import 'package:purechess/features/tutorial/tutorial_level.dart';
import 'package:purechess/features/tutorial/tutorial_screen.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';

class UnavailableEngine extends FakeEngine {
  @override
  Future<chess.Move> chooseMove(Board board) async =>
      throw StateError('AI unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late TutorialCatalog catalog;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    catalog = await TutorialCatalog.load();
  });

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> settleAssets(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(TutorialCatalog.load);
    await tester.pumpAndSettle();
  }

  Future<void> move(WidgetTester tester, String from, String to) async {
    await tester.tap(key('square-$from'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(key('square-$to'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  Future<TutorialController> lesson(
    WidgetTester tester,
    int index, {
    Size? size,
    double textScale = 1,
    TutorialEngine? engine,
  }) async {
    if (size != null) {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await prefs.setInt(TutorialController.progressKey, index);
    final c = TutorialController(
      catalog: catalog,
      prefs: prefs,
      engine: engine ?? FakeEngine(random: Random(42)),
    )..start(index);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        routes: {tutorialDailyRoute: (_) => const TutorialDailyScreen()},
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: TutorialPlayScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('named route loads assets and locks later lessons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: AppRouter.tutorial,
        routes: AppRouter.routes(prefs: prefs, analytics: Analytics.instance),
      ),
    );
    await settleAssets(tester);
    expect(find.text('新手互动教程'), findsOneWidget);
    expect(tester.widget<ListTile>(key('tutorial-level-0')).enabled, isTrue);
    expect(tester.widget<ListTile>(key('tutorial-level-1')).onTap, isNull);
    await tester.tap(key('tutorial-level-0'));
    await tester.pumpAndSettle();
    expect(find.byType(ChessBoard), findsOneWidget);
    await move(tester, 'd4', 'e4');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(key('tutorial-level-1')).enabled, isTrue);
    expect(find.textContaining('已完成 1 / 19'), findsOneWidget);
  });

  testWidgets('load failures are visible and retry can recover', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialScreen(
          prefs: prefs,
          createEngine: FakeEngine.new,
          loadCatalog: () async {
            if (loads++ == 0) throw const FormatException('Missing asset');
            return catalog;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('教程加载失败'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(key('tutorial-level-0'), findsOneWidget);
    expect(loads, 2);
  });

  testWidgets('intro wrong feedback success and next preserve fixed geometry', (
    tester,
  ) async {
    final c = await lesson(tester, 0, size: const Size(390, 844));
    final initial = tester.getRect(find.byType(ChessBoard));
    expect(tester.getSize(key('tutorial-explanation')).height, 156);
    expect(find.bySemanticsLabel('目标 e4'), findsOneWidget);
    await move(tester, 'd4', 'd5');
    expect(find.text(c.level.failure), findsOneWidget);
    expect(tester.getRect(find.byType(ChessBoard)), initial);
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isFalse);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await move(tester, 'd4', 'e4');
    expect(find.text(c.level.success), findsOneWidget);
    expect(tester.getRect(find.byType(ChessBoard)), initial);
    await tester.tap(find.text('下一关'));
    await tester.pumpAndSettle();
    expect(c.index, 1);
    expect(tester.getRect(find.byType(ChessBoard)), initial);
  });

  testWidgets('practice hides solution until hint requested', (tester) async {
    await lesson(tester, 12);
    expect(find.bySemanticsLabel('目标 d8'), findsNothing);
    await tester.tap(find.text('提示'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('目标 d8'), findsOneWidget);
    await move(tester, 'd1', 'd8');
    expect(find.text('下一关'), findsOneWidget);
  });

  testWidgets(
    'promotion needs queen selection and cancellation changes nothing',
    (tester) async {
      final c = await lesson(tester, 15);
      final fen = c.board.toFen();
      await move(tester, 'a7', 'a8');
      expect(find.text('选择升变棋子'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(c.board.toFen(), fen);
      expect(c.solved, isFalse);
      // Cancellation leaves the pawn selected in the shared board.
      await tester.tap(key('square-a8'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(key('promotion-queen'));
      await tester.pumpAndSettle();
      expect(c.solved, isTrue);
      expect(
        c.board.pieceAt(chess.parseSquare('a8'))?.type,
        chess.PieceType.queen,
      );
    },
  );

  testWidgets('save failure shows retry and never advances prematurely', (
    tester,
  ) async {
    final store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    await prefs.reload();
    final c = await lesson(tester, 0);
    store.failKey = 'flutter.tutorial_progress';
    await move(tester, 'd4', 'e4');
    expect(c.solved, isTrue);
    expect(find.text('下一关'), findsNothing);
    expect(find.text('重新保存'), findsOneWidget);
    expect(find.textContaining('进度保存失败'), findsOneWidget);
    store.failKey = null;
    await tester.tap(find.text('重新保存'));
    await tester.pumpAndSettle();
    expect(find.text('下一关'), findsOneWidget);
  });

  testWidgets(
    'graduation confirmation and CTA reach functional daily practice',
    (tester) async {
      final c = await lesson(tester, 18, size: const Size(390, 844));
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '认输结束'))
            .onPressed,
        isNull,
      );
      await move(tester, 'e2', 'e4');
      expect(c.board.plyCount, 2);
      await tester.tap(find.text('认输结束'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续下棋'));
      await tester.pumpAndSettle();
      expect(c.solved, isFalse);
      await tester.tap(find.text('认输结束'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认认输'));
      await tester.pumpAndSettle();
      expect(c.completed, 19);
      await tester.tap(find.text('去每日战术题'));
      await settleAssets(tester);
      expect(find.text('每日战术题 · 入门练习'), findsOneWidget);
      expect(find.byType(ChessBoard), findsOneWidget);
      final board = tester.widget<ChessBoard>(find.byType(ChessBoard)).board;
      if (board.pieceAt(chess.parseSquare('d1')) != null) {
        await move(tester, 'd1', 'd8');
      } else {
        await move(tester, 'g6', 'g7');
      }
      expect(find.textContaining('今天的入门练习已完成'), findsOneWidget);
    },
  );

  testWidgets(
    'completed list offers daily route without replaying graduation',
    (tester) async {
      await prefs.setInt(TutorialController.progressKey, 19);
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: AppRouter.tutorial,
          routes: AppRouter.routes(prefs: prefs, analytics: Analytics.instance),
        ),
      );
      await settleAssets(tester);
      await tester.tap(find.text('去每日战术题'));
      await settleAssets(tester);
      expect(find.text('每日战术题 · 入门练习'), findsOneWidget);
    },
  );

  testWidgets('fallback notice is visible above the graduation explanation', (
    tester,
  ) async {
    final c = await lesson(
      tester,
      18,
      size: const Size(390, 844),
      engine: UnavailableEngine(),
    );
    final initialBoard = tester.getRect(find.byType(ChessBoard));
    await move(tester, 'e2', 'e4');
    expect(c.fallback, isTrue);
    final notice = find.text(c.aiNotice!);
    expect(notice, findsOneWidget);
    expect(
      tester.getRect(notice).bottom,
      lessThanOrEqualTo(tester.getRect(key('tutorial-explanation')).bottom),
    );
    expect(tester.getRect(find.byType(ChessBoard)), initialBoard);
    expect(c.board.plyCount, 2);
    c.start(0);
    await tester.pumpAndSettle();
    expect(find.text(c.aiNotice!), findsNothing);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets(
      'lesson fits ${size.width}x${size.height} at large text scale',
      (tester) async {
        await lesson(tester, 14, size: size, textScale: 1.5);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(key('tutorial-explanation')).height, 156);
        final rect = tester.getRect(find.byType(ChessBoard));
        expect(rect.width, greaterThan(0));
        expect(rect.width, rect.height);
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        await move(tester, 'e1', 'g1');
        expect(tester.takeException(), isNull);
        expect(find.text('下一关'), findsOneWidget);
        expect(tester.getRect(find.byType(ChessBoard)), rect);
      },
    );
  }
}
