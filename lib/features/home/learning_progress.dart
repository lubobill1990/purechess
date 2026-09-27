import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Read-only boundary with the tutorial and daily-puzzle features.
class LearningProgress {
  const LearningProgress({
    this.completedLessons = 0,
    this.totalLessons = 18,
    this.dailySolved = 0,
    this.dailyTotal = 10,
    this.tutorialAvailable = false,
    this.dailyAvailable = false,
    this.error,
  });

  final int completedLessons;
  final int totalLessons;
  final int dailySolved;
  final int dailyTotal;
  final bool tutorialAvailable;
  final bool dailyAvailable;
  final String? error;

  bool get graduated => completedLessons == totalLessons;
  int get nextLesson => graduated ? totalLessons : completedLessons + 1;

  static String dailyKey(DateTime date) =>
      'daily_${date.year}${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  static LearningProgress read(SharedPreferences prefs, DateTime now) {
    final tutorial = prefs.get('tutorial_progress');
    final daily = prefs.get(dailyKey(now));
    final lessons = _counts(tutorial, 18);
    final puzzles = _counts(daily, 10);
    return LearningProgress(
      completedLessons: lessons?.$1 ?? 0,
      totalLessons: lessons?.$2 ?? 18,
      dailySolved: puzzles?.$1 ?? 0,
      dailyTotal: puzzles?.$2 ?? 10,
      tutorialAvailable: lessons != null,
      dailyAvailable: puzzles != null,
      error:
          (tutorial != null && lessons == null) ||
              (daily != null && puzzles == null)
          ? '学习进度格式无法识别，暂不显示已完成数量。'
          : null,
    );
  }

  static (int, int)? _counts(Object? value, int defaultTotal) {
    if (value == null) return null;
    Object? decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    int? completed;
    var total = defaultTotal;
    if (decoded is int) {
      completed = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final count = decoded['completed'];
      final size = decoded['total'];
      if (count is int) completed = count;
      if (size != null) {
        if (size is! int) return null;
        total = size;
      }
    }
    if (completed == null || total <= 0 || completed < 0 || completed > total) {
      return null;
    }
    return (completed, total);
  }
}
