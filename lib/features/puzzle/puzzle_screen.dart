import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/play_feedback.dart';
import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart' as chess;
import '../../core/puzzle.dart';
import '../../widgets/board/chess_board.dart';
import '../../widgets/board/board_panel.dart';
import '../achievements/achievements.dart';
import 'puzzle_attempt.dart';
import 'puzzle_catalog.dart';
import 'puzzle_repository.dart';

class PuzzleScreen extends StatefulWidget {
  const PuzzleScreen({
    super.key,
    required this.prefs,
    this.analytics,
    this.loadCatalog = PuzzleCatalog.load,
    this.now = DateTime.now,
  });

  final SharedPreferences prefs;
  final Analytics? analytics;
  final Future<PuzzleCatalog> Function() loadCatalog;
  final DateTime Function() now;

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  PuzzleRepository? _repository;
  bool _loading = true;
  bool _openingDaily = false;
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
      _repository?.dispose();
      _repository = PuzzleRepository(prefs: widget.prefs, catalog: catalog);
    } catch (error, stack) {
      reportHandledError('puzzle_load', error, stack);
      if (mounted) _error = '题库或进度读取失败，请重试';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _daily() async {
    setState(() => _openingDaily = true);
    try {
      final date = widget.now();
      final ids = await _repository!.daily(date);
      if (!mounted) return;
      _openList('每日 10 题', ids, day: PuzzleRepository.dailyKey(date));
    } catch (error, stack) {
      reportHandledError('puzzle_daily', error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('每日题单读取或保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _openingDaily = false);
    }
  }

  void _openList(
    String title,
    List<String> ids, {
    String? day,
    bool mistakes = false,
  }) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PuzzleListScreen(
          repository: _repository!,
          title: title,
          ids: ids,
          day: day,
          mistakesOnly: mistakes,
          analytics: widget.analytics,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('战术题')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          )
        : ListenableBuilder(
            listenable: _repository!,
            builder: (context, _) {
              final repository = _repository!;
              final catalog = repository.catalog;
              final solved = repository.solved;
              final completed = solved
                  .intersection(catalog.byId.keys.toSet())
                  .length;
              final mistakes =
                  repository.mistakes.where(catalog.byId.containsKey).toList()
                    ..sort();
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '读懂局面，找到关键一步',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text('已完成 $completed / ${catalog.byId.length} 题 · 离线练习'),
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.today_outlined),
                          title: const Text('每日 10 题'),
                          subtitle: Text(
                            '今天已完成 ${repository.completed(PuzzleRepository.dailyKey(widget.now())).length} / 10',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _openingDaily ? null : _daily,
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.bookmark_border),
                          title: const Text('错题本'),
                          subtitle: Text('${mistakes.length} 题待巩固 · 做对后自动移出'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              _openList('错题本', mistakes, mistakes: true),
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final theme in puzzleThemes.entries)
                        Card(
                          child: ExpansionTile(
                            enableFeedback: false,
                            title: Text(theme.value.title),
                            subtitle: Text(
                              '${catalog.packs.where((pack) => pack.theme == theme.key).fold<int>(0, (sum, pack) => sum + pack.puzzles.length)} 题',
                            ),
                            children: [
                              for (final pack in catalog.packs.where(
                                (pack) => pack.theme == theme.key,
                              ))
                                ListTile(
                                  title: Text(puzzleBands[pack.band]!),
                                  subtitle: Text(
                                    '${pack.puzzles.where((puzzle) => solved.contains(puzzle.id)).length} / ${pack.puzzles.length} 已完成',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openList(
                                    '${pack.title} · ${puzzleBands[pack.band]}',
                                    pack.puzzles
                                        .map((puzzle) => puzzle.id)
                                        .toList(),
                                  ),
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
  );
}

class PuzzleListScreen extends StatelessWidget {
  const PuzzleListScreen({
    super.key,
    required this.repository,
    required this.title,
    required this.ids,
    this.day,
    this.mistakesOnly = false,
    this.analytics,
  });

  final PuzzleRepository repository;
  final String title;
  final List<String> ids;
  final String? day;
  final bool mistakesOnly;
  final Analytics? analytics;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final mistakes = repository.mistakes;
        final visible = ids
            .where((id) => !mistakesOnly || mistakes.contains(id))
            .toList();
        final completed = mistakesOnly ? <String>{} : repository.completed(day);
        if (visible.isEmpty) {
          return const Center(
            child: Text('暂时没有错题\n继续练习，做错的题会收进这里', textAlign: TextAlign.center),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        day == null
                            ? '${visible.where(completed.contains).length} / ${visible.length} 已完成'
                            : '${day!.substring(6, 10)}-${day!.substring(10, 12)}-${day!.substring(12)} · ${visible.where(completed.contains).length} / 10 已完成',
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value:
                            visible.where(completed.contains).length /
                            visible.length,
                        semanticsLabel: '题集完成进度',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final puzzle = repository.catalog.byId[visible[index]]!;
                      final wrong = mistakes.contains(puzzle.id);
                      return ListTile(
                        key: ValueKey('puzzle-${puzzle.id}'),
                        leading: Icon(
                          wrong
                              ? Icons.bookmark
                              : completed.contains(puzzle.id)
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                        ),
                        title: Text('第 ${index + 1} 题 · ${puzzle.rating}'),
                        subtitle: Text(
                          '${puzzleThemes.entries.firstWhere((entry) => puzzle.themes.contains(entry.key)).value.title} · ${wrong
                              ? '待巩固'
                              : completed.contains(puzzle.id)
                              ? '已完成'
                              : '未完成'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PuzzleSolveScreen(
                              repository: repository,
                              ids: List.unmodifiable(visible),
                              initialIndex: index,
                              day: day,
                              analytics: analytics,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class PuzzleSolveScreen extends StatefulWidget {
  const PuzzleSolveScreen({
    super.key,
    required this.repository,
    required this.ids,
    this.initialIndex = 0,
    this.day,
    this.analytics,
  });

  final PuzzleRepository repository;
  final List<String> ids;
  final int initialIndex;
  final String? day;
  final Analytics? analytics;

  @override
  State<PuzzleSolveScreen> createState() => _PuzzleSolveScreenState();
}

class _PuzzleSolveScreenState extends State<PuzzleSolveScreen> {
  late int _index;
  late PuzzleAttempt _attempt;
  bool _saving = false;
  bool _discard = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _start();
  }

  void _start() {
    _attempt = PuzzleAttempt(
      widget.repository.catalog.byId[widget.ids[_index]]!,
    );
  }

  void _play(chess.Move move) {
    setState(() => _attempt.play(move));
    if (_attempt.status != PuzzleStatus.playing) {
      (widget.analytics ?? Analytics.instance).event('puzzle_result', {
        'correct': _attempt.status == PuzzleStatus.solved,
        'attempts': _attempt.attempts,
        'duration_ms': _attempt.elapsed.elapsedMilliseconds,
        'rating': _attempt.problem.rating,
      });
      _save();
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.repository.record(
        _attempt.problem.id,
        correct: _attempt.status == PuzzleStatus.solved,
        day: widget.day,
      );
      if (_attempt.status == PuzzleStatus.solved) {
        final achievements = Achievements.of(widget.repository.prefs);
        await achievements.record(
          const ActivityEvent.puzzleSolved(),
          analytics: widget.analytics,
        );
        final dailyComplete =
            widget.day != null &&
            widget.repository.completed(widget.day).length == 10;
        if (dailyComplete) {
          await achievements.record(
            const ActivityEvent.dailyCompleted(),
            analytics: widget.analytics,
          );
        }
      }
    } catch (error, stack) {
      reportHandledError('puzzle_progress', error, stack);
      if (mounted) _saveError = '进度保存失败，请重试保存';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_saving) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('进度尚未保存'),
        content: const Text('离开会丢失本次结果。可以取消并重试保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃本次结果'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _discard = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Widget _board(double size) {
    final square = _attempt.hintSquare;
    final flipped = _attempt.playerColor == chess.Color.black;
    final cell = size / 8;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ChessBoard(
            key: ObjectKey(_attempt),
            board: _attempt.board,
            flipped: flipped,
            enabled: _attempt.status == PuzzleStatus.playing && !_saving,
            onMove: _play,
          ),
          if (square != null)
            Positioned(
              left: (flipped ? 7 - (square & 7) : square & 7) * cell,
              top: (flipped ? square >> 4 : 7 - (square >> 4)) * cell,
              width: cell,
              height: cell,
              child: IgnorePointer(
                child: Semantics(
                  label: '提示起点 ${chess.squareName(square)}',
                  child: Container(
                    key: const ValueKey('puzzle-hint-square'),
                    margin: const EdgeInsets.all(3),
                    decoration: boardHintDecoration(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls() {
    final status = _attempt.status;
    final canContinue = !_saving && _saveError == null;
    final message =
        _saveError ??
        (_saving
            ? '正在保存进度…'
            : switch (status) {
                PuzzleStatus.playing =>
                  '${_attempt.playerColor == chess.Color.white ? '白方' : '黑方'}走棋 · 找到最佳主线',
                PuzzleStatus.failed => '这步不是最佳主线，已加入错题本',
                PuzzleStatus.solved => '答对了！已保存进度，错题本同步更新',
              });
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BoardRail(
          key: const ValueKey('puzzle-result-area'),
          height: 80,
          emphasized: true,
          child: Center(
            child: SingleChildScrollView(
              child: Semantics(
                liveRegion: true,
                child: Text(message, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 72,
          child: SingleChildScrollView(
            child: Text(
              _attempt.hintLevel == 0
                  ? '先观察将军、吃子和直接威胁。对方会自动应着。'
                  : _attempt.idea,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (_saveError != null)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('重试保存'),
          )
        else if (status == PuzzleStatus.playing)
          OutlinedButton.icon(
            onPressed: _attempt.hintLevel == 2
                ? null
                : () => setState(_attempt.revealHint),
            icon: const Icon(Icons.lightbulb_outline),
            label: Text(switch (_attempt.hintLevel) {
              0 => '提示思路',
              1 => '亮起点格',
              _ => '已显示两级提示',
            }),
          )
        else if (status == PuzzleStatus.failed)
          FilledButton(
            onPressed: canContinue ? () => setState(_attempt.retry) : null,
            child: const Text('再试一次'),
          )
        else
          FilledButton(
            onPressed: !canContinue
                ? null
                : () {
                    if (_index + 1 == widget.ids.length) {
                      Navigator.pop(context);
                    } else {
                      setState(() {
                        _index++;
                        _start();
                      });
                    }
                  },
            child: Text(_index + 1 == widget.ids.length ? '返回题目列表' : '下一题'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _discard || (!_saving && _saveError == null),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      backgroundColor: boardTableColor(context),
      appBar: boardAppBar(
        context,
        '第 ${_index + 1} / ${widget.ids.length} 题 · ${_attempt.problem.rating}',
      ),
      body: PlayFeedback(
        session: _attempt,
        board: _attempt.board,
        source: widget.day == null ? 'puzzle' : 'daily',
        prefs: widget.repository.prefs,
        analytics: widget.analytics,
        result: switch (_attempt.status) {
          PuzzleStatus.playing => FeedbackResult.playing,
          PuzzleStatus.solved => FeedbackResult.correct,
          PuzzleStatus.failed => FeedbackResult.incorrect,
        },
        celebration:
            _attempt.status == PuzzleStatus.solved &&
                !_saving &&
                _saveError == null
            ? (widget.ids.every(
                    widget.repository.completed(widget.day).contains,
                  )
                  ? (widget.day == null ? '题集完成！' : '每日练习完成！')
                  : '解题成功！')
            : null,
        child: SafeArea(
          child: BoardPanel(
            board: LayoutBuilder(
              builder: (context, constraints) => _board(constraints.maxWidth),
            ),
            below: BoardRail(child: _controls()),
          ),
        ),
      ),
    ),
  );
}
