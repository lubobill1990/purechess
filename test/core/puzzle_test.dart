import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/puzzle.dart';

PuzzleProblem opening({List<String>? line}) => PuzzleProblem(
  id: 'opening',
  title: 'Develop pieces',
  fen: Fen.initial,
  line: (line ?? ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5'])
      .map(Move.fromUci)
      .toList(),
  themes: ['opening'],
  rating: 800,
);

void main() {
  test('solver move auto replies and progresses to solved', () {
    final session = PuzzleSession(opening());
    expect(session.playerColor, Color.white);
    expect(session.hintSquare(), parseSquare('e2'));
    expect(session.hint(), Move.fromUci('e2e4'));
    expect(session.playUserMove(Move.fromUci('e2e4')), Move.fromUci('e7e5'));
    expect(session.completedPlies, 2);
    expect(session.board.turn, Color.white);
    expect(session.status, PuzzleStatus.playing);
    expect(session.playUserMove(Move.fromUci('g1f3')), Move.fromUci('b8c6'));
    expect(session.playUserMove(Move.fromUci('f1b5')), isNull);
    expect(session.status, PuzzleStatus.solved);
    expect(session.completedPlies, 5);
    expect(session.hint(), isNull);
  });
  test('one move puzzle solves without opponent reply', () {
    final session = PuzzleSession(opening(line: ['e2e4']));
    expect(session.playUserMove(Move.fromUci('e2e4')), isNull);
    expect(session.status, PuzzleStatus.solved);
  });
  test('line ending with opponent reply settles solved', () {
    final session = PuzzleSession(opening(line: ['e2e4', 'e7e5']));
    expect(session.playUserMove(Move.fromUci('e2e4')), Move.fromUci('e7e5'));
    expect(session.status, PuzzleStatus.solved);
  });
  test('off-line legal move fails without board mutation', () {
    final session = PuzzleSession(opening());
    expect(session.playUserMove(Move.fromUci('d2d4')), isNull);
    expect(session.status, PuzzleStatus.failed);
    expect(session.offLineMove, Move.fromUci('d2d4'));
    expect(session.board.toFen(), Fen.initial);
    expect(session.completedPlies, 0);
    expect(session.hint(), isNull);
  });
  test('illegal move throws without consuming attempt', () {
    final session = PuzzleSession(opening());
    expect(
      () => session.playUserMove(Move.fromUci('e2e5')),
      throwsA(isA<IllegalMoveException>()),
    );
    expect(session.status, PuzzleStatus.playing);
    expect(session.completedPlies, 0);
    expect(session.offLineMove, isNull);
  });
  test('ended attempt rejects further moves', () {
    final session = PuzzleSession(opening(line: ['e2e4']));
    session.playUserMove(Move.fromUci('e2e4'));
    expect(() => session.playUserMove(Move.fromUci('e7e5')), throwsStateError);
  });
  test('reset after failure clears the entire attempt', () {
    final session = PuzzleSession(opening());
    session.playUserMove(Move.fromUci('e2e4'));
    session.playUserMove(Move.fromUci('d2d4'));
    session.reset();
    expect(session.status, PuzzleStatus.playing);
    expect(session.completedPlies, 0);
    expect(session.offLineMove, isNull);
    expect(session.board.toFen(), Fen.initial);
    expect(session.hint(), Move.fromUci('e2e4'));
  });
  test('reset after success permits retry', () {
    final session = PuzzleSession(opening(line: ['e2e4']));
    session.playUserMove(Move.fromUci('e2e4'));
    session.reset();
    session.playUserMove(Move.fromUci('e2e4'));
    expect(session.status, PuzzleStatus.solved);
  });
  test('board snapshots cannot change session state', () {
    final session = PuzzleSession(opening());
    session.board.playUci('d2d4');
    expect(session.board.toFen(), Fen.initial);
  });
  test('empty solution is rejected', () {
    expect(() => opening(line: []), throwsArgumentError);
  });
  test('illegal later solution move is rejected at construction', () {
    expect(
      () => opening(line: ['e2e4', 'e7e4']),
      throwsA(isA<IllegalMoveException>()),
    );
  });
  test('solution and themes are immutable', () {
    final problem = opening();
    expect(() => problem.line.clear(), throwsUnsupportedError);
    expect(() => problem.themes.clear(), throwsUnsupportedError);
  });
  test('Lichess first move sets up black solver and automatic reply', () {
    final problem = PuzzleProblem.fromLichess(
      id: 'lichess',
      fen: Fen.initial,
      moves: 'e2e4 e7e5 g1f3 b8c6',
      themes: ['development'],
      rating: 1000,
    );
    final session = PuzzleSession(problem);
    expect(session.playerColor, Color.black);
    expect(session.hint(), Move.fromUci('e7e5'));
    expect(session.playUserMove(Move.fromUci('e7e5')), Move.fromUci('g1f3'));
    session.playUserMove(Move.fromUci('b8c6'));
    expect(session.status, PuzzleStatus.solved);
    expect(problem.rating, 1000);
    expect(problem.themes, ['development']);
  });
  test('Lichess setup-only line is rejected', () {
    expect(
      () => PuzzleProblem.fromLichess(id: 'x', fen: Fen.initial, moves: 'e2e4'),
      throwsArgumentError,
    );
  });
  test('promotion solution requires the correct promotion piece', () {
    final problem = PuzzleProblem(
      id: 'mate',
      fen: '7k/4P1pp/8/5K2/8/8/8/8 w - - 0 1',
      line: [Move.fromUci('e7e8q')],
    );
    final session = PuzzleSession(problem);
    session.playUserMove(Move.fromUci('e7e8n'));
    expect(session.status, PuzzleStatus.failed);
    session.reset();
    session.playUserMove(Move.fromUci('e7e8q'));
    expect(session.status, PuzzleStatus.solved);
  });
}
