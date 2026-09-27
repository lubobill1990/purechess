import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/board.dart';
import '../../core/move.dart';
import '../../core/puzzle.dart';
import 'tutorial_engine.dart';
import 'tutorial_level.dart';

class TutorialController extends ChangeNotifier {
  TutorialController({
    required this.catalog,
    required this.prefs,
    required this.engine,
    Analytics? analytics,
  }) : _analytics = analytics ?? Analytics.instance {
    final stored = prefs.getInt(progressKey) ?? 0;
    if (stored < 0 || stored > catalog.levels.length) {
      throw const FormatException('Invalid tutorial progress');
    }
    completed = stored;
  }

  static const progressKey = 'tutorial_progress';
  final TutorialCatalog catalog;
  final SharedPreferences prefs;
  final Analytics _analytics;
  final TutorialEngine engine;
  TutorialEngine? _fallbackEngine;
  late int completed;
  int? index;
  PuzzleSession? _puzzle;
  Board? _game;
  bool _resigned = false;
  bool _disposed = false;
  int _generation = 0;
  int _attempts = 0;
  Stopwatch _watch = Stopwatch();
  bool thinking = false;
  bool saving = false;
  bool saved = false;
  bool fallback = false;
  bool showHint = false;
  String? message;
  String? aiNotice;

  TutorialLevel get level => catalog.levels[index!];
  Board get board => _game?.copy() ?? _puzzle!.board;
  bool get solved => level.graduation
      ? _resigned || board.status != GameStatus.playing
      : _puzzle!.status == PuzzleStatus.solved;
  bool get failed => _puzzle?.status == PuzzleStatus.failed;
  bool get canPlay => !thinking && !saving && !solved && !failed;
  Move? get hint => showHint ? _puzzle?.hint() : null;
  String get explanation => message ?? (solved ? level.success : level.intro);
  String get outcome => _resigned
      ? '白方认输 · 本局结束'
      : switch (board.status) {
          GameStatus.checkmate =>
            board.turn == Color.black ? '白方获胜 · 将杀' : 'AI 获胜 · 将杀',
          GameStatus.stalemate => '和棋 · 逼和',
          GameStatus.insufficientMaterial => '和棋 · 不足子力',
          GameStatus.fiftyMoveDraw => '和棋 · 50 步规则',
          GameStatus.threefoldRepetition => '和棋 · 三次重复',
          GameStatus.playing => '你执白，请走棋',
        };

  void start(int next) {
    if (saving || thinking) throw StateError('Tutorial is busy');
    if (next < 0 || next >= catalog.levels.length || next > completed) {
      throw StateError('请先完成前面的教程关卡');
    }
    final retrying = index == next;
    _generation++;
    index = next;
    _puzzle = level.graduation ? null : PuzzleSession(level.problem);
    _game = level.graduation ? Board.fromFen(level.fen) : null;
    _resigned = false;
    saved = false;
    message = null;
    showHint = level.guided;
    if (!retrying) {
      _attempts = 0;
      _watch = Stopwatch()..start();
    }
    if (level.graduation) {
      _analytics.event('game_start', {
        'mode': 'tutorial',
        'difficulty': 1,
        'player_color': 'white',
      });
    }
    notifyListeners();
  }

  void revealHint() {
    showHint = true;
    notifyListeners();
  }

  Future<void> play(Move move) async {
    if (!canPlay) return;
    if (!board.isLegal(move)) {
      message = '这步不合法。请选择自己的棋子，并走到合法目标格；被将军时必须先应将。';
      notifyListeners();
      return;
    }
    message = null;
    if (!level.graduation) {
      _attempts++;
      _puzzle!.playUserMove(move);
      if (failed) message = level.failure;
      if (solved || failed) {
        _analytics.event('puzzle_result', {
          'correct': solved,
          'attempts': _attempts,
          'duration_ms': _watch.elapsedMilliseconds,
        });
      }
      notifyListeners();
      if (solved) await saveCompletion();
      return;
    }
    _game!.play(move);
    if (!solved) await _reply();
    if (_disposed) return;
    notifyListeners();
    if (solved) await _finishGame();
  }

  Future<void> _reply() async {
    final generation = _generation;
    thinking = true;
    notifyListeners();
    try {
      Move reply;
      try {
        reply = await (_fallbackEngine ?? engine).chooseMove(board);
        if (!board.isLegal(reply)) {
          throw StateError('AI returned an illegal move');
        }
      } catch (error, stack) {
        if (_disposed || generation != _generation) return;
        reportHandledError('tutorial_ai', error, stack);
        aiNotice = 'AI 暂时不可用，已切换为简易 AI 陪练；本局仍可正常完成。';
        fallback = true;
        _fallbackEngine = FakeEngine();
        await _closeEngine(engine);
        if (_disposed || generation != _generation) return;
        reply = await _fallbackEngine!.chooseMove(board);
      }
      if (_disposed || generation != _generation) return;
      _game!.play(reply);
    } finally {
      if (!_disposed && generation == _generation) {
        thinking = false;
        notifyListeners();
      }
    }
  }

  Future<void> resign() async {
    if (!level.graduation || !canPlay || board.plyCount == 0) return;
    _resigned = true;
    notifyListeners();
    await _finishGame();
  }

  Future<void> _finishGame() async {
    _analytics.event('game_end', {
      'mode': 'tutorial',
      'difficulty': 1,
      'duration_ms': _watch.elapsedMilliseconds,
      'move_count': board.plyCount,
    });
    await saveCompletion();
  }

  Future<void> saveCompletion() async {
    if (!solved || saving || saved) return;
    saving = true;
    message = null;
    notifyListeners();
    try {
      final next = index! + 1;
      if (next > completed) {
        if (!await prefs.setInt(progressKey, next)) {
          throw StateError('Tutorial progress write failed');
        }
        completed = next;
      }
      saved = true;
    } catch (error, stack) {
      reportHandledError('tutorial_progress', error, stack);
      // setInt updates the plugin's cache before the platform write succeeds.
      try {
        await prefs.reload();
      } catch (reloadError, reloadStack) {
        reportHandledError(
          'tutorial_progress_reload',
          reloadError,
          reloadStack,
        );
      }
      message = '进度保存失败，请点「重新保存」。已完成的棋局会保留。';
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_closeEngine(engine));
    final fallbackEngine = _fallbackEngine;
    if (fallbackEngine != null) unawaited(_closeEngine(fallbackEngine));
    super.dispose();
  }

  Future<void> _closeEngine(TutorialEngine engine) async {
    try {
      await engine.dispose();
    } catch (error, stack) {
      reportHandledError('tutorial_ai_close', error, stack);
      aiNotice = 'AI 关闭时出现问题，已停用本次 AI；当前使用简易 AI 陪练。';
    }
  }
}
