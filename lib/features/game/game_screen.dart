import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/play_feedback.dart';
import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart' as chess;
import '../../widgets/board/chess_board.dart';
import '../../widgets/board/piece_image.dart';
import '../achievements/achievements.dart';
import '../library/records_repository.dart';
import '../library/records_screen.dart';
import 'game_session.dart';
import 'new_game_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.session,
    this.openRepository = RecordsRepository.open,
    this.analytics,
    this.prefs,
  });

  final GameSession? session;
  final Future<RecordsRepository> Function() openRepository;
  final Analytics? analytics;
  final SharedPreferences? prefs;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameSession _session;
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
    _achievementRecorded = _session.finished;
    _startEvent();
  }

  void _startEvent() => _analytics.event('game_start', {'mode': 'local'});

  void _change(VoidCallback action) {
    final wasFinished = _session.finished;
    setState(() {
      action();
      _saveMessage = null;
    });
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

  Future<bool> _confirm(String title, String content, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            IconButton(
              tooltip: '人机对弈',
              onPressed: _saving
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => NewGameScreen(analytics: _analytics),
                      ),
                    ),
              icon: const Icon(Icons.smart_toy_outlined),
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
    if (_dirty && !await _confirm('开始新对局', '本局尚未保存。放弃本局并重新开始？', '重新开始')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _session = GameSession();
      _achievementRecorded = false;
      _achievementError = null;
      _savedRevision = -1;
      _saveMessage = null;
    });
    _startEvent();
  }

  Future<void> _leave() async {
    if (_saving || _achievementSaving) return;
    final confirmed = await _confirm(
      '离开对局',
      '本局尚未保存。可取消返回并保存棋谱，或放弃本局离开。',
      '放弃并离开',
    );
    if (confirmed && mounted) Navigator.pop(context);
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
    final board = _session.board;
    final status =
        _session.outcome?.message ??
        (_session.drawOffer != null
            ? '${colorName(_session.drawOffer!)}提和 · 等待对方回应'
            : '${colorName(_session.turn)}走棋${board.inCheck ? ' · 将军，请应将' : ''}');
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('面对面对弈'),
          actions: [
            IconButton(
              tooltip: '翻转棋盘',
              onPressed: _saving
                  ? null
                  : () => setState(() => _flipped = !_flipped),
              icon: const Icon(Icons.flip_camera_android_outlined),
            ),
            IconButton(
              tooltip: '新对局',
              onPressed: _saving ? null : _newGame,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = math.min(constraints.maxWidth, 640.0);
                final boardSize = math.max(
                  0.0,
                  math.min(width - 24, constraints.maxHeight - 240),
                );
                return Center(
                  child: SizedBox(
                    width: width,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RotatedBox(
                          key: const ValueKey('black-player-bar'),
                          quarterTurns: 2,
                          child: _playerBar(chess.Color.black),
                        ),
                        SizedBox(
                          width: boardSize,
                          height: boardSize,
                          child: ChessBoard(
                            key: ObjectKey(_session),
                            board: board,
                            flipped: _flipped,
                            enabled: _session.canPlay && !_saving,
                            onMove: (move) =>
                                _change(() => _session.play(move)),
                          ),
                        ),
                        _playerBar(chess.Color.white),
                        SizedBox(
                          key: const ValueKey('game-result-area'),
                          height: 72,
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Semantics(
                                liveRegion: true,
                                child: Column(
                                  children: [
                                    Text(
                                      _saveMessage == null
                                          ? status
                                          : '$status\n$_saveMessage',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
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
                        SizedBox(
                          height: 56,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _saving || !_dirty ? null : _save,
                                icon: const Icon(Icons.save_outlined),
                                label: Text(_saving ? '正在保存…' : '保存棋谱'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => RecordsScreen(
                                            openRepository:
                                                widget.openRepository,
                                          ),
                                        ),
                                      ),
                                child: const Text('我的棋谱'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerBar(chess.Color color) {
    final canAct = _session.canAct(color) && !_saving;
    final responding = _session.drawOffer?.opponent == color;
    final label = colorName(color);
    return SizedBox(
      height: 56,
      child: ColoredBox(
        color: canAct
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$label${canAct ? ' · 走棋' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (responding) ...[
                TextButton(
                  key: ValueKey('${color.name}-decline-draw'),
                  onPressed: _saving
                      ? null
                      : () => _change(
                          () => _session.respondToDraw(color, accept: false),
                        ),
                  child: const Text('继续对弈'),
                ),
                FilledButton(
                  key: ValueKey('${color.name}-accept-draw'),
                  onPressed: _saving
                      ? null
                      : () => _change(
                          () => _session.respondToDraw(color, accept: true),
                        ),
                  child: const Text('同意和棋'),
                ),
              ] else ...[
                IconButton(
                  key: ValueKey('${color.name}-undo'),
                  tooltip: '$label悔棋',
                  onPressed: _session.canUndo && !_saving
                      ? () => _change(_session.undo)
                      : null,
                  icon: const Icon(Icons.undo),
                ),
                TextButton(
                  key: ValueKey('${color.name}-offer-draw'),
                  onPressed: canAct
                      ? () => _change(() => _session.offerDraw(color))
                      : null,
                  child: const Text('提和'),
                ),
                TextButton(
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
