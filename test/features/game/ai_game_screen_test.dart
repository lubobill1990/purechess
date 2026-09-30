import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/core/pgn.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/ai_game_screen.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:purechess/features/game/game_persistence.dart';
import 'package:purechess/features/game/new_game_screen.dart';
import 'package:purechess/features/game/review_screen.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/memory_records_repository.dart';
import 'fake_game_engine.dart';

class SlowClosingEngine extends FakeGameEngine {
  final closing = Completer<void>();

  @override
  Future<void> dispose() async {
    await closing.future;
    await super.dispose();
  }
}

void main() {
  late SharedPreferences prefs;
  late FakeGameEngine engine;
  late MemoryRecordsRepository repository;
  late GameSession session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    engine = FakeGameEngine();
    repository = MemoryRecordsRepository();
    session = GameSession();
  });

  Future<void> launch(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: AiGameScreen(
          config: AiGameConfig(difficulty: 5),
          rating: AiDifficulty(prefs),
          engine: engine,
          session: session,
          openRepository: () async => repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> move(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('square-e2')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.tap(
      find.byKey(const ValueKey('square-e4')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hint is visible without moving, pair undo restores board', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('提示'));
    await tester.pumpAndSettle();
    expect(find.textContaining('建议'), findsOneWidget);
    expect(session.moveCount, 0);
    await move(tester);
    expect(session.moveCount, 2);
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(session.moveCount, 0);
    expect(find.textContaining('建议'), findsNothing);
  });

  testWidgets(
    'autosaves each side, hints and undo; resignation clears the slot',
    (tester) async {
      await launch(tester);
      await tester.tap(find.text('提示'));
      await tester.pumpAndSettle();
      SavedGame saved() =>
          SavedGame.decode(prefs.getString(GameStore.preferenceKey)!);
      expect(saved().session.hintsUsed, 1);
      final gate = Completer<PositionAnalysis>();
      engine.replies.add((_) => gate.future);
      await tester.tap(
        find.byKey(const ValueKey('square-e2')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.tap(
        find.byKey(const ValueKey('square-e4')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(saved().session.moveCount, 1);
      gate.complete(FakeGameEngine.result('e7e5'));
      await tester.pumpAndSettle();
      expect(saved().session.moveCount, 2);
      await tester.tap(find.text('悔棋'));
      await tester.pumpAndSettle();
      expect(saved().session.moveCount, 0);
      expect(saved().session.hintsUsed, 1);
      await tester.tap(find.text('认输'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认认输'));
      await tester.pumpAndSettle();
      expect(prefs.containsKey(GameStore.preferenceKey), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(prefs.containsKey(GameStore.preferenceKey), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  testWidgets('resumed AI turn searches the restored FEN and continues once', (
    tester,
  ) async {
    session.play(chess.Move.fromUci('e2e4'));
    session.hintsUsed = 2;
    final store = GameStore(prefs);
    addTearDown(store.dispose);
    await store.save(session, config: AiGameConfig(difficulty: 7));
    final saved = store.restore()!;
    final fen = saved.session.board.toFen();
    engine.replies.add((_) async => FakeGameEngine.result('e7e5'));
    await tester.pumpWidget(
      MaterialApp(
        home: AiGameScreen(
          config: saved.config!,
          session: saved.session,
          rating: AiDifficulty(prefs),
          engine: engine,
          gameStore: store,
          resumed: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(engine.requests.single.fen, fen);
    expect(engine.requests.single.difficulty, 7);
    expect(saved.session.moveCount, 2);
    expect(store.restore()!.session.hintsUsed, 2);
    expect(store.restore()!.session.board.toFen(), saved.session.board.toFen());
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isTrue);
  });

  testWidgets('AI screen lifecycle persists metadata not changed by a move', (
    tester,
  ) async {
    await launch(tester);
    session.hintsUsed = 4;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(
      SavedGame.decode(prefs.getString(GameStore.preferenceKey)!)
          .session
          .hintsUsed,
      4,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('late AI result after discard cannot recreate the save', (
    tester,
  ) async {
    await launch(tester);
    final gate = Completer<PositionAnalysis>();
    engine.replies.add((_) => gate.future);
    await tester.tap(
      find.byKey(const ValueKey('square-e2')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.tap(
      find.byKey(const ValueKey('square-e4')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新对局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新开始'));
    await tester.pumpAndSettle();
    expect(find.byType(NewGameScreen), findsOneWidget);
    gate.complete(FakeGameEngine.result('e7e5'));
    await tester.pumpAndSettle();
    expect(prefs.containsKey(GameStore.preferenceKey), isFalse);
  });

  for (final exit in ['resume', 'abandon', 'saved', 'empty']) {
    testWidgets('$exit waits for AI shutdown before returning home', (
      tester,
    ) async {
      final slow = SlowClosingEngine();
      final reply = Completer<PositionAnalysis>();
      slow.replies.add((_) => reply.future);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('测试首页')),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => AiGameScreen(
              config: AiGameConfig(),
              rating: AiDifficulty(prefs),
              engine: slow,
              session: session,
              openRepository: () async => repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (exit != 'empty') {
        await move(tester);
        if (exit == 'saved') {
          await tester.tap(find.text('保存棋谱'));
          await tester.pumpAndSettle();
        }
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      if (exit == 'resume' || exit == 'abandon') {
        await tester.tap(find.text(exit == 'resume' ? '稍后继续' : '放弃并离开'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(AiGameScreen), findsOneWidget);
      expect(find.text('测试首页'), findsNothing);
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled,
        isFalse,
      );
      reply.complete(FakeGameEngine.result('e7e5'));
      await tester.pumpAndSettle();
      expect(session.moveCount, exit == 'empty' ? 0 : 1);
      slow.closing.complete();
      await tester.pumpAndSettle();
      expect(find.text('测试首页'), findsOneWidget);
      expect(slow.disposals, 1);
      expect(prefs.containsKey(GameStore.preferenceKey), exit != 'abandon');
      if (exit != 'abandon') {
        expect(
          SavedGame.decode(prefs.getString(GameStore.preferenceKey)!)
              .session
              .moveCount,
          session.moveCount,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rematch preserves current config rather than adaptive level', (
    tester,
  ) async {
    await launch(tester);
    final boardRect = tester.getRect(find.byType(ChessBoard));
    await tester.tap(find.text('认输'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认认输'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ChessBoard)), boardRect);
    expect(AiDifficulty(prefs).recommended, 4);
    await tester.tap(find.byTooltip('再来一局'));
    await tester.pumpAndSettle();
    expect(find.byType(NewGameScreen), findsNothing);
    final next = tester.widget<AiGameScreen>(find.byType(AiGameScreen));
    expect(next.config.difficulty, 5);
    expect(next.config.humanColor, chess.Color.white);
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).board.plyCount,
      0,
    );
    expect(engine.disposals, 1);
  });

  testWidgets(
    'search blocks board and error/retry are visible in fixed result area',
    (tester) async {
      await launch(tester);
      final before = tester.getRect(find.byType(ChessBoard));
      final gate = Completer<PositionAnalysis>();
      engine.replies.add((_) => gate.future);
      await tester.tap(
        find.byKey(const ValueKey('square-e2')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.tap(
        find.byKey(const ValueKey('square-e4')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled,
        isFalse,
      );
      gate.completeError(const StockfishException('AI 分析失败，请重试'));
      await tester.pumpAndSettle();
      expect(find.text('AI 分析失败，请重试'), findsOneWidget);
      expect(tester.getRect(find.byType(ChessBoard)), before);
      expect(
        tester.getSize(find.byKey(const ValueKey('ai-result-area'))).height,
        72,
      );
      await tester.ensureVisible(find.text('重试 AI'));
      await tester.tap(find.text('重试 AI'));
      await tester.pumpAndSettle();
      expect(session.moveCount, 2);
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled,
        isTrue,
      );
    },
  );

  testWidgets('idle failure is visible without pressing another button', (
    tester,
  ) async {
    await launch(tester);
    engine.failIdle();
    await tester.pumpAndSettle();
    expect(find.text('AI 意外退出，请重试'), findsOneWidget);
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isFalse);
  });

  testWidgets(
    'resign confirms, updates recommendation and opens review in one tap',
    (tester) async {
      await launch(tester);
      await move(tester);
      await tester.tap(find.text('认输'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(session.finished, isFalse);
      await tester.tap(find.text('认输'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认认输'));
      await tester.pumpAndSettle();
      expect(session.finished, isTrue);
      expect(find.text('下局推荐第 4 档'), findsOneWidget);
      await tester.tap(find.text('一键复盘'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('逐手分析 · 3 / 3'), findsOneWidget);
    },
  );

  testWidgets(
    'save failure can retry and new game requires discard confirmation',
    (tester) async {
      await launch(tester);
      await move(tester);
      repository.failSave = true;
      await tester.tap(find.text('保存棋谱'));
      await tester.pumpAndSettle();
      expect(find.textContaining('棋谱保存失败'), findsOneWidget);
      await tester.tap(find.byTooltip('新对局'));
      await tester.pumpAndSettle();
      expect(find.text('重新开始'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      repository.failSave = false;
      await tester.tap(find.text('保存棋谱'));
      await tester.pumpAndSettle();
      expect(repository.saved.single.mainLine.length, 3);
      await tester.tap(find.byTooltip('新对局'));
      await tester.pumpAndSettle();
      expect(find.byType(NewGameScreen), findsOneWidget);
      expect(engine.disposals, 1);
    },
  );

  testWidgets('review mistake tap selects exact resulting position', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 1366));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = Pgn.parse('1. e4 e5 2. Nf3 Nc6 1-0');
    for (final value in [500, -400, 600, -300, 500]) {
      engine.replies.add((_) async => FakeGameEngine.result('e2e4', cp: value));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(record: record, engine: engine),
      ),
    );
    await tester.pumpAndSettle();
    final mistakes = find.byType(ListTile);
    expect(mistakes, findsNWidgets(3));
    final target = find.byKey(const ValueKey('review-mistake-3'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).board.toFen(),
      record.boardAt(record.mainLine[3]).toFen(),
    );
    final chart = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('review-loss-chart')),
    );
    expect((chart.painter! as LossChartPainter).selectedPly, 3);
    expect((chart.painter! as LossChartPainter).losses, [100, 200, 300, 200]);
  });

  testWidgets(
    'review failure shows progress and retry, without losing completed scores',
    (tester) async {
      engine.replies.add((_) async => FakeGameEngine.result('e2e4'));
      engine.replies.add(
        (_) async => throw const StockfishException('AI 暂时不可用，请重试'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewScreen(record: Pgn.parse('1. e4 *'), engine: engine),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('逐手分析 · 1 / 2'), findsOneWidget);
      expect(find.text('AI 暂时不可用，请重试'), findsOneWidget);
      await tester.tap(find.text('继续分析'));
      await tester.pumpAndSettle();
      expect(find.text('逐手分析 · 2 / 2'), findsOneWidget);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets('AI game fits $size with scrollable controls', (tester) async {
      await launch(tester, size: size);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('认输'));
      await tester.tap(find.text('认输'));
      await tester.pumpAndSettle();
      expect(find.text('确认认输'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('new game CTA stays at bottom when $size form scrolls', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await prefs.setInt(AiDifficulty.preferenceKey, 6);
      await tester.pumpWidget(MaterialApp(home: NewGameScreen(prefs: prefs)));
      await tester.pumpAndSettle();
      final cta = find.byKey(const ValueKey('start-ai-game'));
      final before = tester.getRect(cta);
      expect(before.bottom, lessThanOrEqualTo(size.height - 16));
      expect(before.bottom, greaterThan(size.height - 40));
      expect(find.text('难度 · 6 / 10'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).divisions, 9);
      expect(tester.getRect(cta), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('form selection reaches actual game configuration', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: NewGameScreen(prefs: prefs)));
    await tester.pumpAndSettle();
    // White does not start the native AI until a move or hint is requested.
    tester.widget<Slider>(find.byType(Slider)).onChanged!(9);
    await tester.pump();
    await tester.tap(find.text('开始对弈'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AiGameScreen>(find.byType(AiGameScreen)).config.difficulty,
      9,
    );
  });

  testWidgets('black orientation and AI opening are wired into the screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiGameScreen(
          config: AiGameConfig(humanColor: chess.Color.black),
          rating: AiDifficulty(prefs),
          engine: engine,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board.flipped, isTrue);
    expect(board.board.turn, chess.Color.black);
    expect(board.enabled, isTrue);
    expect(engine.requests.length, 1);
  });

  testWidgets('leaving a pending review stops AI before returning to game', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final gate = Completer<PositionAnalysis>();
    engine.replies.add((_) => gate.future);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('返回对弈')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReviewScreen(record: Pgn.parse('1. e4 *'), engine: engine),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('返回对弈'), findsOneWidget);
    expect(engine.stops, greaterThan(0));
    gate.complete(FakeGameEngine.result('e2e4'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone mistake jump brings selected board back into view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = Pgn.parse('1. e4 e5 2. Nf3 Nc6 *');
    for (final value in [500, -400, 600, -300, 500]) {
      engine.replies.add((_) async => FakeGameEngine.result('e2e4', cp: value));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(record: record, engine: engine),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('review-mistake-3'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    final board = find.byType(ChessBoard);
    expect(tester.getRect(board).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(board).bottom, lessThan(844));
    expect(
      tester.widget<ChessBoard>(board).board.toFen(),
      record.boardAt(record.mainLine[3]).toFen(),
    );
  });

  testWidgets('large text preserves form CTA and AI controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: NewGameScreen(prefs: prefs),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('开始对弈')).bottom, lessThan(568));
    expect(tester.takeException(), isNull);
  });
}
