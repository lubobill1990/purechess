import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/puzzle.dart';
import 'package:purechess/features/puzzle/puzzle_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final directory = Directory('assets${Platform.pathSeparator}puzzles');
  final manifest = jsonDecode(
    File('${directory.path}${Platform.pathSeparator}manifest.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final packs = manifest['packs'] as List<dynamic>;
  final ids = <String>{};
  var count = 0;

  for (final item in packs) {
    final pack = item as Map<String, dynamic>;
    final rows = jsonDecode(
      File('${directory.path}${Platform.pathSeparator}${pack['file']}')
          .readAsStringSync(),
    ) as List<dynamic>;
    test('pack ${pack['file']} has the expected quota', () {
      expect(rows.length, pack['count']);
      expect(rows.length, greaterThanOrEqualTo(50));
    });
    for (final row in rows) {
      final data = row as Map<String, dynamic>;
      final id = data['id'] as String;
      count++;
      final unique = ids.add(id);
      test(
        'asset $id: valid FEN, legal full line, intended terminal position',
        () {
          expect(unique, isTrue, reason: 'IDs must not repeat across packs');
          final fen = data['fen'] as String;
          final board = Board.fromFen(fen);
          expect(Board.fromFen(board.toFen()).toFen(), fen);
          final solver = board.turn;
          for (final color in Color.values) {
            var kings = 0;
            for (var rank = 0; rank < 8; rank++) {
              for (var file = 0; file < 8; file++) {
                final piece = board.pieceAt(rank * 16 + file);
                if (piece == Piece(color, PieceType.king)) kings++;
                if (rank == 0 || rank == 7) {
                  expect(piece?.type, isNot(PieceType.pawn));
                }
              }
            }
            expect(kings, 1);
          }
          final themes = (data['themes'] as List<dynamic>).cast<String>();
          final line = (data['line'] as List<dynamic>).cast<String>();
          expect(themes, contains(pack['theme']));
          expect(
            ratingInBand(data['rating'] as int, pack['band'] as String),
            isTrue,
          );
          expect(
            line.length.isOdd,
            isTrue,
            reason: 'Last move belongs to solver',
          );
          for (final uci in line) {
            final move = Move.fromUci(uci);
            expect(board.isLegal(move), isTrue, reason: '$id at $uci');
            board.play(move);
            expect(Board.fromFen(board.toFen()).toFen(), board.toFen());
          }
          expect(board.turn, solver.opponent);
          expect(board.status, isNot(GameStatus.stalemate));
          if (themes.contains('mate') ||
              themes.contains('mateIn1') ||
              themes.contains('mateIn2') ||
              themes.contains('backRankMate')) {
            expect(board.status, GameStatus.checkmate);
            expect(board.winner, solver);
          }
          if (themes.contains('mateIn1')) expect(line.length, 1);
          if (themes.contains('mateIn2')) expect(line.length, 3);
          final session = PuzzleSession(
            PuzzleProblem(
              id: id,
              fen: fen,
              line: line.map(Move.fromUci).toList(),
              themes: themes,
              rating: data['rating'] as int,
            ),
          );
          for (var index = 0; index < line.length; index += 2) {
            session.playUserMove(Move.fromUci(line[index]));
          }
          expect(session.status, PuzzleStatus.solved);
          expect(session.board.toFen(), board.toFen());
        },
      );
    }
  }
  test('catalog contains >=1000 unique puzzles in every requested stratum', () {
    expect(count, manifest['total']);
    expect(ids.length, count);
    expect(count, greaterThanOrEqualTo(1000));
    expect(packs.map((entry) => '${entry['theme']}/${entry['band']}').toSet(), {
      for (final theme in puzzleThemes.keys)
        for (final band in puzzleBands.keys) '$theme/$band',
    });
  });
  test('Flutter bundle includes and loads every puzzle asset', () async {
    final catalog = await PuzzleCatalog.load();
    expect(catalog.byId.length, count);
    expect(catalog.packs.length, 21);
  });
}
