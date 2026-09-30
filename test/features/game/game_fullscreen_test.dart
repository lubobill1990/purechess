import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/app_theme.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/ai_game_screen.dart';
import 'package:purechess/features/game/game_rail.dart';
import 'package:purechess/features/game/game_screen.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:purechess/features/game/new_game_screen.dart';
import 'package:purechess/widgets/board/board_panel.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_game_engine.dart';

void main() {
  late SharedPreferences prefs;
  late GameSession session;
  late FakeGameEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    session = GameSession();
    engine = FakeGameEngine();
  });

  Finder key(String name) => find.byKey(ValueKey(name));
  ChessBoard board(WidgetTester tester) =>
      tester.widget<ChessBoard>(find.byType(ChessBoard));

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  Future<void> launch(
    WidgetTester tester, {
    bool ai = false,
    Size size = const Size(390, 844),
    bool dark = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: Text('测试首页')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ai
              ? AiGameScreen(
                  config: AiGameConfig(difficulty: 3),
                  rating: AiDifficulty(prefs),
                  session: session,
                  engine: engine,
                )
              : GameScreen(session: session, prefs: prefs),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> move(WidgetTester tester, String from, String to) async {
    await tester.tap(key('square-$from'), kind: PointerDeviceKind.mouse);
    await tester.tap(key('square-$to'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  for (final ai in [false, true]) {
    for (final dark in [false, true]) {
      for (final size in [
        const Size(320, 568),
        const Size(844, 390),
        const Size(800, 600),
      ]) {
        testWidgets('$ai $dark $size fullscreen rail is compact at 2x text', (
          tester,
        ) async {
          await launch(tester, ai: ai, dark: dark, size: size, scale: 2);
          expect(find.byType(AppBar), findsNothing);
          final panel = tester.getRect(find.byType(BoardPanel));
          expect(panel.top, 0);
          expect(tester.getSize(find.byType(Scaffold)), size);
          final rail = find.byType(GameRail);
          final rect = tester.getRect(rail);
          expect(rect.height, 44);
          final back = find.descendant(
            of: rail,
            matching: find.byType(BackButton),
          );
          final flip = find.byTooltip('翻转棋盘');
          final restart = find.byTooltip('新对局');
          expect(tester.getRect(back).left, rect.left);
          expect(tester.getRect(restart).right, rect.right);
          for (final action in [back, flip, restart]) {
            expect(action.hitTestable(), findsOneWidget);
            expect(tester.getRect(action).height, lessThanOrEqualTo(44));
          }
          final icon = find.descendant(of: flip, matching: find.byType(Icon));
          expect(
            IconTheme.of(tester.element(icon)).color,
            DefaultTextStyle.of(
              tester.element(find.text(ai ? '第 3 档 · 你执白棋' : '面对面对弈')),
            ).style.color,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('$ai rail flip and new game retain confirmation flow', (
      tester,
    ) async {
      await launch(tester, ai: ai);
      await move(tester, 'e2', 'e4');
      final fen = session.board.toFen();
      final rect = tester.getRect(find.byType(ChessBoard));
      await tester.tap(find.byTooltip('翻转棋盘'));
      await tester.pumpAndSettle();
      expect(board(tester).flipped, isTrue);
      expect(board(tester).board.toFen(), fen);
      expect(tester.getRect(find.byType(ChessBoard)), rect);
      await tester.tap(find.byTooltip('新对局'));
      await tester.pumpAndSettle();
      expect(find.text('开始新对局'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(board(tester).board.toFen(), fen);
      await tester.tap(find.byTooltip('新对局'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新开始'));
      await tester.pumpAndSettle();
      if (ai) {
        expect(find.byType(NewGameScreen), findsOneWidget);
        expect(engine.disposals, 1);
      } else {
        expect(board(tester).board.plyCount, 0);
      }
    });

    testWidgets('$ai rail back and system back both confirm a dirty game', (
      tester,
    ) async {
      await launch(tester, ai: ai);
      await move(tester, 'e2', 'e4');
      final fen = session.board.toFen();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('离开对局'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(board(tester).board.toFen(), fen);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('离开对局'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃并离开'));
      await tester.pumpAndSettle();
      expect(find.text('测试首页'), findsOneWidget);
      expect(find.byType(ChessBoard), findsNothing);
      if (ai) expect(engine.disposals, 1);
    });
  }

  testWidgets('local rotation preserves session, flip, draw and both actions', (
    tester,
  ) async {
    await launch(tester);
    final state = tester.state(find.byType(GameScreen));
    expect(tester.widget<RotatedBox>(key('black-player-bar')).quarterTurns, 2);
    expect(tester.widget<RotatedBox>(key('white-player-bar')).quarterTurns, 0);
    await move(tester, 'e2', 'e4');
    await tester.tap(find.byTooltip('翻转棋盘'));
    await tester.pumpAndSettle();
    await tester.tap(key('black-offer-draw'));
    await tester.pumpAndSettle();
    final fen = session.board.toFen();
    final revision = session.revision;
    await resize(tester, const Size(844, 390));
    expect(tester.state(find.byType(GameScreen)), same(state));
    expect(
      tester.widget<GameScreen>(find.byType(GameScreen)).session,
      same(session),
    );
    expect(board(tester).board.toFen(), fen);
    expect(session.revision, revision);
    expect(session.drawOffer, chess.Color.black);
    expect(board(tester).flipped, isTrue);
    expect(board(tester).flipFingerOffset, isFalse);
    for (final side in ['black', 'white']) {
      expect(
        tester.widget<RotatedBox>(key('$side-player-bar')).quarterTurns,
        0,
      );
      expect(
        tester.getRect(key('$side-player-bar')).left,
        greaterThan(tester.getRect(find.byType(ChessBoard)).right),
      );
    }
    expect(
      tester.getRect(key('black-player-bar')).top,
      lessThan(tester.getRect(key('white-player-bar')).top),
    );
    await tester.tap(key('white-decline-draw'));
    await tester.pumpAndSettle();
    expect(session.drawOffer, isNull);
    await move(tester, 'e7', 'e5');
    expect(session.moveCount, 2);
    await tester.tap(key('white-offer-draw'));
    await tester.pumpAndSettle();
    await tester.tap(key('black-decline-draw'));
    await tester.pumpAndSettle();
    await resize(tester, const Size(390, 844));
    expect(tester.state(find.byType(GameScreen)), same(state));
    expect(session.moveCount, 2);
    expect(board(tester).flipped, isTrue);
    expect(tester.widget<RotatedBox>(key('black-player-bar')).quarterTurns, 2);
    await tester.tap(key('white-undo'));
    await tester.pumpAndSettle();
    expect(session.moveCount, 1);
    expect(board(tester).flipFingerOffset, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rotating while AI thinks keeps one search and the same session',
    (tester) async {
      await launch(tester, ai: true);
      final state = tester.state(find.byType(AiGameScreen));
      final reply = Completer<PositionAnalysis>();
      engine.replies.add((_) => reply.future);
      await move(tester, 'e2', 'e4');
      expect(engine.requests.length, 1);
      await resize(tester, const Size(844, 390));
      expect(tester.state(find.byType(AiGameScreen)), same(state));
      expect(
        tester.widget<AiGameScreen>(find.byType(AiGameScreen)).session,
        same(session),
      );
      expect(session.moveCount, 1);
      expect(engine.requests.length, 1);
      expect(engine.disposals, 0);
      expect(board(tester).flipFingerOffset, isFalse);
      reply.complete(FakeGameEngine.result('e7e5'));
      await tester.pumpAndSettle();
      expect(session.moveCount, 2);
      final fen = session.board.toFen();
      await resize(tester, const Size(390, 844));
      expect(tester.state(find.byType(AiGameScreen)), same(state));
      expect(board(tester).board.toFen(), fen);
      expect(board(tester).enabled, isTrue);
      expect(engine.requests.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
