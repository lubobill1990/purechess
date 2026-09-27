import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../app/telemetry/crash_guard.dart';
import '../../core/board.dart';
import '../../core/game_tree.dart';
import '../../core/move.dart';
import '../../core/pgn.dart';
import '../../engine/stockfish_service.dart';
import '../../engine/uci_protocol.dart';

class ReviewEvaluation {
  const ReviewEvaluation({this.whiteCp, this.whiteMate})
    : assert((whiteCp == null) != (whiteMate == null));

  factory ReviewEvaluation.fromAnalysis(PositionAnalysis result, Color turn) {
    if (result.score.bound != UciScoreBound.exact) {
      throw ArgumentError('Review requires an exact evaluation');
    }
    return result.cp != null
        ? ReviewEvaluation(whiteCp: result.cp! * turn.sign)
        : ReviewEvaluation(whiteMate: result.mate! * turn.sign);
  }

  final int? whiteCp;
  final int? whiteMate;
}

class ReviewMistake {
  const ReviewMistake({required this.ply, required this.loss});
  final int ply;
  final int loss;
}

/// White-relative exact evaluations, including position zero. Mate transitions
/// are gaps, not invented centipawns. Both adjacent scores are required.
List<int?> reviewLosses(
  List<ReviewEvaluation?> evaluations, {
  Color initialTurn = Color.white,
}) {
  return List.unmodifiable([
    for (var ply = 1; ply < evaluations.length; ply++)
      if (evaluations[ply - 1]?.whiteCp case final int before)
        if (evaluations[ply]?.whiteCp case final int after)
          math.max(
            0,
            (before - after) *
                (ply.isOdd ? initialTurn.sign : -initialTurn.sign),
          )
        else
          null
      else
        null,
  ]);
}

List<ReviewMistake> selectReviewMistakes(
  List<ReviewEvaluation?> evaluations, {
  Color initialTurn = Color.white,
}) {
  final losses = reviewLosses(evaluations, initialTurn: initialTurn);
  final mistakes =
      [
        for (var i = 0; i < losses.length; i++)
          if (losses[i] != null && losses[i]! > 0)
            ReviewMistake(ply: i + 1, loss: losses[i]!),
      ]..sort((a, b) {
        final order = b.loss.compareTo(a.loss);
        return order == 0 ? a.ply.compareTo(b.ply) : order;
      });
  return List.unmodifiable(mistakes.take(3));
}

class ReviewController extends ChangeNotifier {
  ReviewController({required GameRecord record, required this.engine})
    : record = Pgn.parse(Pgn.generate(record)) {
    line = this.record.mainLine;
    _evaluations = List.filled(line.length, null);
    engine.status.addListener(_engineChanged);
  }

  final GameRecord record;
  final StockfishService engine;
  late final List<GameNode> line;
  late final List<ReviewEvaluation?> _evaluations;
  bool running = false;
  bool cancelling = false;
  bool _disposed = false;
  int _generation = 0;
  int selectedPly = 0;
  String? error;

  List<ReviewEvaluation?> get evaluations => List.unmodifiable(_evaluations);
  Color get initialTurn => Board.fromFen(record.initialFen).turn;
  List<int?> get losses => reviewLosses(evaluations, initialTurn: initialTurn);
  List<ReviewMistake> get mistakes =>
      selectReviewMistakes(evaluations, initialTurn: initialTurn);
  int get completed => _evaluations.whereType<ReviewEvaluation>().length;
  Board get board => record.boardAt(line[selectedPly]);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _engineChanged() {
    final failure = engine.status.value.error;
    if (!cancelling && failure != null) {
      error = failure.message;
      _notify();
    }
  }

  void select(int ply) {
    RangeError.checkValidIndex(ply, line, 'ply');
    selectedPly = ply;
    _notify();
  }

  Future<void> run() async {
    if (running || cancelling || _disposed) return;
    final generation = ++_generation;
    running = true;
    error = null;
    _notify();
    try {
      for (var i = 0; i < line.length; i++) {
        if (_evaluations[i] != null) continue;
        final position = record.boardAt(line[i]);
        // Rule-adjudicated draws retain their actual result, even if the
        // position-only AI request cannot know the repetition history.
        if (position.status != GameStatus.playing &&
            position.status != GameStatus.checkmate) {
          _evaluations[i] = const ReviewEvaluation(whiteCp: 0);
        } else {
          final result = await engine.analyzePosition(
            position.toFen(),
            difficulty: 10,
            depth: 12,
          );
          if (_disposed || generation != _generation) return;
          _evaluations[i] = ReviewEvaluation.fromAnalysis(
            result,
            position.turn,
          );
        }
        _notify();
      }
    } catch (cause, stack) {
      if (_disposed || generation != _generation) return;
      reportHandledError('game_review', cause, stack);
      error = cause is StockfishException ? cause.message : '本局分析未完成，请重试';
    } finally {
      if (!_disposed && generation == _generation) {
        running = false;
        _notify();
      }
    }
  }

  Future<void> cancel() async {
    if (cancelling || !running) return;
    ++_generation;
    cancelling = true;
    _notify();
    try {
      await engine.stop();
      error = '复盘已暂停，可继续分析';
    } catch (cause, stack) {
      reportHandledError('review_stop', cause, stack);
      error = 'AI 未能停止，请重新打开应用';
    } finally {
      cancelling = false;
      running = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    engine.status.removeListener(_engineChanged);
    super.dispose();
  }
}
