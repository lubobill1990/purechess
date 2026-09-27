import 'dart:io';

import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';

/// Chess Programming Wiki standard perft suite.
const perftCases = [
  (
    name: 'startpos',
    fen: Fen.initial,
    counts: [20, 400, 8902, 197281, 4865609],
  ),
  (
    name: 'KiwiPete',
    fen: 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
    counts: [48, 2039, 97862, 4085603],
  ),
  (
    name: 'CPW position 3',
    fen: '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
    counts: [14, 191, 2812, 43238, 674624],
  ),
  (
    name: 'CPW position 4',
    fen: 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
    counts: [6, 264, 9467, 422333],
  ),
  (
    name: 'CPW position 5',
    fen: 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
    counts: [44, 1486, 62379, 2103487],
  ),
  (
    name: 'CPW position 6',
    fen: 'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
    counts: [46, 2079, 89890, 3894594],
  ),
];

void main() {
  final total = Stopwatch()..start();
  for (final entry in perftCases) {
    final board = Board.fromFen(entry.fen);
    for (var depth = 1; depth <= entry.counts.length; depth++) {
      final timer = Stopwatch()..start();
      final nodes = board.perft(depth);
      timer.stop();
      if (nodes != entry.counts[depth - 1] || board.toFen() != entry.fen) {
        throw StateError(
          '${entry.name} d$depth: $nodes; expected '
          '${entry.counts[depth - 1]}; FEN ${board.toFen()}',
        );
      }
      stdout.writeln(
        '${entry.name} d$depth: $nodes '
        '(${timer.elapsedMilliseconds} ms)',
      );
    }
  }
  stdout.writeln('Total: ${total.elapsedMilliseconds} ms');
}
