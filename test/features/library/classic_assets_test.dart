import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/features/library/classic_library.dart';

void main() {
  final source = File(ClassicLibrary.asset).readAsStringSync();
  final scores = source
      .split(RegExp(r'(?=\[Event )'))
      .where((s) => s.trim().isNotEmpty)
      .toList();
  const expectedPlies = [
    33,
    45,
    47,
    56,
    39,
    49,
    33,
    71,
    73,
    38,
    46,
    83,
    57,
    43,
    35,
    67,
    49,
    65,
    75,
    103,
    76,
  ];

  test(
    'catalogue contains 21 distinct pre-1900 games and 105 original notes',
    () {
      final games = ClassicLibrary.parse(source);
      expect(games, hasLength(21));
      expect(games.map((g) => g.id).toSet(), hasLength(21));
      expect(
        games
            .map((g) => g.line.skip(1).map((n) => n.move!.uci).join(' '))
            .toSet(),
        hasLength(21),
      );
      expect(
        games.expand((g) => g.line).expand((n) => n.comments),
        hasLength(105),
      );
      expect(games.map((g) => int.parse(g.year)), everyElement(lessThan(1900)));
      expect(games.map((g) => g.record.result), everyElement(isNot('*')));
      expect(games.map((g) => g.plies), expectedPlies);
    },
  );

  for (var i = 0; i < scores.length; i++) {
    final title = RegExp(r'\[Title "([^"]+)"\]')
        .firstMatch(scores[i])!
        .group(1)!;
    test(
      'asset ${i + 1}: $title — every ply legal, SAN roundtrip and undo',
      () {
        final record = Pgn.parse(scores[i]);
        final board = Board.fromFen(record.initialFen);
        final line = record.mainLine;
        expect(line.length - 1, expectedPlies[i]);
        final notes = line.expand((node) => node.comments).toList();
        expect(notes.length, inInclusiveRange(3, 8));
        expect(notes, everyElement(isNotEmpty));
        expect(record.tags['Source'], startsWith('https://'));
        for (var ply = 1; ply < line.length; ply++) {
          final move = line[ply].move!;
          expect(board.isLegal(move), isTrue, reason: '$title ply $ply');
          final san = board.san(move);
          expect(board.parseSan(san), move, reason: '$title ply $ply SAN $san');
          board.play(move);
        }
        final regenerated = Pgn.parse(Pgn.generate(record));
        expect(
          regenerated.boardAt(regenerated.mainLine.last).toFen(),
          board.toFen(),
        );
        expect(regenerated.mainLine.expand((n) => n.comments), notes);
        for (var ply = 1; ply < line.length; ply++) {
          board.undo();
        }
        expect(board.toFen(), record.initialFen);
      },
    );
  }

  test('famous mating finishes are mate, not merely valid move sequences', () {
    final games = ClassicLibrary.parse(source);
    for (final id in [
      'opera-1858',
      'immortal-1851',
      'evergreen-1852',
      'rosanes-anderssen-1863',
      'steinitz-rock-1863',
      'steinitz-mongredien-1862',
      'pillsbury-tarrasch-1895',
    ]) {
      final game = games.singleWhere((g) => g.id == id);
      expect(
        game.record.boardAt(game.line.last).status,
        GameStatus.checkmate,
        reason: id,
      );
    }
  });

  test(
    'Capablanca queen odds uses declared FEN; standard games use startpos',
    () {
      final games = ClassicLibrary.parse(source);
      final capablanca = games.last;
      expect(capablanca.id, 'iglesias-capablanca-1893');
      expect(capablanca.record.tags['SetUp'], '1');
      expect(
        capablanca.record.initialFen,
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1',
      );
      expect(
        games.take(20).map((g) => g.record.initialFen),
        everyElement(Fen.initial),
      );
    },
  );

  test(
    'empty, missing metadata, duplicate IDs and modern scores fail explicitly',
    () {
      expect(() => ClassicLibrary.parse(''), throwsFormatException);
      expect(
        () => ClassicLibrary.parse(
          scores.first.replaceFirst('[Id "opera-1858"]', ''),
        ),
        throwsFormatException,
      );
      expect(
        () => ClassicLibrary.parse('${scores.first}\n${scores.first}'),
        throwsFormatException,
      );
      expect(
        () => ClassicLibrary.parse(
          scores.first.replaceFirst('1858.??.??', '1900.01.01'),
        ),
        throwsFormatException,
      );
    },
  );

  test('bundled asset loader uses the same validated catalogue', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final games = await ClassicLibrary.load();
    expect(games, hasLength(21));
    expect(games.first.id, 'opera-1858');
  });
}
