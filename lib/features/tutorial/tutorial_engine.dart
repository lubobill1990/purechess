import 'dart:math';

import '../../core/board.dart';
import '../../core/move.dart';
import '../../engine/stockfish_service.dart';

abstract interface class TutorialEngine {
  Future<Move> chooseMove(Board board);
  Future<void> dispose();
}

class TutorialAi implements TutorialEngine {
  TutorialAi(this.service);
  final StockfishService service;

  @override
  Future<Move> chooseMove(Board board) async {
    final result = await service.analyzePosition(board.toFen(), difficulty: 1);
    final uci = result.bestMove;
    if (uci == null) throw const StockfishException('AI 没有返回可用着法');
    return Move.fromUci(uci);
  }

  @override
  Future<void> dispose() => service.dispose();
}

/// Deliberately weak, offline opponent; never claims to be the full AI.
class FakeEngine implements TutorialEngine {
  FakeEngine({Random? random}) : _random = random ?? Random();
  final Random _random;

  @override
  Future<Move> chooseMove(Board board) async {
    final moves = board.legalMoves();
    if (moves.isEmpty) throw StateError('No legal AI move');
    return moves[_random.nextInt(moves.length)];
  }

  @override
  Future<void> dispose() async {}
}
