import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/features/game/game_session.dart';

void main() {
  void play(GameSession game, String moves) {
    for (final uci in moves.split(' ')) {
      game.play(Move.fromUci(uci));
    }
  }

  test('new game owns its board, date and PGN metadata', () {
    final game = GameSession(startedAt: DateTime(2026, 9, 28));
    expect(game.turn, Color.white);
    expect(game.canUndo, isFalse);
    expect(game.outcome, isNull);
    expect(game.snapshot().tags['Date'], '2026.09.28');
    game.board.playUci('e2e4');
    expect(game.board.toFen(), Fen.initial);
    final snapshot = game.snapshot()..result = '1-0';
    expect(snapshot.result, '1-0');
    expect(game.snapshot().result, '*');
  });

  test('illegal moves leave record, board and revision unchanged', () {
    final game = GameSession();
    expect(
      () => game.play(Move.fromUci('e2e5')),
      throwsA(isA<IllegalMoveException>()),
    );
    expect(game.moveCount, 0);
    expect(game.revision, 0);
    expect(game.snapshot().root.isLeaf, isTrue);
  });

  for (final side in Color.values) {
    test('${side.name} can act only on own turn', () {
      final game = GameSession();
      if (side == Color.black) play(game, 'e2e4');
      expect(game.canAct(side), isTrue);
      expect(game.canAct(side.opponent), isFalse);
      expect(() => game.resign(side.opponent), throwsStateError);
      expect(() => game.offerDraw(side.opponent), throwsStateError);
      game.resign(side);
      expect(game.outcome!.reason, GameEndReason.resignation);
      expect(game.outcome!.winner, side.opponent);
      expect(game.snapshot().result, side == Color.white ? '0-1' : '1-0');
      expect(game.snapshot().tags['Termination'], 'resignation');
      expect(() => game.play(Move.fromUci('e2e4')), throwsStateError);
      expect(() => game.offerDraw(side), throwsStateError);
    });

    test('${side.name} offer requires opponent consent', () {
      final game = GameSession();
      if (side == Color.black) play(game, 'e2e4');
      game.offerDraw(side);
      expect(game.drawOffer, side);
      expect(game.canPlay, isFalse);
      expect(game.canUndo, isFalse);
      expect(() => game.respondToDraw(side, accept: true), throwsStateError);
      expect(() => game.play(Move.fromUci('e2e4')), throwsStateError);
      game.respondToDraw(side.opponent, accept: false);
      expect(game.turn, side);
      expect(game.canPlay, isTrue);
      expect(game.snapshot().result, '*');
      game.offerDraw(side);
      game.respondToDraw(side.opponent, accept: true);
      expect(game.outcome!.reason, GameEndReason.agreement);
      expect(game.snapshot().result, '1/2-1/2');
      expect(game.snapshot().tags['Termination'], 'draw agreement');
      expect(
        () => game.respondToDraw(side.opponent, accept: true),
        throwsStateError,
      );
    });
  }

  test('fools mate ends with correct result and undo reopens game', () {
    final game = GameSession();
    play(game, 'f2f3 e7e5 g2g4 d8h4');
    expect(game.outcome!.reason, GameEndReason.checkmate);
    expect(game.outcome!.message, '黑方胜 · 将杀');
    expect(game.snapshot().result, '0-1');
    game.undo();
    expect(game.outcome, isNull);
    expect(game.canPlay, isTrue);
    expect(game.snapshot().result, '*');
    expect(game.snapshot().tags.containsKey('Termination'), isFalse);
    expect(game.snapshot().mainLine.last.comments, isEmpty);
    game.play(Move.fromUci('d8h4'));
    expect(game.outcome!.reason, GameEndReason.checkmate);
  });

  final outcomes = {
    '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1': GameEndReason.stalemate,
    '7k/8/6K1/8/8/8/8/8 w - - 0 1': GameEndReason.insufficientMaterial,
    '7k/8/6K1/8/8/8/R7/8 w - - 100 1': GameEndReason.fiftyMoveDraw,
    '7k/6Q1/6K1/8/8/8/8/8 b - - 100 1': GameEndReason.checkmate,
  };
  for (final entry in outcomes.entries) {
    test('adjudicates ${entry.value.name} including mate priority', () {
      final game = GameSession(initialFen: entry.key);
      expect(game.finished, isTrue);
      expect(game.canAct(game.turn), isFalse);
      expect(game.outcome!.reason, entry.value);
      expect(game.outcome!.message, isNotEmpty);
      final record = game.snapshot();
      expect(
        record.result,
        entry.value == GameEndReason.checkmate ? '1-0' : '1/2-1/2',
      );
      expect(record.initialFen, entry.key);
      expect(Pgn.generate(record), contains('[SetUp "1"]'));
    });
  }

  test('100th quiet half-move ends game and undo restores counter', () {
    final game = GameSession(initialFen: '7k/8/6K1/8/8/8/R7/8 w - - 99 1');
    play(game, 'a2b2');
    expect(game.outcome!.reason, GameEndReason.fiftyMoveDraw);
    game.undo();
    expect(game.outcome, isNull);
    expect(game.board.halfmoveClock, 99);
  });

  test('third repetition auto-draws but core still permits analysis', () {
    final game = GameSession();
    play(game, 'g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8');
    expect(game.outcome!.reason, GameEndReason.threefoldRepetition);
    expect(game.snapshot().result, '1/2-1/2');
    final analysis = game.board..playUci('e2e4');
    expect(analysis.plyCount, 9);
    expect(() => game.play(Move.fromUci('e2e4')), throwsStateError);
    game.undo();
    expect(game.outcome, isNull);
    expect(game.board.isThreefoldRepetition, isFalse);
  });

  test('undo truncates old line, preserves SAN and has no abandoned RAV', () {
    final game = GameSession();
    play(game, 'e2e4 e7e5');
    game.undo();
    play(game, 'c7c5');
    final record = game.snapshot();
    expect(record.mainLine.map((node) => node.move?.uci), [
      null,
      'e2e4',
      'c7c5',
    ]);
    expect(record.root.children.single.children.length, 1);
    expect(Pgn.generate(record), contains('1. e4 1... c5 *'));
    game.undo();
    game.undo();
    expect(game.board.toFen(), Fen.initial);
    expect(game.canUndo, isFalse);
    expect(() => game.undo(), throwsStateError);
  });

  test('undo after agreement or resignation removes result comments', () {
    for (final agreement in [true, false]) {
      final game = GameSession();
      play(game, 'e2e4 e7e5');
      if (agreement) {
        game.offerDraw(Color.white);
        game.respondToDraw(Color.black, accept: true);
      } else {
        game.resign(Color.white);
      }
      game.undo();
      final record = game.snapshot();
      expect(record.result, '*');
      expect(record.mainLine.expand((node) => node.comments), isEmpty);
      expect(game.finished, isFalse);
    }
  });

  for (final (fen, move) in [
    ('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', 'e1g1'),
    ('7k/8/8/3pP3/8/8/8/K7 w - d6 0 2', 'e5d6'),
    ('7k/P7/8/8/8/8/8/7K w - - 0 1', 'a7a8n'),
  ]) {
    test('special move $move round trips PGN and undo', () {
      final game = GameSession(initialFen: fen);
      play(game, move);
      final record = Pgn.parse(Pgn.generate(game.snapshot()));
      expect(record.boardAt(record.mainLine.last).toFen(), game.board.toFen());
      expect(record.mainLine.last.move!.uci, move);
      game.undo();
      expect(game.board.toFen(), fen);
    });
  }
}
