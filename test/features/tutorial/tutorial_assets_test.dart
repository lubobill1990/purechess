import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/puzzle.dart';
import 'package:purechess/features/tutorial/tutorial_level.dart';

List<Map<String, dynamic>> readTutorialAssets() =>
    ((jsonDecode(File('assets/tutorial/levels.json').readAsStringSync())
                as Map<String, dynamic>)['levels']
            as List)
        .cast<Map<String, dynamic>>();

int kingSquare(Board board, Color color) =>
    [
      for (var rank = 0; rank < 8; rank++)
        for (var file = 0; file < 8; file++) rank * 16 + file,
    ].singleWhere(
      (square) => board.pieceAt(square) == Piece(color, PieceType.king),
    );

void main() {
  final assets = readTutorialAssets();
  final levels = assets.map(TutorialLevel.fromJson).toList();

  test('19 ordered levels include every required topic and two mateIn1s', () {
    expect(levels.length, 19);
    expect(levels.map((level) => level.id), [
      'king',
      'queen',
      'rook',
      'bishop',
      'knight',
      'pawn',
      'capture',
      'check',
      'evade-capture',
      'evade-block',
      'evade-escape',
      'checkmate',
      'mate-in-one-rook',
      'mate-in-one-queen',
      'castling',
      'promotion',
      'en-passant',
      'stalemate',
      'graduation',
    ]);
    expect(TutorialCatalog(levels).levels.length, 19);
    expect(
      levels.where((level) => level.goal == TutorialGoal.mateIn1).length,
      2,
    );
  });

  for (var i = 0; i < levels.length; i++) {
    final level = levels[i];
    final asset = assets[i];
    test('${i + 1}. ${level.id}: all moves legal and teaching facts true', () {
      final before = Board.fromFen(level.fen);
      expect(before.status, GameStatus.playing);
      expect(before.turn, Color.white);
      expect(
        before.isAttacked(kingSquare(before, Color.black), Color.white),
        isFalse,
        reason: 'The non-moving king cannot already be in check',
      );
      expect(level.intro, isNotEmpty);
      expect(level.success, isNotEmpty);
      expect(level.failure, isNotEmpty);
      if (level.graduation) {
        expect(before.pieceAt(parseSquare('d8')), isNull);
        expect(before.pieceAt(parseSquare('d1'))?.type, PieceType.queen);
        expect(before.legalMoves().length, 20);
        expect(level.line, isEmpty);
        return;
      }
      final after = before.copy();
      for (final move in level.line) {
        expect(after.status, GameStatus.playing);
        expect(after.isLegal(move), isTrue, reason: move.uci);
        final mover = after.turn;
        after.play(move);
        expect(
          after.isAttacked(kingSquare(after, mover), mover.opponent),
          isFalse,
        );
      }
      final session = PuzzleSession(level.problem);
      while (session.status == PuzzleStatus.playing) {
        session.playUserMove(session.hint()!);
      }
      expect(session.status, PuzzleStatus.solved);
      expect(session.board.toFen(), after.toFen());
      final move = level.line.first;
      switch (level.goal) {
        case TutorialGoal.movement:
          final piece = PieceType.values.byName(asset['piece'] as String);
          expect(before.pieceAt(move.from)?.type, piece);
          expect(after.pieceAt(move.to), Piece(Color.white, piece));
          final df = ((move.to & 7) - (move.from & 7)).abs();
          final dr = ((move.to >> 4) - (move.from >> 4)).abs();
          switch (piece) {
            case PieceType.king:
              expect(df <= 1 && dr <= 1 && df + dr > 0, isTrue);
            case PieceType.queen:
              expect(df == 0 || dr == 0 || df == dr, isTrue);
              expect(before.isLegal(Move.fromUci('d4g7')), isTrue);
              expect(before.isLegal(Move.fromUci('d4g4')), isTrue);
            case PieceType.rook:
              expect(df == 0 || dr == 0, isTrue);
              expect(before.isLegal(Move.fromUci('d4e5')), isFalse);
            case PieceType.bishop:
              expect(df, dr);
              expect(before.isLegal(Move.fromUci('d4d5')), isFalse);
            case PieceType.knight:
              expect({df, dr}, {1, 2});
              expect(before.pieceAt(parseSquare('e4')), isNotNull);
            case PieceType.pawn:
              expect(df, 0);
              expect(dr, 2);
              expect(before.isLegal(Move.fromUci('e2e3')), isTrue);
              expect(before.isLegal(Move.fromUci('e2d3')), isFalse);
              expect(before.isLegal(Move.fromUci('e2e1')), isFalse);
          }
        case TutorialGoal.capture:
          expect(before.pieceAt(move.to)?.color, Color.black);
          expect(before.pieceAt(move.from)?.type, PieceType.pawn);
          expect(after.pieceAt(move.to)?.color, Color.white);
          expect(((move.to & 7) - (move.from & 7)).abs(), 1);
          expect((move.to >> 4) - (move.from >> 4), 1);
        case TutorialGoal.check:
          expect(after.inCheck, isTrue);
          expect(after.legalMoves(), isNotEmpty);
        case TutorialGoal.evadeCapture:
        case TutorialGoal.evadeBlock:
        case TutorialGoal.evadeEscape:
          expect(before.inCheck, isTrue);
          final evasions = (asset['evasions'] as Map).cast<String, String>();
          expect(evasions.keys.toSet(), {'capture', 'block', 'escape'});
          for (final entry in evasions.entries) {
            final evasion = Move.fromUci(entry.value);
            expect(before.isLegal(evasion), isTrue, reason: entry.key);
            final result = before.copy()..play(evasion);
            expect(
              result.isAttacked(kingSquare(result, Color.white), Color.black),
              isFalse,
              reason: entry.key,
            );
            switch (entry.key) {
              case 'capture':
                expect(
                  before.pieceAt(evasion.to),
                  const Piece(Color.black, PieceType.rook),
                );
                expect(result.pieceAt(evasion.to)?.color, Color.white);
              case 'block':
                expect(evasion.to & 7, 4);
                expect(evasion.to >> 4, inInclusiveRange(1, 6));
                expect(before.pieceAt(evasion.to), isNull);
                expect(result.pieceAt(parseSquare('e8'))?.color, Color.black);
                expect(result.pieceAt(parseSquare('e1'))?.type, PieceType.king);
              case 'escape':
                expect(before.pieceAt(evasion.from)?.type, PieceType.king);
                expect(result.pieceAt(parseSquare('e8'))?.color, Color.black);
            }
          }
          final requiredMethod = switch (level.goal) {
            TutorialGoal.evadeCapture => 'capture',
            TutorialGoal.evadeBlock => 'block',
            _ => 'escape',
          };
          expect(move.uci, evasions[requiredMethod]);
        case TutorialGoal.checkmate:
        case TutorialGoal.mateIn1:
          expect(after.inCheck, isTrue);
          expect(after.legalMoves(), isEmpty);
          expect(after.status, GameStatus.checkmate);
          expect(level.line.length, 1);
        case TutorialGoal.castling:
          expect(after.pieceAt(parseSquare('g1'))?.type, PieceType.king);
          expect(after.pieceAt(parseSquare('f1'))?.type, PieceType.rook);
          expect(after.pieceAt(parseSquare('e1')), isNull);
          expect(after.pieceAt(parseSquare('h1')), isNull);
          expect(before.isLegal(Move.fromUci('e1c1')), isTrue);
        case TutorialGoal.promotion:
          expect(before.pieceAt(move.from)?.type, PieceType.pawn);
          expect(move.promotion, PieceType.queen);
          expect(after.pieceAt(move.to)?.type, PieceType.queen);
          expect(
            before
                .legalMoves()
                .where((m) => m.from == move.from)
                .map((m) => m.promotion)
                .toSet(),
            {
              PieceType.queen,
              PieceType.rook,
              PieceType.bishop,
              PieceType.knight,
            },
          );
        case TutorialGoal.enPassant:
          final setup = Board.fromFen(asset['setupFen'] as String);
          for (final uci in (asset['setupLine'] as List).cast<String>()) {
            final setupMove = Move.fromUci(uci);
            expect(setup.isLegal(setupMove), isTrue);
            setup.play(setupMove);
          }
          expect(setup.toFen(), level.fen);
          expect(before.pieceAt(move.to), isNull);
          expect(before.enPassant, move.to);
          expect(before.pieceAt(parseSquare('d5'))?.type, PieceType.pawn);
          expect(after.pieceAt(parseSquare('d5')), isNull);
          expect(
            after.pieceAt(move.to),
            const Piece(Color.white, PieceType.pawn),
          );
          final delayed = before.copy()
            ..play(Move.fromUci('a1b1'))
            ..play(Move.fromUci('h8g8'));
          expect(delayed.isLegal(move), isFalse);
        case TutorialGoal.stalemateTrap:
          final trap = Move.fromUci(asset['trap'] as String);
          expect(before.isLegal(trap), isTrue);
          final trapped = before.copy()..play(trap);
          expect(trapped.inCheck, isFalse);
          expect(trapped.legalMoves(), isEmpty);
          expect(trapped.status, GameStatus.stalemate);
          expect(after.status, GameStatus.checkmate);
        case TutorialGoal.graduation:
          fail('Graduation handled separately');
      }
    });
  }

  test('castling cannot escape, cross, or land in check', () {
    for (final rank in ['k3r3', 'k4r2', 'k5r1']) {
      final board = Board.fromFen('$rank/8/8/8/8/8/8/4K2R w K - 0 1');
      expect(board.isLegal(Move.fromUci('e1g1')), isFalse);
    }
    final moved = Board.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1');
    expect(moved.isLegal(Move.fromUci('e1g1')), isFalse);
  });

  test('en passant may not expose the king', () {
    final board = Board.fromFen('k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 2');
    expect(board.isLegal(Move.fromUci('e5d6')), isFalse);
  });

  test('pawn cannot move through a piece or capture straight ahead', () {
    final board = Board.fromFen('7k/8/8/8/8/4n3/4P3/K7 w - - 0 1');
    expect(board.isLegal(Move.fromUci('e2e4')), isFalse);
    expect(board.isLegal(Move.fromUci('e2e3')), isFalse);
  });

  test('sliding pieces cannot jump and kings cannot become adjacent', () {
    for (final piece in ['R', 'Q']) {
      final board = Board.fromFen(
        '7k/8/8/3p4/3$piece'
        '4/8/8/K7 w - - 0 1',
      );
      expect(board.isLegal(Move.fromUci('d4d7')), isFalse);
    }
    final bishop = Board.fromFen('k7/8/8/4p3/3B4/8/8/K7 w - - 0 1');
    expect(bishop.isLegal(Move.fromUci('d4g7')), isFalse);
    final kings = Board.fromFen('8/8/8/5k2/3K4/8/8/8 w - - 0 1');
    expect(kings.isLegal(Move.fromUci('d4e4')), isFalse);
  });

  test('malformed text, empty solutions and duplicate IDs are rejected', () {
    expect(
      () => TutorialLevel.fromJson({...assets.first, 'intro': ''}),
      throwsFormatException,
    );
    expect(
      () => TutorialLevel.fromJson({...assets.first, 'line': <String>[]}),
      throwsArgumentError,
    );
    expect(
      () => TutorialLevel.fromJson({
        ...assets.first,
        'line': ['d4d8'],
      }),
      throwsA(isA<IllegalMoveException>()),
    );
    expect(
      () => TutorialCatalog([levels.first, ...levels]),
      throwsFormatException,
    );
  });
}
