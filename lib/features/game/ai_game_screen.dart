import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/play_feedback.dart';
import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart' as chess;
import '../../engine/stockfish_service.dart';
import '../../widgets/board/chess_board.dart';
import '../../widgets/board/board_panel.dart';
import '../library/records_repository.dart';
import 'ai_difficulty.dart';
import 'game_controller.dart';
import 'game_persistence.dart';
import 'game_rail.dart';
import 'game_fullscreen.dart';
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
    this.gameStore,
    this.resumed = false,
    this.openRepository = RecordsRepository.open,
  });

  final AiGameConfig config;
  final AiDifficulty rating;
  final StockfishService? engine;
  final GameSession? session;
  final Analytics? analytics;
  final GameStore? gameStore;
  final bool resumed;
  final Future<RecordsRepository> Function() openRepository;

  @override
  State<AiGameScreen> createState() => _AiGameScreenState();
}

class _AiGameScreenState extends State<AiGameScreen> {
  late final StockfishService _engine;
  late final GameController _game;
  late final GamePersistence _persistence;
  GameStore? _ownedStore;
  Future<void>? _closingEngine;
  late bool _flipped;
  bool _saving = false;
  bool _reviewing = false;
  bool _navigating = false;
  bool _controllerDisposed = false;
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
      resumed: widget.resumed,
    );
    final prefs = widget.rating.prefs;
    if (widget.gameStore == null && prefs != null) {
      _ownedStore = GameStore(prefs);
    }
    _persistence = GamePersistence(
      store: widget.gameStore ?? _ownedStore,
      session: () => _game.session,
      config: widget.config,
    );
    _game.addListener(_changed);
    unawaited(_game.start());
  }

  void _changed() {
    _persistence.save();
    if (mounted) setState(() {});
  }

  Future<void> _closeEngine() => _closingEngine ??= _disposeEngine();

  Future<void> _disposeEngine() async {
    try {
      await _engine.dispose();
    } catch (error, stack) {
      reportHandledError('game_dispose', error, stack);
    }
  }

  @override
  void dispose() {
    _disposeController();
    unawaited(_persistence.close());
    _ownedStore?.dispose();
    unawaited(_closeEngine());
    super.dispose();
  }

  void _disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    _game.removeListener(_changed);
    _game.dispose();
  }

  Future<bool> _confirm(
    String title,
    String message,
    String action, {
    bool allowResume = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            if (allowResume && _persistence.store != null)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context, false);
                  await _exit();
                },
                child: const Text('稍后继续'),
              ),
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
    if (_saving ||
        _reviewing ||
        _game.ratingSaving ||
        _game.achievementSaving ||
        _navigating) {
      return;
    }
    if (!_dirty) {
      await _exit();
      return;
    }
    if (await _confirm(
      '离开对局',
      '可稍后继续本局，或放弃本局并离开。棋谱需另行保存。',
      '放弃并离开',
      allowResume: !_game.session.finished,
    )) {
      await _exit(abandon: true);
    }
  }

  Future<void> _exit({bool abandon = false}) async {
    if (!mounted || _navigating) return;
    setState(() => _navigating = true);
    _disposeController();
    await _persistence.close(abandon: abandon);
    await _closeEngine();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _newGame() async {
    if (_navigating) return;
    final rematch = _game.session.finished;
    if (!rematch &&
        _dirty &&
        !await _confirm('开始新对局', '本局尚未保存，放弃本局并重新开始？', '重新开始')) {
      return;
    }
    if (!mounted || _navigating) return;
    setState(() => _navigating = true);
    _disposeController();
    await _persistence.close(abandon: true);
    await _closeEngine();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => rematch
            ? AiGameScreen(
                config: widget.config,
                rating: widget.rating,
                analytics: widget.analytics,
                gameStore: widget.gameStore,
                openRepository: widget.openRepository,
              )
            : NewGameScreen(
                prefs: widget.rating.prefs,
                analytics: widget.analytics,
                gameStore: widget.gameStore,
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
    final locked =
        _saving ||
        _reviewing ||
        _game.ratingSaving ||
        _game.achievementSaving ||
        _navigating;
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 21;
    final title =
        '第 ${widget.config.difficulty} 档 · 你执${widget.config.humanColor == chess.Color.white ? '白棋' : '黑棋'}';
    GameRail navigation(bool landscape) => GameRail(
      landscape: landscape,
      title: title,
      onLeave: _leave,
      onFlip: () => setState(() => _flipped = !_flipped),
      onNewGame: locked ? null : _newGame,
      finished: session.finished,
      actions: [
        if (compact)
          GameMenuItem(
            value: _save,
            enabled: !locked && _dirty,
            child: Text(_saving ? '正在保存…' : '保存棋谱'),
          ),
        if (compact)
          GameMenuItem(
            value: _review,
            enabled: session.finished && !locked && !_game.busy,
            child: const Text('一键复盘'),
          ),
      ],
    );
    return GameFullscreen(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          backgroundColor: boardTableColor(context),
          body: PlayFeedback(
            session: session,
            board: board,
            source: 'ai',
            prefs: widget.rating.prefs,
            analytics: widget.analytics,
            result: !session.finished
                ? FeedbackResult.playing
                : session.outcome!.winner == null
                ? FeedbackResult.draw
                : session.outcome!.winner == widget.config.humanColor
                ? FeedbackResult.win
                : FeedbackResult.loss,
            celebration: session.outcome?.winner == widget.config.humanColor
                ? '你赢了！'
                : null,
            child: SafeArea(
              child: BoardPanel(
                minimumSidebarWidth: 320,
                navigationBuilder: navigation,
                above: BoardRail(
                  height: 48,
                  emphasized: _game.humanTurn,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Semantics(
                          liveRegion: true,
                          child: Text(session.finished ? title : status),
                        ),
                      ),
                    ),
                  ),
                ),
                board: ChessBoard(
                  board: board,
                  flipped: _flipped,
                  enabled: _game.humanTurn && !locked,
                  onMove: (move) {
                    _saveMessage = null;
                    unawaited(_game.play(move));
                  },
                ),
                below: BoardRail(
                  emphasized: true,
                  child: SizedBox(
                    key: const ValueKey('ai-result-area'),
                    height: 72,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Semantics(
                            liveRegion: true,
                            child: Column(
                              children: [
                                if (session.finished)
                                  Text(status, textAlign: TextAlign.center),
                                if (_saveMessage != null) Text(_saveMessage!),
                                if (_game.achievementError != null) ...[
                                  Text(_game.achievementError!),
                                  TextButton(
                                    onPressed: _game.achievementSaving
                                        ? null
                                        : _game.saveAchievement,
                                    child: const Text('重试保存成就'),
                                  ),
                                ],
                                if (_game.error != null) ...[
                                  Text(
                                    _game.error!,
                                    style: const TextStyle(
                                      color: BoardPainter.ivory,
                                      fontWeight: FontWeight.w600,
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
                    ),
                  ),
                ),
                controls: SizedBox(
                  height: compact ? 56 : 112,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GameActionChip(
                                onPressed: _game.humanTurn && !locked
                                    ? _game.requestHint
                                    : null,
                                icon: Icons.lightbulb_outline,
                                label: '提示',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GameActionChip(
                                onPressed: _game.canUndo && !locked
                                    ? () {
                                        _saveMessage = null;
                                        unawaited(_game.undo());
                                      }
                                    : null,
                                icon: Icons.undo,
                                label: '悔棋',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GameActionChip(
                                onPressed:
                                    session.finished ||
                                        locked ||
                                        _game.phase == GamePhase.cancelling
                                    ? null
                                    : _resign,
                                label: '认输',
                              ),
                            ),
                          ],
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GameActionChip(
                                  onPressed: locked || !_dirty ? null : _save,
                                  icon: Icons.save_outlined,
                                  label: _saving ? '正在保存…' : '保存棋谱',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GameActionChip(
                                  onPressed:
                                      session.finished && !locked && !_game.busy
                                      ? _newGame
                                      : null,
                                  icon: session.finished
                                      ? Icons.replay
                                      : Icons.query_stats,
                                  label: session.finished ? '再来一局' : '一键复盘',
                                ),
                              ),
                              if (session.finished) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GameActionChip(
                                    label: '一键复盘',
                                    onPressed: locked || _game.busy
                                        ? null
                                        : _review,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
