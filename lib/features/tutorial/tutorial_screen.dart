import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/play_feedback.dart';
import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/board.dart';
import '../../core/move.dart' as chess;
import '../../core/puzzle.dart';
import '../../engine/stockfish_service.dart';
import '../../widgets/board/chess_board.dart';
import '../achievements/achievements.dart';
import 'tutorial_controller.dart';
import 'tutorial_engine.dart';
import 'tutorial_level.dart';

const tutorialDailyRoute = '/puzzle/daily';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({
    super.key,
    required this.prefs,
    this.analytics,
    this.loadCatalog = TutorialCatalog.load,
    this.createEngine,
  });

  final SharedPreferences prefs;
  final Analytics? analytics;
  final Future<TutorialCatalog> Function() loadCatalog;
  final TutorialEngine Function()? createEngine;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  TutorialController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.loadCatalog();
      if (!mounted) return;
      _controller = TutorialController(
        catalog: catalog,
        prefs: widget.prefs,
        analytics: widget.analytics,
        engine:
            widget.createEngine?.call() ??
            TutorialAi(
              StockfishService(
                prefs: widget.prefs,
                analytics: widget.analytics,
              ),
            ),
      );
    } catch (error, stack) {
      reportHandledError('tutorial_load', error, stack);
      if (mounted) _error = '教程加载失败，请重试；若仍失败，请检查应用资源与本地进度。';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新手互动教程')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _LoadError(message: _error!, retry: _load)
        : AnimatedBuilder(
            animation: _controller!,
            builder: (context, _) {
              final controller = _controller!;
              final levels = controller.catalog.levels;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '从认识棋子，到下完第一局',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '每关只学一件事 · 已完成 ${controller.completed} / ${levels.length}',
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: controller.completed / levels.length,
                    semanticsLabel: '教程完成进度',
                  ),
                  const SizedBox(height: 16),
                  if (controller.completed == levels.length)
                    FilledButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, tutorialDailyRoute),
                      child: const Text('去每日战术题'),
                    ),
                  for (var i = 0; i < levels.length; i++)
                    Card(
                      child: ListTile(
                        key: ValueKey('tutorial-level-$i'),
                        enabled: i <= controller.completed,
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(levels[i].title),
                        subtitle: Text(
                          i < controller.completed
                              ? '已完成 · 可以重温'
                              : i == controller.completed
                              ? '从这里继续'
                              : '完成前一关后解锁',
                        ),
                        trailing: Icon(
                          i < controller.completed
                              ? Icons.check_circle_outline
                              : i == controller.completed
                              ? Icons.play_arrow
                              : Icons.lock_outline,
                        ),
                        onTap: i > controller.completed
                            ? null
                            : () {
                                controller.start(i);
                                Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TutorialPlayScreen(
                                      controller: controller,
                                      analytics: widget.analytics,
                                    ),
                                  ),
                                );
                              },
                      ),
                    ),
                ],
              );
            },
          ),
  );
}

class TutorialPlayScreen extends StatelessWidget {
  const TutorialPlayScreen({
    super.key,
    required this.controller,
    this.analytics,
  });
  final TutorialController controller;
  final Analytics? analytics;

  Future<void> _resign(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束毕业局？'),
        content: const Text('认输会结束本局，并完成教程。输赢不影响毕业。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续下棋'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认认输'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) await controller.resign();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      return PopScope(
        canPop: !c.thinking && !c.saving,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${c.index! + 1} / ${c.catalog.levels.length} · ${c.level.title}',
            ),
          ),
          body: PlayFeedback(
            session: (c, c.index),
            board: c.board,
            source: 'tutorial',
            prefs: c.prefs,
            analytics: analytics,
            result: c.solved
                ? FeedbackResult.completed
                : c.failed
                ? FeedbackResult.incorrect
                : FeedbackResult.playing,
            celebration: c.solved && c.saved
                ? (c.level.graduation ? '教程毕业！' : '本关完成！')
                : null,
            child: _LessonLayout(
              board: c.board,
              enabled: c.canPlay,
              hint: c.hint,
              onMove: c.play,
              status: c.saving
                  ? '正在保存进度'
                  : c.solved
                  ? (c.level.graduation ? c.outcome : '完成目标')
                  : c.thinking
                  ? 'AI 正在走棋，请稍候'
                  : c.failed
                  ? '再试一次'
                  : '你执白 · 点选棋子，再点目标格',
              explanation: c.explanation,
              notice: c.level.graduation ? c.aiNotice : null,
              actions: [
                if (!c.level.graduation && !c.solved && !c.failed)
                  OutlinedButton(
                    onPressed: c.revealHint,
                    child: const Text('提示'),
                  ),
                if (!c.solved)
                  OutlinedButton(
                    onPressed: c.saving || c.thinking
                        ? null
                        : () => c.start(c.index!),
                    child: const Text('重试'),
                  ),
                if (c.level.graduation && !c.solved)
                  OutlinedButton(
                    onPressed: c.canPlay && c.board.plyCount > 0
                        ? () => _resign(context)
                        : null,
                    child: const Text('认输结束'),
                  ),
                if (c.solved && !c.saved)
                  FilledButton(
                    onPressed: c.saving ? null : c.saveCompletion,
                    child: const Text('重新保存'),
                  ),
                if (c.solved && c.saved)
                  FilledButton(
                    onPressed: c.level.graduation
                        ? () => Navigator.pushReplacementNamed(
                            context,
                            tutorialDailyRoute,
                          )
                        : () => c.start(c.index! + 1),
                    child: Text(c.level.graduation ? '去每日战术题' : '下一关'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A working hand-off until the separate daily-puzzle feature owns this route.
/// These are authored tutorial exercises, not the full daily ten-puzzle set.
class TutorialDailyScreen extends StatefulWidget {
  const TutorialDailyScreen({super.key, this.analytics, this.prefs});
  final Analytics? analytics;
  final SharedPreferences? prefs;

  @override
  State<TutorialDailyScreen> createState() => _TutorialDailyScreenState();
}

class _TutorialDailyScreenState extends State<TutorialDailyScreen> {
  PuzzleSession? _session;
  String? _error;
  bool _hint = false;
  int _attempts = 0;
  final _watch = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final catalog = await TutorialCatalog.load();
      final problems = catalog.levels
          .where((level) => level.goal == TutorialGoal.mateIn1)
          .toList();
      final today = DateTime.now();
      final day = DateTime.utc(
        today.year,
        today.month,
        today.day,
      ).difference(DateTime.utc(2026)).inDays;
      if (mounted) {
        setState(() {
          _session = PuzzleSession(problems[day % problems.length].problem);
        });
      }
    } catch (error, stack) {
      reportHandledError('tutorial_daily_load', error, stack);
      if (mounted) setState(() => _error = '入门题加载失败，请重试。');
    }
  }

  void _play(chess.Move move) {
    setState(() {
      _attempts++;
      _session!.playUserMove(move);
    });
    (widget.analytics ?? Analytics.instance).event('puzzle_result', {
      'correct': _session!.status == PuzzleStatus.solved,
      'attempts': _attempts,
      'duration_ms': _watch.elapsedMilliseconds,
    });
    if (_session!.status == PuzzleStatus.solved) {
      unawaited(_recordAchievement());
    }
  }

  Future<void> _recordAchievement() async {
    try {
      final prefs = widget.prefs ?? await SharedPreferences.getInstance();
      await Achievements.of(
        prefs,
      ).record(const ActivityEvent.puzzleSolved(), analytics: widget.analytics);
    } catch (error, stack) {
      reportHandledError('daily_intro_achievement', error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('成就保存失败'),
            action: SnackBarAction(label: '重试', onPressed: _recordAchievement),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('每日战术题 · 入门练习')),
      body: _error != null
          ? _LoadError(message: _error!, retry: _load)
          : session == null
          ? const Center(child: CircularProgressIndicator())
          : PlayFeedback(
              session: session,
              board: session.board,
              source: 'daily_intro',
              prefs: widget.prefs,
              analytics: widget.analytics,
              result: switch (session.status) {
                PuzzleStatus.playing => FeedbackResult.playing,
                PuzzleStatus.solved => FeedbackResult.correct,
                PuzzleStatus.failed => FeedbackResult.incorrect,
              },
              celebration: session.status == PuzzleStatus.solved
                  ? '入门练习完成！'
                  : null,
              child: _LessonLayout(
                board: session.board,
                enabled: session.status == PuzzleStatus.playing,
                hint: _hint ? session.hint() : null,
                onMove: _play,
                status: session.status == PuzzleStatus.solved
                    ? '答对了 · 今天的入门练习已完成'
                    : session.status == PuzzleStatus.failed
                    ? '还不是将杀 · 重试一下'
                    : '白方走 · 一步将杀',
                explanation:
                    '从教程的两道一步杀中按日期轮换一道，练习先找将军，再检查对方能否应将。'
                    '这是每天一题的入门练习，适合刚完成教程后巩固规则。',
                actions: [
                  OutlinedButton(
                    onPressed: () => setState(() => _hint = true),
                    child: const Text('提示'),
                  ),
                  FilledButton(
                    onPressed: () => setState(() {
                      session.reset();
                      _hint = false;
                    }),
                    child: const Text('再练一次'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _LessonLayout extends StatelessWidget {
  const _LessonLayout({
    required this.board,
    required this.enabled,
    required this.hint,
    required this.onMove,
    required this.status,
    required this.explanation,
    required this.actions,
    this.notice,
  });

  final Board board;
  final bool enabled;
  final chess.Move? hint;
  final ValueChanged<chess.Move> onMove;
  final String status;
  final String explanation;
  final String? notice;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        SizedBox(
          key: const ValueKey('tutorial-explanation'),
          height: 156,
          child: SingleChildScrollView(
            key: ValueKey('$status:${notice != null}'),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (notice != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    notice!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(explanation),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Center(
                  child: SizedBox.square(
                    dimension: size,
                    child: Stack(
                      children: [
                        ChessBoard(
                          board: board,
                          enabled: enabled,
                          onMove: onMove,
                        ),
                        if (hint != null)
                          for (final square in [hint!.from, hint!.to])
                            Positioned(
                              left: (square & 7) * size / 8,
                              top: (7 - (square >> 4)) * size / 8,
                              width: size / 8,
                              height: size / 8,
                              child: IgnorePointer(
                                child: Semantics(
                                  label:
                                      '${square == hint!.from ? '起点' : '目标'} '
                                      '${chess.squareName(square)}',
                                  child: Container(
                                    margin: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: square == hint!.to
                                          ? BoxShape.circle
                                          : BoxShape.rectangle,
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
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
        SizedBox(
          height: 64,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final action in actions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: action,
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('重新加载')),
        ],
      ),
    ),
  );
}
