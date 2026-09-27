import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/game_tree.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/features/game/review_controller.dart';

import 'fake_game_engine.dart';

void main() {
  List<ReviewEvaluation?> cp(List<int?> values) => [
    for (final value in values)
      value == null ? null : ReviewEvaluation(whiteCp: value),
  ];

  test('losses use mover perspective and clamp improvements to zero', () {
    expect(reviewLosses(cp([100, 0, 200, 300, 100])), [100, 200, 0, 0]);
    expect(reviewLosses(cp([100, 0, 200]), initialTurn: Color.black), [0, 0]);
  });

  test('top three positive losses sorted descending, ties by earliest ply', () {
    final mistakes = selectReviewMistakes(cp([500, 400, 600, 300, 500, 0]));
    expect(mistakes.map((m) => m.ply), [5, 3, 2]);
    expect(mistakes.map((m) => m.loss), [500, 300, 200]);
    expect(() => mistakes.clear(), throwsUnsupportedError);
  });

  test('missing positions never bridge an unanalysed move', () {
    final values = cp([100, null, -500, -600]);
    expect(reviewLosses(values), [null, null, 100]);
    expect(selectReviewMistakes(values).single.ply, 3);
  });

  test('mate transitions are gaps, not fabricated centipawn losses', () {
    final values = [
      const ReviewEvaluation(whiteCp: 300),
      const ReviewEvaluation(whiteMate: 3),
      const ReviewEvaluation(whiteMate: -2),
      const ReviewEvaluation(whiteCp: -300),
      const ReviewEvaluation(whiteCp: -100),
    ];
    expect(reviewLosses(values), [null, null, null, 200]);
    expect(selectReviewMistakes(values).single.ply, 4);
  });

  test('empty, one-position and no-positive-loss reviews have no mistakes', () {
    for (final values in [
      <int?>[],
      [0],
      [0, 0, 0],
      [0, 100, -100],
    ]) {
      expect(selectReviewMistakes(cp(values)), isEmpty);
    }
  });

  test('black-to-move initial FEN inverts attribution', () {
    final mistakes = selectReviewMistakes(
      cp([0, 200, -100]),
      initialTurn: Color.black,
    );
    expect(mistakes.map((m) => m.ply), [2, 1]);
    expect(mistakes.map((m) => m.loss), [300, 200]);
  });

  test('score normalization preserves signed mate and white perspective', () {
    expect(
      ReviewEvaluation.fromAnalysis(
        FakeGameEngine.result('e7e5', cp: 40),
        Color.black,
      ).whiteCp,
      -40,
    );
    expect(
      ReviewEvaluation.fromAnalysis(
        FakeGameEngine.result('e7e5', mate: -3),
        Color.black,
      ).whiteMate,
      3,
    );
    expect(
      ReviewEvaluation.fromAnalysis(
        FakeGameEngine.result(null, mate: 0),
        Color.black,
      ).whiteMate,
      0,
    );
  });

  late FakeGameEngine engine;
  late ReviewController review;
  setUp(() {
    engine = FakeGameEngine();
    review = ReviewController(
      record: Pgn.parse('1. e4 e5 2. Nf3 Nc6 *'),
      engine: engine,
    );
  });
  tearDown(() async {
    review.dispose();
    await engine.dispose();
  });

  test('analyses every position including zero without sampling', () async {
    final original = Pgn.generate(review.record);
    await review.run();
    expect(engine.requests, hasLength(5));
    expect(review.completed, 5);
    expect(review.running, isFalse);
    expect(
      engine.requests.every((r) => r.difficulty == 10 && r.depth == 12),
      isTrue,
    );
    expect(Pgn.generate(review.record), original);
    review.select(3);
    expect(review.board.lastMove!.uci, 'g1f3');
    expect(() => review.select(5), throwsRangeError);
  });

  test(
    'failure keeps partial analysis and retry resumes only missing positions',
    () async {
      engine.replies.add((_) async => FakeGameEngine.result('e2e4', cp: 50));
      engine.replies.add(
        (_) async => throw const StockfishException('AI 分析失败，请重试'),
      );
      await review.run();
      expect(review.completed, 1);
      expect(review.error, contains('分析失败'));
      expect(review.evaluations.skip(1).every((v) => v == null), isTrue);
      await review.run();
      expect(review.completed, 5);
      expect(engine.requests, hasLength(6));
      expect(review.error, isNull);
    },
  );

  test('cancel ignores old result and allows complete retry', () async {
    final gate = Completer<PositionAnalysis>();
    engine.replies.add((_) => gate.future);
    final pending = review.run();
    await review.cancel();
    gate.complete(FakeGameEngine.result('e2e4'));
    await pending;
    expect(review.completed, 0);
    expect(review.error, contains('暂停'));
    await review.run();
    expect(review.completed, 5);
  });

  test(
    'review snapshots input and cannot be altered by original tree edits',
    () {
      final record = GameRecord();
      final isolated = ReviewController(record: record, engine: engine);
      record.addSan(record.root, 'e4');
      expect(isolated.line.length, 1);
      isolated.dispose();
    },
  );

  test(
    'rule-adjudicated draw is zero without asking position-only AI',
    () async {
      final drawn = ReviewController(
        record: GameRecord(initialFen: '7k/8/6K1/8/8/8/8/8 w - - 0 1'),
        engine: engine,
      );
      await drawn.run();
      expect(drawn.completed, 1);
      expect(drawn.evaluations.single!.whiteCp, 0);
      expect(engine.requests, isEmpty);
      drawn.dispose();
    },
  );
}
