import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/puzzle.dart';
import 'package:purechess/features/puzzle/puzzle_attempt.dart';

import 'fixtures.dart';

void main() {
  test('two hint levels reveal idea before source and reset after a move', () {
    final attempt = PuzzleAttempt(practice());
    expect(attempt.hintSquare, isNull);
    attempt.revealHint();
    expect(attempt.idea, contains('同时攻击两个目标'));
    expect(attempt.hintSquare, isNull);
    attempt.revealHint();
    attempt.revealHint();
    expect(attempt.hintLevel, 2);
    expect(attempt.hintSquare, parseSquare('e2'));
    attempt.play(Move.fromUci('e2e4'));
    expect(attempt.hintLevel, 0);
    expect(attempt.hintSquare, isNull);
    expect(
      attempt.board.pieceAt(parseSquare('e5')),
      const Piece(Color.black, PieceType.pawn),
    );
    expect(attempt.board.turn, Color.white);
    attempt.play(Move.fromUci('g1f3'));
    expect(attempt.status, PuzzleStatus.solved);
    expect(attempt.elapsed.isRunning, isFalse);
  });
  test('failure, retry, illegal moves and ended attempts preserve state', () {
    final attempt = PuzzleAttempt(practice());
    expect(
      () => attempt.play(Move.fromUci('e2e5')),
      throwsA(isA<IllegalMoveException>()),
    );
    expect(attempt.status, PuzzleStatus.playing);
    attempt.play(Move.fromUci('d2d4'));
    expect(attempt.status, PuzzleStatus.failed);
    expect(attempt.board.toFen(), Fen.initial);
    expect(() => attempt.play(Move.fromUci('e2e4')), throwsStateError);
    expect(() => attempt.revealHint(), throwsStateError);
    attempt.retry();
    expect(attempt.attempts, 2);
    expect(attempt.elapsed.isRunning, isTrue);
    expect(attempt.status, PuzzleStatus.playing);
  });
  for (final black in [false, true]) {
    test('alternative mate-in-one accepted (${black ? 'black' : 'white'})', () {
      final attempt = PuzzleAttempt(mate(black: black));
      attempt.play(Move.fromUci(black ? 'f2f1' : 'f7f8'));
      expect(attempt.status, PuzzleStatus.solved);
      expect(attempt.board.status, GameStatus.checkmate);
      expect(() => attempt.play(Move.fromUci('a1a2')), throwsStateError);
      attempt.retry();
      expect(attempt.board.toFen(), attempt.problem.fen);
      expect(attempt.status, PuzzleStatus.playing);
    });
  }
  test('legal non-mating alternative does not solve mate-in-one', () {
    final attempt = PuzzleAttempt(mate());
    attempt.play(Move.fromUci('f7f6'));
    expect(attempt.status, PuzzleStatus.failed);
  });
  test('alternative rook promotion mate is accepted', () {
    final attempt = PuzzleAttempt(
      PuzzleProblem(
        id: 'promotion',
        fen: '7k/4P1pp/8/5K2/8/8/8/8 w - - 0 1',
        line: [Move.fromUci('e7e8q')],
        themes: ['mateIn1'],
      ),
    );
    attempt.play(Move.fromUci('e7e8r'));
    expect(attempt.status, PuzzleStatus.solved);
    expect(attempt.board.status, GameStatus.checkmate);
  });
}
