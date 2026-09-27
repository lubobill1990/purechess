import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/move.dart';

List<String> moves(Board board) =>
    board.legalMoves().map((m) => m.uci).toList();

void main() {
  group('position and movement', () {
    test('initial position and state', () {
      final board = Board();
      expect(board.toFen(), Fen.initial);
      expect(board.turn, Color.white);
      expect(board.status, GameStatus.playing);
      expect(board.winner, isNull);
      expect(board.lastMove, isNull);
      expect(
        board.pieceAt(parseSquare('e1')),
        const Piece(Color.white, PieceType.king),
      );
      expect(
        board.pieceAt(parseSquare('d8')),
        const Piece(Color.black, PieceType.queen),
      );
      expect(board.pieceAt(parseSquare('e4')), isNull);
    });
    for (final uci in [
      'e2e3',
      'e2e4',
      'a2a4',
      'h2h3',
      'b1a3',
      'b1c3',
      'g1f3',
      'g1h3',
    ]) {
      test(
        'initial legal $uci',
        () => expect(Board().isLegal(Move.fromUci(uci)), isTrue),
      );
    }
    for (final uci in [
      'e2e5',
      'e2f3',
      'a1a2',
      'f1b5',
      'e1e2',
      'e1g1',
      'b1b3',
      'b1d2',
      'e7e5',
      'e2e4q',
    ]) {
      test('initial illegal $uci is atomic', () {
        final board = Board();
        final key = board.zobristHash;
        expect(() => board.playUci(uci), throwsA(isA<IllegalMoveException>()));
        expect(board.toFen(), Fen.initial);
        expect(board.zobristHash, key);
        expect(board.plyCount, 0);
      });
    }
    for (final entry in [
      ('P', 'e5', 'd5'),
      ('N', 'f5', 'e5'),
      ('B', 'g7', 'd7'),
      ('R', 'd7', 'g7'),
      ('Q', 'g7', 'f7'),
    ]) {
      test('${entry.$1} attack geometry', () {
        final board = Board.fromFen('7k/8/8/8/3${entry.$1}4/8/8/K7 w - - 0 1');
        expect(board.isAttacked(parseSquare(entry.$2), Color.white), isTrue);
        expect(board.isAttacked(parseSquare(entry.$3), Color.white), isFalse);
      });
    }
    test('king attacks adjacent squares', () {
      final board = Board.fromFen('7k/8/8/8/3K4/8/8/8 w - - 0 1');
      expect(board.isAttacked(parseSquare('e5'), Color.white), isTrue);
      expect(board.isAttacked(parseSquare('f5'), Color.white), isFalse);
    });
    test('black pawn attacks downward, not forward', () {
      final board = Board.fromFen('7k/8/8/3p4/8/8/8/K7 w - - 0 1');
      expect(board.isAttacked(parseSquare('c4'), Color.black), isTrue);
      expect(board.isAttacked(parseSquare('e4'), Color.black), isTrue);
      expect(board.isAttacked(parseSquare('d4'), Color.black), isFalse);
    });
    test('sliders stop at either color blocker', () {
      final board = Board.fromFen('7k/8/3p4/8/3R1P2/8/8/K7 w - - 0 1');
      expect(board.isAttacked(parseSquare('d7'), Color.white), isFalse);
      expect(board.isAttacked(parseSquare('g4'), Color.white), isFalse);
      expect(moves(board), contains('d4d6'));
      expect(moves(board), isNot(contains('d4f4')));
    });
    test('pinned rook may stay on pin ray only', () {
      final board = Board.fromFen('4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1');
      expect(moves(board), contains('e2e8'));
      expect(moves(board), isNot(contains('e2d2')));
    });
    test('double check permits only king moves', () {
      final board = Board.fromFen('4r2k/8/8/8/1b6/8/2R5/4K3 w - - 0 1');
      expect(board.inCheck, isTrue);
      expect(board.legalMoves(), isNotEmpty);
      expect(
        board.legalMoves().every((m) => m.from == parseSquare('e1')),
        isTrue,
      );
    });
    test('pinned enemy pieces still attack king destinations', () {
      final board = Board.fromFen('4k3/4n3/8/6K1/8/8/8/4R3 w - - 0 1');
      expect(board.isAttacked(parseSquare('f5'), Color.black), isTrue);
      expect(moves(board), isNot(contains('g5f5')));
    });
    test('king cannot capture a protected piece', () {
      final board = Board.fromFen('7k/8/8/8/8/4r3/4p3/4K3 w - - 0 1');
      expect(moves(board), isNot(contains('e1e2')));
    });
    test('copy preserves history but isolates mutation', () {
      final board = Board()..playUci('e2e4');
      final clone = board.copy()..playUci('e7e5');
      expect(board.turn, Color.black);
      expect(clone.plyCount, 2);
      clone.undo();
      expect(clone.toFen(), board.toFen());
      clone.undo();
      expect(clone.toFen(), Fen.initial);
      expect(board.plyCount, 1);
    });
    test(
      'undo empty board throws',
      () => expect(() => Board().undo(), throwsStateError),
    );
    test('perft depth zero and negative depth', () {
      expect(Board().perft(0), 1);
      expect(() => Board().perft(-1), throwsArgumentError);
    });
    test('invalid mailbox access throws', () {
      expect(() => Board().pieceAt(8), throwsArgumentError);
      expect(() => Board().isAttacked(-1, Color.white), throwsArgumentError);
    });
  });

  group('castling', () {
    for (final entry in [
      ('w', 'e1g1', 'g1', 'f1', 'h1', 'O-O', 12),
      ('w', 'e1c1', 'c1', 'd1', 'a1', 'O-O-O', 12),
      ('b', 'e8g8', 'g8', 'f8', 'h8', 'O-O', 3),
      ('b', 'e8c8', 'c8', 'd8', 'a8', 'O-O-O', 3),
    ]) {
      test('${entry.$1} ${entry.$6} moves both pieces and undoes', () {
        final fen = 'r3k2r/8/8/8/8/8/8/R3K2R ${entry.$1} KQkq - 7 20';
        final board = Board.fromFen(fen);
        final color = board.turn;
        final move = Move.fromUci(entry.$2);
        expect(board.san(move), entry.$6);
        expect(board.parseSan(entry.$6.replaceAll('O', '0')), move);
        board.play(move);
        expect(
          board.pieceAt(parseSquare(entry.$3)),
          Piece(color, PieceType.king),
        );
        expect(
          board.pieceAt(parseSquare(entry.$4)),
          Piece(color, PieceType.rook),
        );
        expect(board.pieceAt(parseSquare(entry.$5)), isNull);
        expect(board.castlingRights, entry.$7);
        expect(board.halfmoveClock, 8);
        board.undo();
        expect(board.toFen(), fen);
      });
    }
    for (final entry in [
      ('missing rook', '4k3/8/8/8/8/8/8/4K3 w KQ - 0 1', 'e1g1'),
      ('wrong color rook', '4k3/8/8/8/8/8/8/4K2r w K - 0 1', 'e1g1'),
      ('king off home', '4k3/8/8/8/8/8/8/3K3R w K - 0 1', 'd1f1'),
      ('no rights', '4k3/8/8/8/8/8/8/4K2R w - - 0 1', 'e1g1'),
      ('occupied transit', '4k3/8/8/8/8/8/8/4KB1R w K - 0 1', 'e1g1'),
      ('occupied b file', '4k3/8/8/8/8/8/8/RN2K3 w Q - 0 1', 'e1c1'),
      ('in check', '4r2k/8/8/8/8/8/8/R3K2R w KQ - 0 1', 'e1g1'),
      ('through check', '5r1k/8/8/8/8/8/8/4K2R w K - 0 1', 'e1g1'),
      ('into check', '6rk/8/8/8/8/8/8/4K2R w K - 0 1', 'e1g1'),
      ('queenside through check', '3r3k/8/8/8/8/8/8/R3K3 w Q - 0 1', 'e1c1'),
      ('black through check', 'r3k2r/8/8/8/8/8/8/3R3K b kq - 0 1', 'e8c8'),
      ('pawn attacks transit', '7k/8/8/8/8/8/4p3/4K2R w K - 0 1', 'e1g1'),
    ]) {
      test('${entry.$1} forbids castling', () {
        final board = Board.fromFen(entry.$2);
        expect(board.isLegal(Move.fromUci(entry.$3)), isFalse);
      });
    }
    test('attacked b1 does not forbid queenside castling', () {
      final board = Board.fromFen('1r5k/8/8/8/8/8/8/R3K3 w Q - 0 1');
      expect(moves(board), contains('e1c1'));
    });
    test('rook movement permanently loses that right', () {
      final board = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      for (final move in ['h1h2', 'h8h7', 'h2h1', 'h7h8']) {
        board.playUci(move);
      }
      expect(board.castlingRights, 10);
      expect(moves(board), isNot(contains('e1g1')));
      expect(moves(board), contains('e1c1'));
    });
    test('king movement permanently loses both rights', () {
      final board = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      for (final move in ['e1f1', 'e8f8', 'f1e1', 'f8e8']) {
        board.playUci(move);
      }
      expect(board.castlingRights, 0);
    });
    test('home rook capture revokes both involved rights', () {
      final board = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      board.playUci('a1a8');
      expect(board.castlingRights, 5);
      board.undo();
      expect(board.castlingRights, 15);
    });
  });

  group('en passant', () {
    for (final entry in [
      ('white', '7k/8/8/3pP3/8/8/8/K7 w - d6 12 9', 'e5d6', 'd5'),
      ('black', '7k/8/8/8/3Pp3/8/8/K7 b - d3 12 9', 'e4d3', 'd4'),
    ]) {
      test('${entry.$1} captures and undoes en passant', () {
        final board = Board.fromFen(entry.$2);
        final key = board.zobristHash;
        board.playUci(entry.$3);
        expect(board.pieceAt(parseSquare(entry.$4)), isNull);
        expect(board.halfmoveClock, 0);
        expect(board.enPassant, isNull);
        board.undo();
        expect(board.toFen(), entry.$2);
        expect(board.zobristHash, key);
      });
    }
    test('horizontal discovered check makes EP illegal', () {
      final board = Board.fromFen('7k/8/8/r4pPK/8/8/8/8 w - f6 0 1');
      expect(moves(board), isNot(contains('g5f6')));
    });
    test('vertical pin makes EP illegal', () {
      final board = Board.fromFen('k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      expect(moves(board), isNot(contains('e5d6')));
    });
    test('EP can remove a checking pawn', () {
      final board = Board.fromFen('7k/8/8/3pP3/4K3/8/8/8 w - d6 0 1');
      expect(board.inCheck, isTrue);
      board.playUci('e5d6');
      expect(board.isAttacked(parseSquare('e4'), Color.black), isFalse);
    });
    test('EP cannot capture a nonexistent pawn', () {
      final board = Board.fromFen('7k/8/8/4P3/8/8/8/K7 w - d6 0 1');
      expect(moves(board), isNot(contains('e5d6')));
    });
    test('EP expires after one reply', () {
      final board = Board.fromFen('7k/3p4/8/4P3/8/8/8/K7 b - - 0 1');
      board.playUci('d7d5');
      expect(moves(board), contains('e5d6'));
      board.playUci('a1a2');
      board.playUci('h8h7');
      expect(moves(board), isNot(contains('e5d6')));
    });
  });

  group('promotion', () {
    for (final side in ['w', 'b']) {
      for (final letter in ['q', 'r', 'b', 'n']) {
        test('$side promotes to $letter and undoes', () {
          final fen = side == 'w'
              ? '7k/4P3/8/8/8/8/8/K7 w - - 12 1'
              : '7k/8/8/8/8/8/4p3/K7 b - - 12 1';
          final move = Move.fromUci(
            side == 'w' ? 'e7e8$letter' : 'e2e1$letter',
          );
          final board = Board.fromFen(fen);
          final color = board.turn;
          expect(
            board.legalMoves().where((m) => m.from == move.from).length,
            4,
          );
          board.play(move);
          expect(board.pieceAt(move.to), Piece(color, move.promotion!));
          expect(board.halfmoveClock, 0);
          board.undo();
          expect(board.toFen(), fen);
        });
      }
    }
    test('capture promotion offers all four choices', () {
      final board = Board.fromFen('3r3k/4P3/8/8/8/8/8/K7 w - - 0 1');
      expect(moves(board), containsAll(['e7d8q', 'e7d8r', 'e7d8b', 'e7d8n']));
      board.playUci('e7d8n');
      expect(
        board.pieceAt(parseSquare('d8')),
        const Piece(Color.white, PieceType.knight),
      );
      board.undo();
      expect(
        board.pieceAt(parseSquare('d8')),
        const Piece(Color.black, PieceType.rook),
      );
    });
    test('promotion piece is mandatory', () {
      final board = Board.fromFen('7k/4P3/8/8/8/8/8/K7 w - - 0 1');
      expect(board.isLegal(Move.fromUci('e7e8')), isFalse);
      expect(
        board.isLegal(
          Move(parseSquare('e7'), parseSquare('e8'), promotion: PieceType.king),
        ),
        isFalse,
      );
    });
  });

  group('outcomes and repetition', () {
    test('Fools mate and winner', () {
      final board = Board();
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        board.playSan(san);
      }
      expect(board.status, GameStatus.checkmate);
      expect(board.winner, Color.black);
      expect(board.legalMoves(), isEmpty);
    });
    test('stalemate is not checkmate', () {
      final board = Board.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(board.status, GameStatus.stalemate);
      expect(board.inCheck, isFalse);
      expect(board.winner, isNull);
    });
    for (final entry in [
      ('bare kings', '7k/8/8/8/8/8/8/K7', true),
      ('one knight', '7k/8/8/8/8/8/8/KN6', true),
      ('one bishop', '7k/8/8/8/8/8/8/KB6', true),
      ('same-color bishops', '7k/8/8/8/8/5b2/8/KB6', true),
      ('opposite-color bishops', '7k/8/8/8/8/4b3/8/KB6', false),
      ('two knights', '7k/8/8/8/8/8/8/KNN5', false),
      ('opposing knights', '6nk/8/8/8/8/8/8/KN6', false),
      ('bishop and knight', '7k/8/8/8/8/8/8/KNB5', false),
      ('pawn', '7k/8/8/8/8/8/P7/K7', false),
      ('rook', '7k/8/8/8/8/8/R7/K7', false),
      ('queen', '7k/8/8/8/8/8/Q7/K7', false),
      ('promoted same-color bishops', '7k/8/8/8/8/5B2/8/KB6', true),
    ]) {
      test('insufficient material: ${entry.$1}', () {
        final board = Board.fromFen('${entry.$2} w - - 0 1');
        expect(board.isInsufficientMaterial, entry.$3);
        expect(
          board.status,
          entry.$3 ? GameStatus.insufficientMaterial : GameStatus.playing,
        );
      });
    }
    test('50 move threshold at 100 halfmoves', () {
      final board = Board.fromFen('7k/8/8/8/8/8/R7/K7 w - - 99 50');
      expect(board.isFiftyMoveDraw, isFalse);
      board.playUci('a2b2');
      expect(board.halfmoveClock, 100);
      expect(board.status, GameStatus.fiftyMoveDraw);
      board.undo();
      expect(board.halfmoveClock, 99);
    });
    test('pawn move resets halfmove clock', () {
      final board = Board.fromFen('7k/8/8/8/8/8/P7/K7 w - - 99 50');
      board.playUci('a2a3');
      expect(board.halfmoveClock, 0);
    });
    test('capture resets halfmove clock', () {
      final board = Board.fromFen('7k/8/8/8/8/n7/R7/K7 w - - 99 50');
      board.playUci('a2a3');
      expect(board.halfmoveClock, 0);
    });
    test('checkmate takes precedence over 50 moves', () {
      final board = Board.fromFen('7k/8/5KQ1/8/8/8/8/8 w - - 99 50');
      board.playSan('Qg7#');
      expect(board.halfmoveClock, 100);
      expect(board.status, GameStatus.checkmate);
    });
    test('threefold repetition counts initial position, copy and undo', () {
      final board = Board();
      final initialKey = board.zobristHash;
      for (var cycle = 0; cycle < 2; cycle++) {
        for (final move in ['g1f3', 'g8f6', 'f3g1', 'f6g8']) {
          board.playUci(move);
        }
        expect(board.repetitionCount, cycle + 2);
      }
      expect(board.zobristHash, initialKey);
      expect(board.status, GameStatus.threefoldRepetition);
      final clone = board.copy()..undo();
      expect(clone.isThreefoldRepetition, isFalse);
      expect(board.isThreefoldRepetition, isTrue);
      board.undo();
      board.playUci('f6g8');
      expect(board.repetitionCount, 3);
    });
    test('hash ignores clocks, includes side and castling rights', () {
      final original = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      final clocks = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 99 50');
      final side = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1');
      final rights = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w Qkq - 0 1');
      expect(original.zobristHash, clocks.zobristHash);
      expect(original.zobristHash, isNot(side.zobristHash));
      expect(original.zobristHash, isNot(rights.zobristHash));
      expect(original.zobristHash.bitLength, lessThanOrEqualTo(64));
    });
    for (final entry in [
      ('legal EP', '7k/8/8/3pP3/8/8/8/K7 w - d6 0 1', false),
      ('uncapturable EP', '7k/8/8/3p4/8/8/8/K7 w - d6 0 1', true),
      ('pinned EP', 'k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 1', true),
      ('horizontal pinned EP', '7k/8/8/r4pPK/8/8/8/8 w - f6 0 1', true),
      (
        'one of two pawns can capture',
        'k3r3/8/8/2PpP3/8/8/8/4K3 w - d6 0 1',
        false,
      ),
    ]) {
      test('Zobrist ${entry.$1}', () {
        final board = Board.fromFen(entry.$2);
        final without = Board.fromFen(
          entry.$2.replaceFirst(RegExp(r'[df]6'), '-'),
        );
        expect(board.zobristHash == without.zobristHash, entry.$3);
        expect(board.toFen(), entry.$2);
      });
    }
    test('same arrangement after loss of castling is not a repetition', () {
      final board = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      for (final move in ['h1h2', 'h8h7', 'h2h1', 'h7h8']) {
        board.playUci(move);
      }
      expect(board.repetitionCount, 1);
    });
    test('irrelevant EP does not prevent actual repetition', () {
      final board = Board()..playUci('e2e4');
      final key = board.zobristHash;
      for (var i = 0; i < 2; i++) {
        for (final move in ['g8f6', 'g1f3', 'f6g8', 'f3g1']) {
          board.playUci(move);
        }
      }
      expect(board.zobristHash, key);
      expect(board.isThreefoldRepetition, isTrue);
    });
    test('FEN import cannot invent repetition history', () {
      final board = Board();
      for (var i = 0; i < 2; i++) {
        for (final move in ['g1f3', 'g8f6', 'f3g1', 'f6g8']) {
          board.playUci(move);
        }
      }
      expect(Board.fromFen(board.toFen()).repetitionCount, 1);
    });
  });
}
