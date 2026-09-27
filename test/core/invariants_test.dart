import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/game_tree.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/pgn.dart';

import '../../tool/perft.dart';

void main() {
  for (final entry in perftCases) {
    test('${entry.name}: every legal move preserves make/undo invariants', () {
      final board = Board.fromFen(entry.fen);
      final key = board.zobristHash;
      for (final move in board.legalMoves()) {
        final san = board.san(move);
        board.play(move);
        final roundTrip = Board.fromFen(board.toFen());
        expect(roundTrip.zobristHash, board.zobristHash);
        expect(roundTrip.legalMoves(), board.legalMoves());
        expect(board.plyCount, 1);
        expect(board.lastMove, move);
        expect(board.undo(), move);
        expect(board.parseSan(san), move);
        expect(board.toFen(), entry.fen);
        expect(board.zobristHash, key);
        expect(board.repetitionCount, 1);
        expect(board.lastMove, isNull);
      }
    });
  }
  test('seeded complete games preserve notation, tree, history and undo', () {
    final random = Random(20260928);
    for (var game = 0; game < 4; game++) {
      final board = Board();
      final record = GameRecord();
      var node = record.root;
      final fens = [board.toFen()];
      final keys = [board.zobristHash];
      final played = <Move>[];
      for (var ply = 0; ply < 80; ply++) {
        final legal = board.legalMoves();
        if (legal.isEmpty) break;
        final move = legal[random.nextInt(legal.length)];
        expect(board.parseSan(board.san(move)), move);
        node = record.addMove(node, move);
        board.play(move);
        played.add(move);
        fens.add(board.toFen());
        keys.add(board.zobristHash);
        expect(Board.fromFen(fens.last).zobristHash, keys.last);
      }
      final restored = Pgn.parse(Pgn.generate(record));
      expect(restored.mainLine.skip(1).map((n) => n.move), played);
      expect(restored.boardAt(restored.mainLine.last).toFen(), board.toFen());
      for (var ply = played.length - 1; ply >= 0; ply--) {
        expect(board.undo(), played[ply]);
        expect(board.toFen(), fens[ply]);
        expect(board.zobristHash, keys[ply]);
      }
      expect(board.toFen(), Fen.initial);
      expect(board.repetitionCount, 1);
    }
  });
}
