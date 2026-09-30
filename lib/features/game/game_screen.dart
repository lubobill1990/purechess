import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/play_feedback.dart';
import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart' as chess;
import '../../widgets/board/chess_board.dart';
import '../../widgets/board/board_panel.dart';
import '../../widgets/board/piece_image.dart';
import '../achievements/achievements.dart';
import '../library/records_repository.dart';
import '../library/records_screen.dart';
import 'game_session.dart';
import 'game_persistence.dart';
import 'game_rail.dart';
import 'game_fullscreen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.session,
    this.openRepository = RecordsRepository.open,
    this.analytics,
    this.prefs,
    this.gameStore,
    this.resumed = false,
  });

  final GameSession? session;
  final Future<RecordsRepository> Function() openRepository;
  final Analytics? analytics;
  final SharedPreferences? prefs;
  final GameStore? gameStore;
  final bool resumed;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameSession _session;
  late GamePersistence _persistence;
  GameStore? _ownedStore;
  bool _flipped = false;
  bool _saving = false;
  int _savedRevision = -1;
  String? _saveMessage;
  bool _achievementRecorded = false;
  bool _achievementSaving = false;
  String? _achievementError;

  Analytics get _analytics => widget.analytics ?? Analytics.instance;
  bool get _dirty =>
      (_session.moveCount > 0 || _session.finished) &&
      _session.revision != _savedRevision;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? GameSession();
    if (widget.gameStore == null && widget.prefs != null) {
      _ownedStore = GameStore(widget.prefs!);
    }
    _attachPersistence();
    // A restored finished game must not earn its achievement twice.
    _achievementRecorded = _session.finished;
    if (widget.resumed) {
      _analytics.event('game_resume', {
        'mode': 'local',
        'move_count': _session.moveCount,
      });
    } else {
      _startEvent();
    }
  }

  void _attachPersistence() {
    _persistence = GamePersistence(
      store: widget.gameStore ?? _ownedStore,
      session: () => _session,
    );
  }

  @override
  void dispose() {
    unawaited(_persistence.close());
    _ownedStore?.dispose();
    super.dispose();
  }

  void _startEvent() => _analytics.event('game_start', {'mode': 'local'});

  void _change(VoidCallback action) {
    final wasFinished = _session.finished;
    setState(() {
      action();
      _saveMessage = null;
    });
    _persistence.save();
    if (!wasFinished && _session.finished) {
      unawaited(_recordAchievement());
      _analytics.event('game_end', {
        'mode': 'local',
        'duration_ms': DateTime.now()
            .difference(_session.startedAt)
            .inMilliseconds,
        'move_count': _session.moveCount,
      });
    }
  }

  Future<void> _recordAchievement() async {
    if (_achievementRecorded || _achievementSaving) return;
    final session = _session;
    _achievementSaving = true;
    try {
      final prefs = widget.prefs ?? await SharedPreferences.getInstance();
      await Achievements.of(prefs).record(
        const ActivityEvent.gameFinished(won: false, versusAi: false),
        analytics: _analytics,
      );
      if (identical(session, _session)) {
        _achievementRecorded = true;
        _achievementError = null;
      }
    } catch (error, stack) {
      reportHandledError('local_game_achievement', error, stack);
      if (identical(session, _session)) _achievementError = '成就未保存，请重试';
    } finally {
      _achievementSaving = false;
      if (mounted) setState(() {});
    }
  }

  Future<bool> _confirm(
    String title,
    String content,
    String action, {
    bool allowResume = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            if (allowResume && _persistence.store != null)
              TextButton(
                onPressed: () async {
                  await _persistence.close();
                  if (context.mounted) Navigator.pop(context, false);
                  if (mounted) Navigator.pop(this.context);
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

  Future<void> _resign(chess.Color color) async {
    final revision = _session.revision;
    final confirmed = await _confirm(
      '${colorName(color)}认输',
      '确认认输并结束本局？',
      '确认认输',
    );
    if (confirmed &&
        mounted &&
        revision == _session.revision &&
        _session.canAct(color)) {
      _change(() => _session.resign(color));
    }
  }

  Future<void> _newGame() async {
    if (_achievementSaving) return;
    if (!_session.finished &&
        _dirty &&
        !await _confirm('开始新对局', '本局尚未保存。放弃本局并重新开始？', '重新开始')) {
      return;
    }
    await _persistence.close(abandon: true);
    if (!mounted) return;
    setState(() {
      _session = GameSession();
      _achievementRecorded = false;
      _achievementError = null;
      _savedRevision = -1;
      _saveMessage = null;
    });
    _attachPersistence();
    _startEvent();
  }

  Future<void> _leave() async {
    if (_saving || _achievementSaving) return;
    final confirmed = await _confirm(
      '离开对局',
      '可稍后继续本局，或放弃本局并离开。棋谱需另行保存。',
      '放弃并离开',
      allowResume: !_session.finished,
    );
    if (confirmed) {
      await _persistence.close(abandon: true);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    final revision = _session.revision;
    try {
      final record = _session.snapshot();
      final repository = await widget.openRepository();
      await repository.save(record);
      if (mounted) {
        setState(() {
          _savedRevision = revision;
          _saveMessage = '已保存到我的棋谱';
        });
      }
    } catch (error, stack) {
      reportHandledError('save_pgn', error, stack);
      if (mounted) {
        setState(() => _saveMessage = '棋谱保存失败，请检查存储空间后重试');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facingOpponent =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final board = _session.board;
    final status = _session.outcome?.message ?? '';
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 21;
    void openRecords() => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecordsScreen(openRepository: widget.openRepository),
      ),
    );
    GameRail navigation(bool landscape) => GameRail(
      landscape: landscape,
      title: '面对面对弈',
      onLeave: _leave,
      onFlip: _saving ? null : () => setState(() => _flipped = !_flipped),
      onNewGame: _saving ? null : _newGame,
      finished: _session.finished,
      actions: compact
          ? [
              GameMenuItem(
                value: _save,
                enabled: !_saving && _dirty,
                child: Text(_saving ? '正在保存…' : '保存棋谱'),
              ),
              GameMenuItem(
                value: openRecords,
                enabled: !_saving,
                child: const Text('我的棋谱'),
              ),
            ]
          : const [],
    );
    return GameFullscreen(
      child: PopScope(
        canPop: !_dirty && !_saving,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          backgroundColor: boardTableColor(context),
          body: PlayFeedback(
            session: _session,
            board: board,
            source: 'local',
            prefs: widget.prefs,
            analytics: widget.analytics,
            result: !_session.finished
                ? FeedbackResult.playing
                : _session.outcome!.winner == null
                ? FeedbackResult.draw
                : FeedbackResult.win,
            celebration: _session.outcome?.winner == null
                ? null
                : '${colorName(_session.outcome!.winner!)}获胜',
            child: SafeArea(
              child: BoardPanel(
                minimumSidebarWidth: 320,
                navigationBuilder: navigation,
                above: BoardRail(
                  child: RotatedBox(
                    key: const ValueKey('black-player-bar'),
                    quarterTurns: facingOpponent ? 2 : 0,
                    child: _playerBar(chess.Color.black),
                  ),
                ),
                board: ChessBoard(
                  key: ObjectKey(_session),
                  board: board,
                  flipped: _flipped,
                  flipFingerOffset:
                      facingOpponent && _session.turn == chess.Color.black,
                  enabled: _session.canPlay && !_saving,
                  onMove: (move) => _change(() => _session.play(move)),
                ),
                below: Column(
                  children: [
                    BoardRail(
                      emphasized: true,
                      child: SizedBox(
                        key: const ValueKey('game-result-area'),
                        height: 72,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Semantics(
                                liveRegion: true,
                                child: Column(
                                  children: [
                                    Text(
                                      _saveMessage == null
                                          ? status
                                          : '$status\n$_saveMessage',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_achievementError != null)
                                      TextButton(
                                        onPressed: _achievementSaving
                                            ? null
                                            : _recordAchievement,
                                        child: Text('$_achievementError保存'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    BoardRail(
                      child: RotatedBox(
                        key: const ValueKey('white-player-bar'),
                        quarterTurns: 0,
                        child: _playerBar(chess.Color.white),
                      ),
                    ),
                  ],
                ),
                controls: compact
                    ? const SizedBox.shrink()
                    : SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _saving || !_dirty ? null : _save,
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(_saving ? '正在保存…' : '保存棋谱'),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton(
                                  onPressed: _saving ? null : openRecords,
                                  child: const Text('我的棋谱'),
                                ),
                              ],
                            ),
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

  Widget _playerBar(chess.Color color) {
    final canAct = _session.canAct(color) && !_saving;
    final active = !_session.finished && _session.turn == color;
    final responding = _session.drawOffer?.opponent == color;
    final label = colorName(color);
    return SizedBox(
      height: 64,
      child: ColoredBox(
        key: ValueKey('${color.name}-turn-highlight'),
        color: active ? BoardPainter.lastMoveTint : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$label\n${responding
                          ? '对方提和'
                          : _session.drawOffer == color
                          ? '等待回应'
                          : active
                          ? '轮到你${_session.board.inCheck ? ' · 应将' : ''}'
                          : (_session.finished ? '对局结束' : '等待对方')}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: active
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: BoardPainter.ink.withValues(
                          alpha: active ? 1 : .55,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (responding) ...[
                Expanded(
                  child: GameActionChip(
                    key: ValueKey('${color.name}-decline-draw'),
                    onPressed: _saving
                        ? null
                        : () => _change(
                            () => _session.respondToDraw(color, accept: false),
                          ),
                    label: '继续对弈',
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: GameActionChip(
                    key: ValueKey('${color.name}-accept-draw'),
                    onPressed: _saving
                        ? null
                        : () => _change(
                            () => _session.respondToDraw(color, accept: true),
                          ),
                    label: '同意和棋',
                  ),
                ),
              ] else ...[
                OutlinedButton(
                  key: ValueKey('${color.name}-undo'),
                  onPressed: _session.canUndo && !_saving
                      ? () => _change(_session.undo)
                      : null,
                  child: Tooltip(
                    message: '$label悔棋',
                    child: const Icon(Icons.undo, size: 20),
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  key: ValueKey('${color.name}-offer-draw'),
                  onPressed: canAct
                      ? () => _change(() => _session.offerDraw(color))
                      : null,
                  child: const Text('提和'),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  key: ValueKey('${color.name}-resign'),
                  onPressed: canAct ? () => _resign(color) : null,
                  child: const Text('认输'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
