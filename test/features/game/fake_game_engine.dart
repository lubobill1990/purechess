import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/engine/uci_protocol.dart';

class FakeGameEngine extends StockfishService {
  final changes = ValueNotifier(const StockfishStatus(StockfishState.ready));
  final replies = Queue<Future<PositionAnalysis> Function(String)>();
  final requests = <({String fen, int difficulty, int? depth})>[];
  Object? startError;
  Object? stopError;
  int starts = 0;
  int stops = 0;
  int disposals = 0;

  @override
  ValueListenable<StockfishStatus> get status => changes;

  void failIdle() => changes.value = const StockfishStatus(
    StockfishState.failed,
    error: StockfishException('AI 意外退出，请重试'),
  );

  @override
  Future<void> ensureStarted() async {
    starts++;
    if (startError != null) throw startError!;
    changes.value = const StockfishStatus(StockfishState.ready);
  }

  @override
  Future<PositionAnalysis> analyzePosition(
    String fen, {
    int difficulty = 5,
    int? depth,
  }) async {
    requests.add((fen: fen, difficulty: difficulty, depth: depth));
    if (replies.isNotEmpty) return replies.removeFirst()(fen);
    final board = Board.fromFen(fen);
    final moves = board.legalMoves();
    return result(moves.isEmpty ? null : moves.first.uci);
  }

  static PositionAnalysis result(String? move, {int cp = 0, int? mate}) =>
      PositionAnalysis(
        score: mate == null
            ? UciScore(UciScoreKind.cp, cp)
            : UciScore(UciScoreKind.mate, mate),
        bestMove: move,
        bestLine: [?move],
        depth: 12,
      );

  @override
  Future<void> stop() async {
    stops++;
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    changes.dispose();
  }
}
