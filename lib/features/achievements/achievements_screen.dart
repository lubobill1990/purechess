import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart' as chess;
import '../../widgets/board/piece_image.dart';
import '../home/study_theme.dart';
import 'achievements.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({
    super.key,
    required this.prefs,
    this.now = DateTime.now,
  });
  final SharedPreferences prefs;
  final DateTime Function() now;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with WidgetsBindingObserver {
  AchievementData? _data;
  AchievementProgress? _progress;
  String? _error;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = widget.now().toLocal();
    _midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (mounted) setState(() {});
        _scheduleMidnight();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
      _scheduleMidnight();
    }
  }

  Future<void> _load() async {
    try {
      final data = await Achievements.of(widget.prefs).read();
      final progress = AchievementProgress.read(widget.prefs);
      if (mounted) {
        setState(() {
          _data = data;
          _progress = progress;
          _error = null;
        });
      }
    } catch (error, stack) {
      reportHandledError('achievements_screen', error, stack);
      if (mounted) setState(() => _error = '成就读取失败，请重试');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StudyTheme(
    child: Builder(
      builder: (context) {
        final data = _data;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('成就')),
          body: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : data == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '每一步，都算数。',
                                  style: theme.textTheme.headlineLarge,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  '连续打卡 ${data.currentStreak(widget.now())} 天',
                                  key: const ValueKey('achievement-streak'),
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  data.activeToday(widget.now())
                                      ? '今日已打卡'
                                      : '今日未打卡 · 完成一题、一关或一局即可',
                                ),
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 24,
                                  runSpacing: 12,
                                  children: [
                                    Text('最佳连续 ${data.bestStreak} 天'),
                                    Text(
                                      '累计对局 ${data.counters['gamesFinished']} 局',
                                    ),
                                    Text(
                                      '战胜 AI ${data.counters['winsVsAi']} 局',
                                    ),
                                    Text('累计答对 ${_progress!.puzzles} 题'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          '奖章墙 · ${data.earned.length} / ${achievementBadges.length}',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text('从落子启程，到战术百炼。已获得的奖章会一直保留。'),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final scale =
                                MediaQuery.textScalerOf(context).scale(14) / 14;
                            final columns =
                                (constraints.maxWidth / (170 * scale))
                                    .floor()
                                    .clamp(1, 4);
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: achievementBadges.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisExtent: 210 * math.max(1, scale),
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                  ),
                              itemBuilder: (context, index) => _BadgeTile(
                                badge: achievementBadges[index],
                                date: data.earned[achievementBadges[index].id],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    ),
  );
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, this.date});
  final AchievementBadge badge;
  final String? date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final earned = date != null;
    final ink = earned ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    final dateText = date == null
        ? null
        : '${date!.substring(0, 4)}-${date!.substring(4, 6)}-${date!.substring(6)}';
    return Semantics(
      label: earned ? '已获得' : '未获得',
      child: Card(
        key: ValueKey('badge-${badge.id}-${earned ? 'earned' : 'locked'}'),
        color: earned
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: earned
                    ? colors.primary
                    : colors.outlineVariant,
                foregroundColor: earned ? colors.onPrimary : colors.outline,
                child: Opacity(
                  opacity: earned ? 1 : .45,
                  child: const SizedBox.square(
                    dimension: 36,
                    child: PieceImage(
                      piece: chess.Piece(
                        chess.Color.white,
                        chess.PieceType.knight,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                badge.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: ink),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: Text(
                    earned ? '获得于 $dateText' : badge.condition,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
