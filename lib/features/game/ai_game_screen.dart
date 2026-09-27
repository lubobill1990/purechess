import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart' as chess;
import '../../engine/stockfish_service.dart';
import '../../widgets/board/chess_board.dart';
import '../library/records_repository.dart';
import 'ai_difficulty.dart';
import 'game_controller.dart';
import 'game_session.dart';
import 'new_game_screen.dart';
import 'review_screen.dart';

class AiGameScreen extends StatefulWidget {
  const AiGameScreen({
    super.key,
    required this.config,
    required this.rating,
    this.engine,
    this.session,
    this.analytics,
    this.openRepository = RecordsRepository.open,
  });

  final AiGameConfig config;
  final AiDifficulty rating;
  final StockfishService? engine;
  final GameSession? session;
  final Analytics? analytics;
  final Future<RecordsRepository> Function() openRepository;

  @override
  State<AiGameScreen> createState() => _AiGameScreenState();
}

class _AiGameScreenState extends State<AiGameScreen> {
  late final StockfishService _engine;
  late final GameController _game;
  late bool _flipped;
  bool _saving = false;
  bool _reviewing = false;
  int _savedRevision = -1;
  String? _saveMessage;

  bool get _dirty =>
      (_game.session.moveCount > 0 || _game.session.finished) &&
      _savedRevision != _game.session.revision;

  @override
  void initState() {
    super.initState();
    _flipped = widget.config.humanColor == chess.Color.black;
    _engine =
        widget.engine ??
        StockfishService(
          analytics: widget.analytics,
          prefs: widget.rating.prefs,
        );
    _game = GameController(
      config: widget.config,
      rating: widget.rating,
      engine: _engine,
      session: widget.session,
      analytics: widget.analytics,
    )..addListener(_changed);
    unawaited(_game.start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _closeEngine() async {
    try {
      await _engine.dispose();
    } catch (error, stack) {
      reportHandledError('game_dispose', error, stack);
    }
  }

  @override
  void dispose() {
    _game.removeListener(_changed);
    _game.dispose();
    unawaited(_closeEngine());
    super.dispose();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _leave() async {
    if (_saving || _game.ratingSaving) return;
    if (await _confirm('离开对局', '本局尚未保存，放弃本局并离开？', '放弃并离开') && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _newGame() async {
    if (_dirty && !await _confirm('开始新对局', '本局尚未保存，放弃本局并重新开始？', '重新开始')) {
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NewGameScreen(
          prefs: widget.rating.prefs,
          analytics: widget.analytics,
        ),
      ),
    );
  }

  Future<void> _resign() async {
    if (await _confirm('认输', '确认认输并结束本局？', '确认认输') && mounted) {
      await _game.resign();
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    final revision = _game.session.revision;
    try {
      final snapshot = _game.session.snapshot();
      final repository = await widget.openRepository();
      await repository.save(snapshot);
      if (mounted) {
        setState(() {
          _savedRevision = revision;
          _saveMessage = '已保存到我的棋谱';
        });
      }
    } catch (error, stack) {
      reportHandledError('save_ai_game', error, stack);
      if (mounted) setState(() => _saveMessage = '棋谱保存失败，请检查存储空间后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _review() async {
    setState(() => _reviewing = true);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ReviewScreen(record: _game.session.snapshot(), engine: _engine),
      ),
    );
    if (mounted) setState(() => _reviewing = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = _game.session;
    final board = session.board;
    final hint = _game.hint;
    final status =
        session.outcome?.message ??
        switch (_game.phase) {
          GamePhase.thinking => 'AI 正在思考…',
          GamePhase.hinting => '正在寻找提示…',
          GamePhase.cancelling => '正在停止思考…',
          GamePhase.failed => '对弈已暂停',
          _ =>
            hint != null
                ? '建议 ${chess.squareName(hint.from)} → ${chess.squareName(hint.to)}'
                      '${hint.promotion != null ? ' · 升变 ${board.san(hint)}' : ''}'
                : '轮到你走棋${board.inCheck ? ' · 将军，请应将' : ''}',
        };
    final locked = _saving || _reviewing || _game.ratingSaving;
    return PopScope(
      canPop: !_dirty && !locked,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('AI 对弈 · 第 ${widget.config.difficulty} 档'),
          actions: [
            IconButton(
              tooltip: '翻转棋盘',
              onPressed: () => setState(() => _flipped = !_flipped),
              icon: const Icon(Icons.flip_camera_android_outlined),
            ),
            IconButton(
              tooltip: '新对局',
              onPressed: locked ? null : _newGame,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(constraints.maxWidth, 640.0);
              final size = math.min(
                width - 24,
                math.max(120.0, constraints.maxHeight - 260),
              );
              return SingleChildScrollView(
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 36,
                          child: Center(
                            child: Text(
                              '你执${widget.config.humanColor == chess.Color.white ? '白棋 · 先走' : '黑棋 · 后走'}',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: size,
                          height: size,
                          child: ChessBoard(
                            board: board,
                            flipped: _flipped,
                            enabled: _game.humanTurn && !locked,
                            onMove: (move) {
                              _saveMessage = null;
                              unawaited(_game.play(move));
                            },
                          ),
                        ),
                        SizedBox(
                          key: const ValueKey('ai-result-area'),
                          height: 112,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Semantics(
                              liveRegion: true,
                              child: Column(
                                children: [
                                  Text(status, textAlign: TextAlign.center),
                                  if (_saveMessage != null) Text(_saveMessage!),
                                  if (_game.error != null) ...[
                                    Text(
                                      _game.error!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _game.busy || locked
                                          ? null
                                          : _game.retry,
                                      child: const Text('重试 AI'),
                                    ),
                                  ],
                                  if (_game.ratingError != null) ...[
                                    Text(_game.ratingError!),
                                    TextButton(
                                      onPressed: _game.ratingSaving
                                          ? null
                                          : _game.saveRating,
                                      child: const Text('重试保存推荐'),
                                    ),
                                  ],
                                  if (session.finished &&
                                      _game.ratingError == null)
                                    Text(
                                      _game.ratingSaving
                                          ? '正在保存推荐难度…'
                                          : '下局推荐第 ${widget.rating.recommended} 档',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _game.humanTurn && !locked
                                  ? _game.requestHint
                                  : null,
                              icon: const Icon(Icons.lightbulb_outline),
                              label: const Text('提示'),
                            ),
                            TextButton.icon(
                              onPressed: _game.canUndo && !locked
                                  ? () {
                                      _saveMessage = null;
                                      unawaited(_game.undo());
                                    }
                                  : null,
                              icon: const Icon(Icons.undo),
                              label: const Text('悔棋'),
                            ),
                            TextButton(
                              onPressed:
                                  session.finished ||
                                      locked ||
                                      _game.phase == GamePhase.cancelling
                                  ? null
                                  : _resign,
                              child: const Text('认输'),
                            ),
                          ],
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: locked || !_dirty ? null : _save,
                              icon: const Icon(Icons.save_outlined),
                              label: Text(_saving ? '正在保存…' : '保存棋谱'),
                            ),
                            FilledButton.icon(
                              onPressed:
                                  session.finished && !locked && !_game.busy
                                  ? _review
                                  : null,
                              icon: const Icon(Icons.query_stats),
                              label: const Text('一键复盘'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
