import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    testWidgets('$ai safe insets keep landscape navigation clear of content', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(
        left: 24,
        top: 12,
        bottom: 10,
      );
      addTearDown(tester.view.resetPadding);
      await launch(tester, ai: ai, size: const Size(844, 390));
      expect(tester.getTopLeft(find.byType(GameRail)), const Offset(34, 22));
      expect(tester.getSize(find.byType(GameRail)), const Size(44, 44));
      expect(find.byType(Scrollable), findsNothing);
      await tester.tap(find.byTooltip('对局菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('翻转棋盘'));
      await tester.pumpAndSettle();
      expect(board(tester).flipped, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$ai immersive restores on push, pop, replacement and disposal',
      (tester) async {
        final modes = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
              modes.add(call.arguments as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await launch(tester, ai: ai);
        expect(modes.last, 'SystemUiMode.immersiveSticky');
        final navigator = Navigator.of(tester.element(find.byType(GameRail)));
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('另一页')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(modes.last, 'SystemUiMode.edgeToEdge');
        navigator.pop();
        await tester.pumpAndSettle();
        expect(modes.last, 'SystemUiMode.immersiveSticky');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(modes.last, 'SystemUiMode.immersiveSticky');
        unawaited(
          navigator.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('替换页')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(modes.last, 'SystemUiMode.edgeToEdge');
        await tester.pumpWidget(const SizedBox.shrink());
        expect(modes.last, 'SystemUiMode.edgeToEdge');
      },
    );

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
          expect(find.byType(Scrollable), findsNothing);
          if (size.width > size.height) {
            expect(rect.topLeft, const Offset(10, 10));
            final boardRect = tester.getRect(find.byType(ChessBoard));
            expect(rect.right, lessThan(boardRect.left));
            for (final side in ['black', 'white']) {
              if (!ai) {
                expect(
                  rect.overlaps(tester.getRect(key('$side-player-bar'))),
                  isFalse,
                );
              }
            }
            await tester.tap(find.byTooltip('对局菜单'));
            await tester.pumpAndSettle();
            for (final label in ['返回', '翻转棋盘', '新对局', '保存棋谱']) {
              expect(find.text(label).hitTestable(), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
            return;
          }
          final back = find.descendant(
            of: rail,
            matching: find.byType(BackButton),
          );
          final flip = find.byTooltip('翻转棋盘');
          final restart = find.byTooltip('新对局');
          expect(tester.getRect(back).left, rect.left);
          expect(tester.getRect(restart).right, lessThanOrEqualTo(rect.right));
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

    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets(
        'symmetric turn chips and draw response stay fixed at $size',
        (tester) async {
          await launch(tester, size: size, scale: 2);
          final rect = tester.getRect(find.byType(ChessBoard));
          Color highlight(String side) =>
              tester.widget<ColoredBox>(key('$side-turn-highlight')).color;
          expect(highlight('white'), BoardPainter.lastMoveTint);
          expect(highlight('black'), Colors.transparent);
          expect(find.text('白方\n轮到你'), findsOneWidget);
          final buttonContext = tester.element(key('black-resign'));
          final disabled = OutlinedButtonTheme.of(buttonContext).style!;
          expect(
            disabled.side!.resolve({WidgetState.disabled}),
            BorderSide.none,
          );
          expect(disabled.side!.resolve({})!.width, greaterThan(0));
          expect(
            disabled.foregroundColor!.resolve({WidgetState.disabled})!.a,
            lessThan(disabled.foregroundColor!.resolve({})!.a),
          );
          await move(tester, 'e2', 'e4');
          expect(highlight('black'), BoardPainter.lastMoveTint);
          expect(highlight('white'), Colors.transparent);
          expect(find.text('黑方\n轮到你'), findsOneWidget);
          expect(tester.getRect(find.byType(ChessBoard)), rect);
          await tester.tap(key('black-offer-draw'));
          await tester.pumpAndSettle();
          expect(key('white-decline-draw').hitTestable(), findsOneWidget);
          expect(key('white-accept-draw').hitTestable(), findsOneWidget);
          expect(tester.getRect(find.byType(ChessBoard)), rect);
          await tester.tap(key('white-decline-draw'));
          await tester.pumpAndSettle();
          expect(find.byType(Scrollable), findsNothing);
          expect(tester.getRect(find.byType(ChessBoard)), rect);
          expect(tester.takeException(), isNull);
        },
      );
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
    // Symmetric landscape: upright panes, black left of the centered board
    // and white right of it (players sit on either side, same text
    // direction for both).
    final boardRect = tester.getRect(find.byType(ChessBoard));
    expect(boardRect.center.dx, closeTo(844 / 2, .001));
    expect(
      tester.getRect(key('black-player-bar')).right,
      lessThan(boardRect.left),
    );
    expect(
      tester.getRect(key('white-player-bar')).left,
      greaterThan(boardRect.right),
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
