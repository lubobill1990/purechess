import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router.dart';
import '../../app/telemetry/crash_guard.dart';
import '../library/classic_library.dart';
import 'learning_progress.dart';
import 'study_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.prefs,
    this.recommendedDifficulty,
    this.canResumeGame = false,
    this.now = DateTime.now,
  }) : assert(
         recommendedDifficulty == null ||
             (recommendedDifficulty >= 1 && recommendedDifficulty <= 10),
       );

  final SharedPreferences prefs;
  final int? recommendedDifficulty;
  final bool canResumeGame;
  final DateTime Function() now;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _midnight;
  String? _refreshError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = widget.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () {
      if (mounted) setState(() {});
      _scheduleMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
      _scheduleMidnight();
    }
  }

  Future<void> _refresh() async {
    try {
      await widget.prefs.reload();
      if (mounted) setState(() => _refreshError = null);
    } catch (error, stack) {
      reportHandledError('home_progress', error, stack);
      if (mounted) setState(() => _refreshError = '学习进度刷新失败，请重试。');
    }
  }

  Future<void> _open(String route, {Object? arguments}) async {
    await Navigator.pushNamed(context, route, arguments: arguments);
    if (mounted) await _refresh();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StudyTheme(child: Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    final progress = LearningProgress.read(widget.prefs, widget.now());
    final reading = ReadingProgress.read(widget.prefs);
    final savedDifficulty = widget.prefs.get('chess.ai.recommendedLevel');
    final validDifficulty =
        savedDifficulty is int && savedDifficulty >= 1 && savedDifficulty <= 10;
    final difficulty =
        widget.recommendedDifficulty ?? (validDifficulty ? savedDifficulty : 1);
    final theme = Theme.of(context);
    final error =
        _refreshError ??
        progress.error ??
        reading.error ??
        (widget.recommendedDifficulty == null &&
                savedDifficulty != null &&
                !validDifficulty
            ? '推荐难度无法识别，暂用入门第 1 档。'
            : null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('纯弈国象'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () => _open(AppRouter.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!progress.graduated && widget.canResumeGame)
                    TextButton.icon(
                      onPressed: () =>
                          _open(AppRouter.newGame, arguments: {'resume': true}),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('继续对局'),
                    ),
                  Text(
                    progress.graduated ? '每天，读懂一步。' : '从第一步，到看懂一盘棋。',
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    progress.graduated
                        ? '练习一次判断，下一盘棋，再向大师借一招。'
                        : '不必先记住所有规则。在棋盘上，一关一关学会。',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  if (!progress.graduated)
                    _LearningCard(
                      icon: Icons.school_outlined,
                      eyebrow: '入门教程',
                      title: '继续教程第 ${progress.nextLesson} 关',
                      description: progress.tutorialAvailable
                          ? '已完成 ${progress.completedLessons} / ${progress.totalLessons} 关'
                          : '还没有学习记录，从第 1 关开始。',
                      progress:
                          progress.completedLessons / progress.totalLessons,
                      onTap: () => _open(
                        AppRouter.tutorial,
                        arguments: {'lesson': progress.nextLesson},
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth >= 840
                            ? (constraints.maxWidth - 32) / 3
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            SizedBox(
                              width: width,
                              child: _LearningCard(
                                icon: Icons.extension_outlined,
                                eyebrow: '练习 · 每日十题',
                                title: '每日战术题',
                                description: progress.dailyAvailable
                                    ? '今日 ${progress.dailySolved} / ${progress.dailyTotal} 题'
                                    : '今日还没有练习记录。',
                                progress:
                                    progress.dailySolved / progress.dailyTotal,
                                onTap: () => _open(AppRouter.daily),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _LearningCard(
                                icon: Icons.grid_on_outlined,
                                eyebrow: '实战 · 循序渐进',
                                title: widget.canResumeGame ? '继续对局' : '新对局',
                                description: '推荐难度 $difficulty / 10 档',
                                onTap: () => _open(
                                  AppRouter.newGame,
                                  arguments: {
                                    'difficulty': difficulty,
                                    'resume': widget.canResumeGame,
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _LearningCard(
                                icon: Icons.menu_book_outlined,
                                eyebrow: '阅读 · 十九世纪名局',
                                title: reading.id == null ? '读一盘名局' : '继续看的名局',
                                description: reading.id == null
                                    ? '从莫菲的歌剧院局开始。'
                                    : '已读 ${reading.ply} 半回合 · 回到上次的位置',
                                onTap: () => _open(AppRouter.reading),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  Divider(color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: () => _open(AppRouter.newGame),
                        icon: const Icon(Icons.smart_toy_outlined),
                        label: const Text('人机对弈'),
                      ),
                      TextButton.icon(
                        onPressed: () => _open(AppRouter.game),
                        icon: const Icon(Icons.people_outline),
                        label: const Text('双人对弈'),
                      ),
                      TextButton.icon(
                        onPressed: () => _open(AppRouter.records),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('我的棋谱'),
                      ),
                      TextButton.icon(
                        onPressed: () => _open(AppRouter.library),
                        icon: const Icon(Icons.auto_stories_outlined),
                        label: const Text('名局库'),
                      ),
                      if (progress.graduated)
                        TextButton(
                          onPressed: () => _open(AppRouter.tutorial),
                          child: const Text('重温教程'),
                        ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (_refreshError != null)
                    TextButton(onPressed: _refresh, child: const Text('重试')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LearningCard extends StatelessWidget {
  const _LearningCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.onTap,
    this.progress,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        enableFeedback: false,
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(eyebrow, style: theme.textTheme.labelLarge),
                  ),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
              const SizedBox(height: 24),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(description, style: theme.textTheme.bodyLarge),
              if (progress != null) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: progress,
                  semanticsLabel: title,
                  semanticsValue: '${(progress! * 100).round()}%',
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
