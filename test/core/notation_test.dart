import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/move.dart';

import '../../tool/perft.dart';

void main() {
  group('coordinates and UCI', () {
    test('all 64 mailbox squares round trip', () {
      for (var rank = 0; rank < 8; rank++) {
        for (var file = 0; file < 8; file++) {
          final square = rank * 16 + file;
          expect(parseSquare(squareName(square)), square);
          expect(isSquare(square), isTrue);
        }
      }
    });
    for (final text in ['', 'a0', 'i1', 'A1', 'a9', ' a1', 'a10']) {
      test('reject invalid square "$text"', () {
        expect(() => parseSquare(text), throwsFormatException);
      });
    }
    for (final square in [-1, 8, 15, 128]) {
      test('reject invalid square index $square', () {
        expect(isSquare(square), isFalse);
        expect(() => squareName(square), throwsArgumentError);
      });
    }
    for (final text in ['e2e4', 'e7e8q', 'b2a1n', 'e1g1']) {
      test('UCI round trip $text', () {
        final move = Move.fromUci(text);
        expect(move.uci, text);
        expect(move, Move.fromUci(text));
        expect(move.hashCode, Move.fromUci(text).hashCode);
      });
    }
    for (final text in [
      '',
      'e4',
      'e2e9',
      'e7e8k',
      'e7e8Q',
      'e2-e4',
      'e2e4qq',
    ]) {
      test('reject malformed UCI "$text"', () {
        expect(() => Move.fromUci(text), throwsFormatException);
      });
    }
    test('promotion is part of move identity', () {
      expect(Move.fromUci('e7e8q'), isNot(Move.fromUci('e7e8n')));
    });
  });

  group('FEN', () {
    for (final entry in perftCases) {
      test('${entry.name} exact FEN round trip', () {
        expect(Fen.generate(Fen.parse(entry.fen)), entry.fen);
        expect(Board.fromFen(entry.fen).toFen(), entry.fen);
      });
    }
    test('FEN retains uncapturable EP and black counters', () {
      const fen = '7k/8/8/8/4P3/8/8/K7 b - e3 0 123';
      expect(Board.fromFen(fen).toFen(), fen);
    });
    test('FEN accepts surrounding whitespace', () {
      expect(Board.fromFen('  ${Fen.initial}\n').toFen(), Fen.initial);
    });
    test('FEN state after white and black double pushes', () {
      final board = Board()..playUci('e2e4');
      expect(
        board.toFen(),
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
      );
      board.playUci('c7c5');
      expect(
        board.toFen(),
        'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
      );
    });
    for (final entry in [
      ('missing counters', '7k/8/8/8/8/8/8/K7 w - -'),
      ('extra field', '7k/8/8/8/8/8/8/K7 w - - 0 1 extra'),
      ('short board', '7k/8/8/8/8/8/K7 w - - 0 1'),
      ('long board', '7k/8/8/8/8/8/8/8/K7 w - - 0 1'),
      ('short rank', '6k/8/8/8/8/8/8/K7 w - - 0 1'),
      ('wide rank', '8k/8/8/8/8/8/8/K7 w - - 0 1'),
      ('zero digit', '07k/8/8/8/8/8/8/K7 w - - 0 1'),
      ('adjacent digits', '61k/8/8/8/8/8/8/K7 w - - 0 1'),
      ('unknown piece', '6xk/8/8/8/8/8/8/K7 w - - 0 1'),
      ('missing king', '7k/8/8/8/8/8/8/8 w - - 0 1'),
      ('duplicate king', '7k/8/8/8/8/8/8/KK6 w - - 0 1'),
      ('pawn back rank', 'P6k/8/8/8/8/8/8/K7 w - - 0 1'),
      ('bad side', '7k/8/8/8/8/8/8/K7 x - - 0 1'),
      ('bad castling', '7k/8/8/8/8/8/8/K7 w A - 0 1'),
      ('duplicate castling', '7k/8/8/8/8/8/8/K7 w KK - 0 1'),
      ('mixed castling dash', '7k/8/8/8/8/8/8/K7 w K- - 0 1'),
      ('bad EP square', '7k/8/8/8/8/8/8/K7 w - z6 0 1'),
      ('bad EP rank', '7k/8/8/8/8/8/8/K7 w - d4 0 1'),
      ('wrong EP side', '7k/8/8/8/8/8/8/K7 b - d6 0 1'),
      ('occupied EP', '7k/8/3N4/8/8/8/8/K7 w - d6 0 1'),
      ('negative halfmove', '7k/8/8/8/8/8/8/K7 w - - -1 1'),
      ('fractional halfmove', '7k/8/8/8/8/8/8/K7 w - - 1.5 1'),
      ('zero fullmove', '7k/8/8/8/8/8/8/K7 w - - 0 0'),
      ('nonnumeric fullmove', '7k/8/8/8/8/8/8/K7 w - - 0 x'),
    ]) {
      test('reject ${entry.$1}', () {
        expect(() => Board.fromFen(entry.$2), throwsFormatException);
      });
    }
    test('position snapshot cannot mutate a board', () {
      final board = Board();
      expect(() => board.position.squares[0] = 0, throwsUnsupportedError);
      expect(board.toFen(), Fen.initial);
    });
  });

  group('SAN', () {
    for (final entry in [
      (
        'file disambiguation',
        '7k/8/8/8/8/8/8/1N2KN2 w - - 0 1',
        'b1d2',
        'Nbd2',
      ),
      (
        'rank disambiguation',
        '7k/8/8/8/8/1N6/8/1N2K3 w - - 0 1',
        'b1d2',
        'N1d2',
      ),
      (
        'capture disambiguation',
        '7k/8/8/8/3p4/1N3N2/8/4K3 w - - 0 1',
        'b3d4',
        'Nbxd4',
      ),
      (
        'full disambiguation',
        '7k/8/8/1N6/8/1N3N2/8/4K3 w - - 0 1',
        'b3d4',
        'Nb3d4',
      ),
      (
        'pinned knight not ambiguous',
        '1r5k/8/8/8/8/8/1N1N4/1K6 w - - 0 1',
        'd2c4',
        'Nc4',
      ),
      ('promotion mate', '7k/4P1pp/8/5K2/8/8/8/8 w - - 0 1', 'e7e8q', 'e8=Q#'),
      ('promotion check', '7k/4P3/8/8/8/8/8/K7 w - - 0 1', 'e7e8r', 'e8=R+'),
      ('underpromotion', '7k/4P3/8/8/8/8/8/K7 w - - 0 1', 'e7e8n', 'e8=N'),
      (
        'capture promotion',
        '3r3k/4P3/8/8/8/8/8/K7 w - - 0 1',
        'e7d8q',
        'exd8=Q+',
      ),
      ('en passant', '7k/8/8/3pP3/8/8/8/K7 w - d6 0 1', 'e5d6', 'exd6'),
      ('pawn capture', '7k/8/8/3p4/4P3/8/8/K7 w - - 0 1', 'e4d5', 'exd5'),
      ('discovered check', '4k3/8/8/8/8/8/4B3/K3R3 w - - 0 1', 'e2f3', 'Bf3+'),
    ]) {
      test(entry.$1, () {
        final board = Board.fromFen(entry.$2);
        final key = board.zobristHash;
        final move = Move.fromUci(entry.$3);
        expect(board.san(move), entry.$4);
        expect(board.parseSan(entry.$4), move);
        expect(board.toFen(), entry.$2);
        expect(board.zobristHash, key);
        expect(board.plyCount, 0);
      });
    }
    for (final entry in perftCases) {
      test('all legal ${entry.name} moves SAN/UCI round trip', () {
        final board = Board.fromFen(entry.fen);
        final legal = board.legalMoves();
        final names = legal.map(board.san).toList();
        expect(names.toSet().length, legal.length);
        for (var i = 0; i < legal.length; i++) {
          expect(board.parseSan(names[i]), legal[i]);
          expect(Move.fromUci(legal[i].uci), legal[i]);
        }
        expect(board.toFen(), entry.fen);
      });
    }
    for (final text in [
      'e5',
      'e4+',
      'e4#',
      'Nf3x',
      'Pe4',
      'exd3',
      'O-O',
      'e2e4',
      '',
    ]) {
      test('reject invalid starting SAN "$text"', () {
        expect(() => Board().parseSan(text), throwsFormatException);
      });
    }
    test('ambiguous SAN is rejected', () {
      final board = Board.fromFen('7k/8/8/8/8/8/8/1N2KN2 w - - 0 1');
      expect(() => board.parseSan('Nd2'), throwsFormatException);
    });
    test('annotations and omitted check suffix are accepted', () {
      expect(Board().parseSan('e4!?'), Move.fromUci('e2e4'));
      final board = Board.fromFen('7k/4P3/8/8/8/8/8/K7 w - - 0 1');
      expect(board.parseSan('e8=Q'), Move.fromUci('e7e8q'));
    });
    test('illegal move cannot be formatted', () {
      expect(
        () => Board().san(Move.fromUci('e2e5')),
        throwsA(isA<IllegalMoveException>()),
      );
    });
  });
}
