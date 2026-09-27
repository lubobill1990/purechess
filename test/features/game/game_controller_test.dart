import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/game_controller.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/fake_stockfish_transport.dart';
import '../../support/preferences_store.dart';
import 'fake_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late FakeGameEngine engine;
  final controllers = <GameController>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    engine = FakeGameEngine();
  });

  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    await engine.dispose();
  });

  GameController create({
    Color color = Color.white,
    int level = 4,
    GameSession? session,
    StockfishService? service,
    Analytics? analytics,
  }) {
    final controller = GameController(
      config: AiGameConfig(humanColor: color, difficulty: level),
      rating: AiDifficulty(prefs),
      engine: service ?? engine,
      session: session,
      analytics: analytics,
    );
    controllers.add(controller);
    return controller;
  }

  test('white waits for player, then requests selected difficulty', () async {
    final game = create(level: 7);
    await game.start();
    expect(engine.requests, isEmpty);
    await game.play(Move.fromUci('e2e4'));
    expect(engine.requests.single.difficulty, 7);
    expect(engine.requests.single.depth, isNull);
    expect(game.session.moveCount, 2);
    expect(game.humanTurn, isTrue);
    expect(game.session.snapshot().tags['Black'], 'AI');
    expect(game.session.snapshot().tags['White'], '我');
  });

  test('black starts with AI opening and cannot undo opening alone', () async {
    final game = create(color: Color.black);
    await game.start();
    expect(game.session.moveCount, 1);
    expect(game.humanTurn, isTrue);
    expect(game.canUndo, isFalse);
    await game.play(Move.fromUci('e7e5'));
    expect(game.session.moveCount, 3);
    await game.undo();
    expect(game.session.moveCount, 1);
    expect(game.session.turn, Color.black);
  });

  test(
    'hint calls analysis without playing and is cleared by a move',
    () async {
      final game = create();
      await game.start();
      await game.requestHint();
      expect(game.hint, isNotNull);
      expect(game.session.moveCount, 0);
      expect(engine.requests.single.difficulty, 10);
      expect(engine.requests.single.depth, 12);
      await game.play(Move.fromUci('e2e4'));
      expect(game.hint, isNull);
    },
  );

  test(
    'undo takes back both moves and removes abandoned PGN continuation',
    () async {
      final game = create();
      await game.play(Move.fromUci('e2e4'));
      await game.undo();
      expect(game.session.moveCount, 0);
      expect(game.session.snapshot().mainLine, hasLength(1));
      await game.play(Move.fromUci('d2d4'));
      expect(game.session.snapshot().mainLine[1].move!.uci, 'd2d4');
    },
  );

  test('undo during thinking ignores a late reply', () async {
    final gate = Completer<PositionAnalysis>();
    engine.replies.add((_) => gate.future);
    final game = create();
    final pending = game.play(Move.fromUci('e2e4'));
    expect(game.phase, GamePhase.thinking);
    expect(game.humanTurn, isFalse);
    await game.undo();
    gate.complete(FakeGameEngine.result('e7e5'));
    await pending;
    expect(game.session.moveCount, 0);
    expect(game.phase, GamePhase.playing);
  });

  test('undo during hint invalidates hint result', () async {
    final game = create();
    await game.play(Move.fromUci('e2e4'));
    final gate = Completer<PositionAnalysis>();
    engine.replies.add((_) => gate.future);
    final pending = game.requestHint();
    await game.undo();
    gate.complete(FakeGameEngine.result('d2d4'));
    await pending;
    expect(game.hint, isNull);
    expect(game.session.moveCount, 0);
  });

  test('resign while thinking cancels reply and records loss once', () async {
    final gate = Completer<PositionAnalysis>();
    engine.replies.add((_) => gate.future);
    final game = create(level: 6);
    final pending = game.play(Move.fromUci('e2e4'));
    await game.resign();
    gate.complete(FakeGameEngine.result('e7e5'));
    await pending;
    expect(game.session.outcome!.winner, Color.black);
    expect(game.session.moveCount, 1);
    expect(game.phase, GamePhase.finished);
    expect(AiDifficulty(prefs).recommended, 5);
    expect(game.canUndo, isFalse);
    await prefs.setInt(AiDifficulty.preferenceKey, 9);
    await game.saveRating();
    expect(AiDifficulty(prefs).recommended, 9);
  });

  test('AI exception is visible and retry resumes same position', () async {
    engine.replies.add(
      (_) async => throw const StockfishException('AI 启动失败，请重试'),
    );
    final game = create(color: Color.black);
    await game.start();
    expect(game.error, 'AI 启动失败，请重试');
    expect(game.phase, GamePhase.failed);
    expect(game.session.moveCount, 0);
    await game.retry();
    expect(game.error, isNull);
    expect(game.session.moveCount, 1);
    expect(engine.requests[0].fen, engine.requests[1].fen);
  });

  test('illegal AI response is surfaced instead of played', () async {
    engine.replies.add((_) async => FakeGameEngine.result('a1a8'));
    final game = create(color: Color.black);
    await game.start();
    expect(game.error, isNotNull);
    expect(game.session.moveCount, 0);
  });

  test('idle failures block player and retry actually restarts AI', () async {
    final game = create();
    await game.start();
    engine.failIdle();
    expect(game.humanTurn, isFalse);
    expect(game.error, contains('意外退出'));
    await game.retry();
    expect(engine.starts, 1);
    expect(game.humanTurn, isTrue);
  });

  test('failed stop preserves board and shows an error', () async {
    final game = create();
    await game.play(Move.fromUci('e2e4'));
    final fen = game.session.board.toFen();
    engine.stopError = StateError('stop failure');
    await game.undo();
    expect(game.error, contains('未能停止'));
    expect(game.session.board.toFen(), fen);
  });

  test('disposal invalidates pending result without notifying', () async {
    final gate = Completer<PositionAnalysis>();
    engine.replies.add((_) => gate.future);
    final game = create(color: Color.black);
    final pending = game.start();
    game.dispose();
    controllers.remove(game);
    gate.complete(FakeGameEngine.result('e2e4'));
    await pending;
    expect(game.session.moveCount, 0);
  });

  test('human mate raises recommendation and needs no AI search', () async {
    final session = GameSession(initialFen: '7k/5Q2/6K1/8/8/8/8/8 w - - 0 1');
    final game = create(session: session, level: 4);
    await game.play(session.board.parseSan('Qg7#'));
    expect(game.session.finished, isTrue);
    expect(engine.requests, isEmpty);
    expect(AiDifficulty(prefs).recommended, 5);
  });

  test('automatic draw preserves selected level', () async {
    final session = GameSession(initialFen: '7k/8/6K1/8/8/8/8/8 w - - 0 1');
    final game = create(session: session, level: 6);
    await game.start();
    expect(game.phase, GamePhase.finished);
    expect(AiDifficulty(prefs).recommended, 6);
  });

  test('recommendation write failure can be explicitly retried', () async {
    final store = FailingPreferencesStore()
      ..failKey = 'flutter.${AiDifficulty.preferenceKey}';
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    final game = create(level: 7);
    await game.resign();
    expect(game.ratingError, contains('未保存'));
    expect(game.ratingSaving, isFalse);
    store.failKey = null;
    await game.saveRating();
    expect(game.ratingError, isNull);
    expect(
      store.getAll(),
      completion(containsPair('flutter.${AiDifficulty.preferenceKey}', 6)),
    );
  });

  test(
    'game AI uses real service sentinels and safe start/end events',
    () async {
      final dir = await Directory.systemTemp.createTemp('chess_game_test_');
      final analytics = Analytics.testing(directory: dir);
      await analytics.prepare(prefs);
      final transport = FakeStockfishTransport()..analysis = false;
      final service = StockfishService(
        transportFactory: () => transport,
        analytics: analytics,
        prefs: prefs,
      );
      final game = create(
        color: Color.black,
        service: service,
        analytics: analytics,
      );
      final pending = game.start();
      final phase = File('${dir.path}${Platform.pathSeparator}phase.txt');
      expect(phase.readAsStringSync(), 'chess_engine_start');
      for (
        var i = 0;
        i < 100 && !transport.commands.any((c) => c.startsWith('go '));
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(phase.readAsStringSync(), 'chess_engine_analyze');
      transport.output.add('info depth 8 score cp 24 pv e2e4');
      transport.output.add('bestmove e2e4');
      await pending;
      expect(phase.existsSync(), isFalse);
      await game.resign();
      final events = File(
        '${dir.path}${Platform.pathSeparator}pending_events.jsonl',
      ).readAsLinesSync().map((line) => jsonDecode(line) as Map);
      expect(events.where((e) => e['name'] == 'game_start'), hasLength(1));
      expect(events.where((e) => e['name'] == 'game_end'), hasLength(1));
      game.dispose();
      controllers.remove(game);
      await service.dispose();
      analytics.dispose();
      await dir.delete(recursive: true);
    },
  );

  for (var level = 1; level <= 10; level++) {
    test('difficulty $level adapts wins/losses/draws within bounds', () {
      expect(nextDifficulty(level, won: true), (level + 1).clamp(1, 10));
      expect(nextDifficulty(level, won: false), (level - 1).clamp(1, 10));
      expect(nextDifficulty(level, won: null), level);
    });
  }

  test('invalid difficulty is rejected and default is beginner', () {
    expect(() => AiGameConfig(difficulty: 0), throwsRangeError);
    expect(() => nextDifficulty(11, won: true), throwsRangeError);
    expect(AiDifficulty(prefs).recommended, 1);
  });
}
