import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/telemetry/crash_guard.dart';
import '../../core/game_tree.dart';
import '../../engine/stockfish_service.dart';
import '../../widgets/board/chess_board.dart';
import 'review_controller.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.record, this.engine});
  final GameRecord record;
  final StockfishService? engine;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final StockfishService _engine;
  late final ReviewController _review;
  final _scroll = ScrollController();
  bool _leaving = false;
  bool _stoppedForExit = false;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? StockfishService();
    _review = ReviewController(record: widget.record, engine: _engine)
      ..addListener(_changed);
    unawaited(_review.run());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _release() async {
    try {
      if (widget.engine == null) {
        await _engine.dispose();
      } else if (!_stoppedForExit) {
        await _engine.stop();
      }
    } catch (error, stack) {
      reportHandledError('review_dispose', error, stack);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await _review.cancel();
      await _engine.stop();
      if (!mounted) return;
      setState(() => _stoppedForExit = true);
      Navigator.pop(context);
    } catch (error, stack) {
      reportHandledError('review_leave', error, stack);
      if (mounted) {
        setState(() {
          _leaving = false;
          _review.error = 'AI 未能停止，请重试或重新打开应用';
        });
      }
    }
  }

  @override
  void dispose() {
    _review.removeListener(_changed);
    _review.dispose();
    _scroll.dispose();
    unawaited(_release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final evaluation = _review.evaluations[_review.selectedPly];
    final cp = evaluation?.whiteCp;
    final mate = evaluation?.whiteMate;
    final evaluationText = evaluation == null
        ? '此局面尚未分析'
        : cp != null
        ? '白方优势 ${(cp / 100).toStringAsFixed(2)} 兵'
        : mate == 0
        ? '已将杀'
        : '${mate! > 0 ? '白方' : '黑方'}可在 ${mate.abs()} 步内将杀';
    return PopScope(
      canPop: _stoppedForExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('本局复盘')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SizedBox(
                width: math.min(640, constraints.maxWidth),
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '逐手分析 · ${_review.completed} / ${_review.line.length}',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (_review.running)
                      LinearProgressIndicator(
                        value: _review.completed / _review.line.length,
                      ),
                    if (_review.running)
                      TextButton(
                        onPressed: _review.cancelling || _leaving
                            ? null
                            : _review.cancel,
                        child: const Text('暂停分析'),
                      ),
                    if (_review.error != null) ...[
                      Text(
                        _review.error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      TextButton(
                        onPressed:
                            _review.running || _review.cancelling || _leaving
                            ? null
                            : _review.run,
                        child: const Text('继续分析'),
                      ),
                    ],
                    Center(
                      child: SizedBox(
                        width: math.min(360, constraints.maxWidth - 32),
                        child: ChessBoard(
                          board: _review.board,
                          enabled: false,
                          onMove: (_) {},
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '第 ${_review.selectedPly} 手 · $evaluationText',
                      textAlign: TextAlign.center,
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: '上一手',
                          onPressed: _review.selectedPly > 0
                              ? () => _review.select(_review.selectedPly - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Slider(
                            key: const ValueKey('review-position'),
                            min: 0,
                            max: math
                                .max(1, _review.line.length - 1)
                                .toDouble(),
                            divisions: math.max(1, _review.line.length - 1),
                            value: _review.selectedPly.toDouble(),
                            label: '第 ${_review.selectedPly} 手',
                            onChanged: _review.line.length > 1
                                ? (value) => _review.select(value.round())
                                : null,
                          ),
                        ),
                        IconButton(
                          tooltip: '下一手',
                          onPressed:
                              _review.selectedPly < _review.line.length - 1
                              ? () => _review.select(_review.selectedPly + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    Text(
                      '每手损失 · 1 兵 = 100',
                      style: theme.textTheme.titleMedium,
                    ),
                    const Text('横轴为手数，纵轴为损失。将杀前后不折算兵值，曲线留空。'),
                    const SizedBox(height: 8),
                    Semantics(
                      label: '逐手损失曲线，可用上方滑块选择手数',
                      child: SizedBox(
                        height: 140,
                        child: CustomPaint(
                          key: const ValueKey('review-loss-chart'),
                          painter: LossChartPainter(
                            losses: _review.losses,
                            selectedPly: _review.selectedPly,
                            color: theme.colorScheme.primary,
                            gridColor: theme.colorScheme.outlineVariant,
                            textColor: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('3 大恶手 · 双方', style: theme.textTheme.titleLarge),
                    if (_review.mistakes.isEmpty)
                      Text(
                        _review.running
                            ? '分析后在这里查看损失较大的着法'
                            : '已分析的着法中没有可量化的正损失',
                      ),
                    for (final mistake in _review.mistakes)
                      ListTile(
                        key: ValueKey('review-mistake-${mistake.ply}'),
                        contentPadding: EdgeInsets.zero,
                        selected: _review.selectedPly == mistake.ply,
                        title: Text(
                          '第 ${mistake.ply} 手 · ${_review.record.boardAt(_review.line[mistake.ply - 1]).san(_review.line[mistake.ply].move!)}',
                        ),
                        subtitle: Text(
                          '损失 ${mistake.loss} · ${(mistake.loss / 100).toStringAsFixed(2)} 兵',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          _review.select(mistake.ply);
                          _scroll.jumpTo(0);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LossChartPainter extends CustomPainter {
  LossChartPainter({
    required List<int?> losses,
    required this.selectedPly,
    required this.color,
    required this.gridColor,
    required this.textColor,
  }) : losses = List.unmodifiable(losses);

  final List<int?> losses;
  final int selectedPly;
  final Color color;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0;
    final width = math.max(1.0, size.width - left - 8);
    final height = math.max(1.0, size.height - 24);
    final maximum = losses.whereType<int>().fold<int>(100, math.max);
    void label(String text, Offset offset) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: textColor, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, offset);
    }

    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = height * (1 - fraction);
      canvas.drawLine(
        Offset(left, y),
        Offset(left + width, y),
        Paint()..color = gridColor,
      );
      label(
        '${(maximum * fraction).round()}',
        Offset(0, y.clamp(0, height - 12)),
      );
    }
    if (losses.isEmpty) return;
    double x(int i) =>
        left +
        (losses.length == 1 ? width / 2 : width * i / (losses.length - 1));
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    Offset? previous;
    for (var i = 0; i < losses.length; i++) {
      final value = losses[i];
      if (value == null) {
        previous = null;
        continue;
      }
      final point = Offset(x(i), height * (1 - value / maximum));
      if (previous != null) canvas.drawLine(previous, point, paint);
      canvas.drawCircle(point, selectedPly == i + 1 ? 5 : 2.5, paint);
      previous = point;
    }
    label('1', Offset(x(0), height + 6));
    if (losses.length > 1) {
      label('${losses.length}', Offset(x(losses.length - 1) - 12, height + 6));
    }
  }

  @override
  bool shouldRepaint(LossChartPainter oldDelegate) =>
      oldDelegate.losses != losses ||
      oldDelegate.selectedPly != selectedPly ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.textColor != textColor;
}
