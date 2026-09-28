import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart';
import '../../engine/stockfish_service.dart';
import '../achievements/achievements.dart';
import 'ai_difficulty.dart';
import 'game_session.dart';

enum GamePhase { playing, thinking, hinting, cancelling, finished, failed }

class GameController extends ChangeNotifier {
  GameController({
    required this.config,
    required this.engine,
    required this.rating,
    GameSession? session,
    Analytics? analytics,
  }) : session = session ?? GameSession(humanColor: config.humanColor),
       analytics = analytics ?? Analytics.instance {
    _achievementRecorded = this.session.finished;
    engine.status.addListener(_engineChanged);
  }

  final AiGameConfig config;
  final StockfishService engine;
  final AiDifficulty rating;
  final Analytics analytics;
  final GameSession session;
  GamePhase phase = GamePhase.playing;
  String? error;
  String? ratingError;
  Move? hint;
  bool ratingSaving = false;
  bool _recorded = false;
  bool _started = false;
  bool _ended = false;
  bool _disposed = false;
  bool _achievementRecorded = false;
  int _generation = 0;

  bool get busy =>
      phase == GamePhase.thinking ||
      phase == GamePhase.hinting ||
      phase == GamePhase.cancelling;
  bool get humanTurn =>
      !session.finished &&
      !busy &&
      error == null &&
      session.turn == config.humanColor;
  bool get canUndo =>
      !session.finished &&
      phase != GamePhase.cancelling &&
      session.moveCount > (config.humanColor == Color.black ? 1 : 0);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _engineChanged() {
    if (session.finished) return;
    final failure = engine.status.value.error;
    if (!_disposed && failure != null && phase != GamePhase.cancelling) {
      error = failure.message;
      if (!busy && !session.finished) phase = GamePhase.failed;
      _notify();
    }
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    analytics.event('game_start', {
      'mode': 'ai',
      'difficulty': config.difficulty,
      'player_color': config.humanColor.name,
    });
    await _continueGame();
  }

  Future<void> play(Move move) async {
    if (!humanTurn) throw StateError('Not the human turn');
    session.play(move);
    hint = null;
    _notify();
    await _continueGame();
  }

  Future<void> _continueGame() async {
    if (_disposed) return;
    if (session.finished) {
      phase = GamePhase.finished;
      _notify();
      if (!_ended) {
        _ended = true;
        analytics.event('game_end', {
          'mode': 'ai',
          'difficulty': config.difficulty,
          'move_count': session.moveCount,
          'duration_ms': DateTime.now()
              .difference(session.startedAt)
              .inMilliseconds,
        });
      }
      await saveAchievement();
      await saveRating();
    } else if (session.turn != config.humanColor) {
      await _search(forHint: false);
    } else {
      phase = GamePhase.playing;
      _notify();
    }
  }

  Future<void> requestHint() async {
    if (!humanTurn) throw StateError('Hint requires the human turn');
    await _search(forHint: true);
  }

  Future<void> _search({required bool forHint}) async {
    final generation = ++_generation;
    phase = forHint ? GamePhase.hinting : GamePhase.thinking;
    error = null;
    hint = null;
    _notify();
    try {
      final result = await engine.analyzePosition(
        session.board.toFen(),
        difficulty: forHint ? 10 : config.difficulty,
        depth: forHint ? 12 : null,
      );
      if (_disposed || generation != _generation) return;
      final uci = forHint && result.bestLine.isNotEmpty
          ? result.bestLine.first
          : result.bestMove;
      if (uci == null) throw StateError('AI did not return a move');
      final move = Move.fromUci(uci);
      if (!session.board.isLegal(move)) {
        throw StateError('AI returned an illegal move');
      }
      phase = GamePhase.playing;
      if (forHint) {
        hint = move;
        _notify();
      } else {
        session.play(move);
        await _continueGame();
      }
    } catch (cause, stack) {
      if (_disposed || generation != _generation) return;
      reportHandledError('game_ai', cause, stack);
      error = cause is StockfishException ? cause.message : 'AI 未能完成这一步，请重试';
      phase = GamePhase.failed;
      _notify();
    }
  }

  Future<void> retry() async {
    if (busy || _disposed) return;
    error = null;
    phase = session.finished ? GamePhase.finished : GamePhase.playing;
    if (session.finished || session.turn == config.humanColor) {
      // Restart even on a human turn so an idle AI failure is not just hidden.
      phase = GamePhase.thinking;
      _notify();
      final generation = ++_generation;
      try {
        await engine.ensureStarted();
        if (_disposed || generation != _generation) return;
        phase = session.finished ? GamePhase.finished : GamePhase.playing;
      } catch (cause, stack) {
        if (_disposed || generation != _generation) return;
        reportHandledError('game_ai_retry', cause, stack);
        error = cause is StockfishException ? cause.message : 'AI 暂时不可用，请重试';
        phase = GamePhase.failed;
      }
      _notify();
    } else {
      await _continueGame();
    }
  }

  Future<bool> _cancelSearch() async {
    ++_generation;
    phase = GamePhase.cancelling;
    hint = null;
    _notify();
    try {
      await engine.stop();
      if (_disposed) return false;
      error = null;
      return true;
    } catch (cause, stack) {
      if (_disposed) return false;
      reportHandledError('game_ai_stop', cause, stack);
      error = 'AI 未能停止，请重新打开应用';
      phase = GamePhase.failed;
      _notify();
      return false;
    }
  }

  /// Remove the human move and its reply, or just the human move if AI is busy.
  Future<void> undo() async {
    if (!canUndo) throw StateError('No human move to undo');
    if (!await _cancelSearch()) return;
    session.undo();
    if (session.turn != config.humanColor && session.canUndo) session.undo();
    phase = GamePhase.playing;
    _notify();
  }

  Future<void> resign() async {
    if (session.finished || phase == GamePhase.cancelling) return;
    if (!await _cancelSearch()) return;
    session.resign(config.humanColor, requireTurn: false);
    await _continueGame();
  }

  Future<void> saveRating() async {
    if (!session.finished || _recorded || ratingSaving || _disposed) return;
    ratingSaving = true;
    ratingError = null;
    _notify();
    try {
      final winner = session.outcome!.winner;
      await rating.recordResult(
        config.difficulty,
        won: winner == null ? null : winner == config.humanColor,
      );
      _recorded = true;
    } catch (cause, stack) {
      reportHandledError('game_rating', cause, stack);
      ratingError = '推荐难度未保存，请重试';
    } finally {
      ratingSaving = false;
      _notify();
    }
  }

  String? achievementError;
  bool achievementSaving = false;

  Future<void> saveAchievement() async {
    if (!session.finished || _achievementRecorded || achievementSaving) return;
    achievementSaving = true;
    achievementError = null;
    _notify();
    try {
      await Achievements.of(rating.prefs).record(
        ActivityEvent.gameFinished(
          won: session.outcome!.winner == config.humanColor,
        ),
        analytics: analytics,
      );
      _achievementRecorded = true;
    } catch (cause, stack) {
      reportHandledError('game_achievement', cause, stack);
      achievementError = '成就未保存，请重试';
    } finally {
      achievementSaving = false;
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
