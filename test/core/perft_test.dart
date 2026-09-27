import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';

import '../../tool/perft.dart';

void main() {
  for (final entry in perftCases) {
    for (var depth = 1; depth <= entry.counts.length; depth++) {
      test('${entry.name} perft depth $depth', () {
        final board = Board.fromFen(entry.fen);
        final key = board.zobristHash;
        expect(board.perft(depth), entry.counts[depth - 1]);
        expect(board.toFen(), entry.fen);
        expect(board.zobristHash, key);
        expect(board.plyCount, 0);
        expect(board.repetitionCount, 1);
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  }
}
