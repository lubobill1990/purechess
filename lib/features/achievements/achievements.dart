import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';

enum ActivityKind {
  gameFinished,
  puzzleSolved,
  tutorialLevelDone,
  dailyCompleted,
}

class ActivityEvent {
  const ActivityEvent.gameFinished({required this.won, this.versusAi = true})
    : kind = ActivityKind.gameFinished;
  const ActivityEvent.puzzleSolved()
    : kind = ActivityKind.puzzleSolved,
      won = false,
      versusAi = false;
  const ActivityEvent.tutorialLevelDone()
    : kind = ActivityKind.tutorialLevelDone,
      won = false,
      versusAi = false;
  const ActivityEvent.dailyCompleted()
    : kind = ActivityKind.dailyCompleted,
      won = false,
      versusAi = false;

  final ActivityKind kind;
  final bool won;
  final bool versusAi;
}

class AchievementBadge {
  const AchievementBadge(
    this.id,
    this.title,
    this.condition,
    this.metric,
    this.target,
  );
  final String id;
  final String title;
  final String condition;
  final String metric;
  final int target;
}

const achievementBadges = [
  AchievementBadge('first_day', '落子启程', '完成一次学习或对局', 'bestStreak', 1),
  AchievementBadge('streak_7', '七日进阶', '连续打卡 7 天', 'bestStreak', 7),
  AchievementBadge('streak_30', '月积棋功', '连续打卡 30 天', 'bestStreak', 30),
  AchievementBadge('streak_100', '百日磨棋', '连续打卡 100 天', 'bestStreak', 100),
  AchievementBadge('streak_365', '四季棋心', '连续打卡 365 天', 'bestStreak', 365),
  AchievementBadge('tutorial_grad', '新锐出师', '完成全部教程（含毕业局）', 'tutorial', 19),
  AchievementBadge('first_win', '首胜', '首次战胜 AI', 'winsVsAi', 1),
  AchievementBadge(
    'win_streak_3',
    '三连胜',
    '连续 3 局战胜 AI（和棋中断连胜）',
    'bestWinStreak',
    3,
  ),
  AchievementBadge('games_10', '十局初成', '完成 10 局对弈，含认输与和棋', 'gamesFinished', 10),
  AchievementBadge(
    'games_100',
    '百局历练',
    '完成 100 局对弈，含认输与和棋',
    'gamesFinished',
    100,
  ),
  AchievementBadge('daily_7', '七日战术', '累计完成 7 天每日十题', 'dailyCompleted', 7),
  AchievementBadge('daily_30', '战术月课', '累计完成 30 天每日十题', 'dailyCompleted', 30),
  AchievementBadge('puzzles_10', '战术入门', '累计做对 10 道不同战术题', 'puzzles', 10),
  AchievementBadge('puzzles_50', '妙手渐成', '累计做对 50 道不同战术题', 'puzzles', 50),
  AchievementBadge('puzzles_200', '战术百炼', '累计做对 200 道不同战术题', 'puzzles', 200),
];

String achievementDay(DateTime value) {
  final date = value.toLocal();
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}

class AchievementData {
  AchievementData({
    this.lastActiveDay = '',
    this.streak = 0,
    this.bestStreak = 0,
    Map<String, int> counters = const {},
    Map<String, String> earned = const {},
  }) : counters = Map.unmodifiable({
         for (final key in counterKeys) key: counters[key] ?? 0,
       }),
       earned = Map.unmodifiable(earned);

  static const preferenceKey = 'achievements';
  static const counterKeys = {
    'gamesFinished',
    'winsVsAi',
    'winStreak',
    'bestWinStreak',
    'dailyCompleted',
  };
  final String lastActiveDay;
  final int streak;
  final int bestStreak;
  final Map<String, int> counters;
  final Map<String, String> earned;

  bool activeToday(DateTime now) => lastActiveDay == achievementDay(now);
  int currentStreak(DateTime now) {
    final local = now.toLocal();
    final yesterday = achievementDay(
      DateTime(local.year, local.month, local.day - 1),
    );
    return activeToday(now) || lastActiveDay == yesterday ? streak : 0;
  }

  String encode() => jsonEncode({
    'lastActiveDay': lastActiveDay,
    'streak': streak,
    'bestStreak': bestStreak,
    'counters': counters,
    'earned': earned,
  });

  static bool _day(Object? value) {
    if (value is! String || !RegExp(r'^\d{8}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && achievementDay(parsed) == value;
  }

  static AchievementData decode(Object? raw) {
    if (raw is! String) throw const FormatException('奖章数据格式无效');
    final data = jsonDecode(raw);
    bool count(Object? value) => value is int && value >= 0;
    if (data is! Map<String, dynamic> ||
        !(data['lastActiveDay'] == '' || _day(data['lastActiveDay'])) ||
        !count(data['streak']) ||
        !count(data['bestStreak']) ||
        data['counters'] is! Map<String, dynamic> ||
        data['earned'] is! Map<String, dynamic>) {
      throw const FormatException('奖章数据结构无效');
    }
    final counters = data['counters'] as Map<String, dynamic>;
    final earned = data['earned'] as Map<String, dynamic>;
    if (counters.length != counterKeys.length ||
        !counterKeys.every((key) => count(counters[key])) ||
        earned.entries.any(
          (entry) =>
              !achievementBadges.any((badge) => badge.id == entry.key) ||
              !_day(entry.value),
        )) {
      throw const FormatException('奖章计数或日期无效');
    }
    return AchievementData(
      lastActiveDay: data['lastActiveDay'] as String,
      streak: data['streak'] as int,
      bestStreak: data['bestStreak'] as int,
      counters: counters.cast<String, int>(),
      earned: earned.cast<String, String>(),
    );
  }

  static AchievementData merge(AchievementData a, AchievementData b) =>
      AchievementData(
        lastActiveDay: a.lastActiveDay.compareTo(b.lastActiveDay) >= 0
            ? a.lastActiveDay
            : b.lastActiveDay,
        streak: max(a.streak, b.streak),
        bestStreak: max(a.bestStreak, b.bestStreak),
        counters: {
          for (final key in counterKeys)
            key: max(a.counters[key]!, b.counters[key]!),
        },
        earned: {
          ...a.earned,
          for (final entry in b.earned.entries)
            entry.key:
                a.earned[entry.key] != null &&
                    a.earned[entry.key]!.compareTo(entry.value) < 0
                ? a.earned[entry.key]!
                : entry.value,
        },
      );
}

/// Reads the existing progress; achievements never store a second puzzle count.
class AchievementProgress {
  const AchievementProgress({
    this.puzzles = 0,
    this.tutorial = 0,
    this.daily = 0,
  });
  final int puzzles;
  final int tutorial;
  final int daily;

  static AchievementProgress read(SharedPreferences prefs) {
    final tutorial = prefs.get('tutorial_progress') ?? 0;
    if (tutorial is! int || tutorial < 0) {
      throw const FormatException('教程进度格式无效');
    }
    final raw = prefs.get('puzzle_progress_v1');
    if (raw == null) return AchievementProgress(tutorial: tutorial);
    if (raw is! String) throw const FormatException('战术题进度格式无效');
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['solved'] is! List ||
        data['dailySolved'] is! Map<String, dynamic>) {
      throw const FormatException('战术题进度结构无效');
    }
    final solved = data['solved'] as List;
    if (solved.any((id) => id is! String)) {
      throw const FormatException('战术题编号无效');
    }
    var daily = 0;
    for (final entry in (data['dailySolved'] as Map<String, dynamic>).entries) {
      if (entry.value is! List) throw const FormatException('每日题进度无效');
      final completed = (entry.value as List).toSet();
      final set = prefs.get(entry.key);
      if (set is String) {
        final ids = jsonDecode(set);
        if (ids is List &&
            ids.toSet().length == 10 &&
            ids.every(completed.contains)) {
          daily++;
        }
      }
    }
    return AchievementProgress(
      puzzles: solved.toSet().length,
      tutorial: tutorial,
      daily: daily,
    );
  }
}

class Achievements {
  Achievements(this.prefs, {this.now = DateTime.now});
  final SharedPreferences prefs;
  final DateTime Function() now;
  static final _instances = Expando<Achievements>();
  static Achievements of(SharedPreferences prefs) =>
      _instances[prefs] ??= Achievements(prefs);

  final _earned = StreamController<AchievementBadge>.broadcast(sync: true);
  Stream<AchievementBadge> get earned => _earned.stream;
  Future<void>? _pending;

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      if (identical(_pending, done.future)) _pending = null;
      done.complete();
    }
  }

  Future<void> _write(AchievementData data) async {
    try {
      if (!await prefs.setString(
        AchievementData.preferenceKey,
        data.encode(),
      )) {
        throw StateError('奖章进度保存失败');
      }
    } catch (_) {
      await prefs.reload();
      rethrow;
    }
  }

  Future<AchievementData> _read() async {
    final raw = prefs.get(AchievementData.preferenceKey);
    if (raw == null) return AchievementData();
    try {
      return AchievementData.decode(raw);
    } on FormatException catch (error, stack) {
      reportHandledError('achievements_decode', error, stack);
      final empty = AchievementData();
      await _write(empty);
      return empty;
    }
  }

  Future<AchievementData> read() => _serial(_read);

  Future<List<AchievementBadge>> record(
    ActivityEvent event, {
    Analytics? analytics,
  }) => _serial(() async {
    final before = await _read();
    final progress = AchievementProgress.read(prefs);
    final date = now().toLocal();
    final day = achievementDay(date);
    final yesterday = achievementDay(
      DateTime(date.year, date.month, date.day - 1),
    );
    final streak = before.lastActiveDay == day
        ? before.streak
        : before.lastActiveDay == yesterday
        ? before.streak + 1
        : 1;
    final counters = {...before.counters};
    if (event.kind == ActivityKind.gameFinished) {
      counters['gamesFinished'] = counters['gamesFinished']! + 1;
      if (event.versusAi) {
        counters['winsVsAi'] = counters['winsVsAi']! + (event.won ? 1 : 0);
        counters['winStreak'] = event.won ? counters['winStreak']! + 1 : 0;
        counters['bestWinStreak'] = max(
          counters['bestWinStreak']!,
          counters['winStreak']!,
        );
      }
    }
    // Persisted daily sets are the idempotency ledger, including after restart.
    if (event.kind == ActivityKind.dailyCompleted) {
      counters['dailyCompleted'] = max(
        counters['dailyCompleted']!,
        progress.daily,
      );
    }
    final best = max(before.bestStreak, streak);
    final metrics = {
      ...counters,
      'bestStreak': best,
      'puzzles': progress.puzzles,
      'tutorial': progress.tutorial,
    };
    final fresh = achievementBadges
        .where(
          (badge) =>
              !before.earned.containsKey(badge.id) &&
              metrics[badge.metric]! >= badge.target,
        )
        .toList();
    await _write(
      AchievementData(
        lastActiveDay: day,
        streak: streak,
        bestStreak: best,
        counters: counters,
        earned: {...before.earned, for (final badge in fresh) badge.id: day},
      ),
    );
    for (final badge in fresh) {
      (analytics ?? Analytics.instance).event('badge_earned', {
        'badge': badge.id,
      });
      _earned.add(badge);
    }
    return fresh;
  });
}
