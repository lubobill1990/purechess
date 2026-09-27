import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/features/home/learning_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final today = DateTime(2026, 9, 28);

  Future<SharedPreferences> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test(
    'missing providers leave a first-lesson placeholder and write nothing',
    () async {
      final store = await prefs({});
      final progress = LearningProgress.read(store, today);
      expect(progress.nextLesson, 1);
      expect(progress.graduated, false);
      expect(progress.tutorialAvailable, false);
      expect(progress.dailyAvailable, false);
      expect(progress.error, isNull);
      expect(store.getKeys(), isEmpty);
    },
  );

  for (final completed in [0, 1, 17, 18]) {
    test('integer tutorial contract: $completed completed', () async {
      final store = await prefs({'tutorial_progress': completed});
      final progress = LearningProgress.read(store, today);
      expect(progress.completedLessons, completed);
      expect(progress.nextLesson, completed == 18 ? 18 : completed + 1);
      expect(progress.graduated, completed == 18);
      expect(store.getInt('tutorial_progress'), completed);
    });
  }

  test('JSON counts can explicitly carry a different course length', () async {
    final store = await prefs({
      'tutorial_progress': jsonEncode({'completed': 20, 'total': 20}),
    });
    final progress = LearningProgress.read(store, today);
    expect(progress.graduated, true);
    expect(progress.totalLessons, 20);
  });

  test(
    'daily key is local calendar YYYYMMDD and never borrows yesterday',
    () async {
      final store = await prefs({'daily_20260927': 10, 'daily_20260928': 3});
      expect(LearningProgress.dailyKey(DateTime(2026, 1, 2)), 'daily_20260102');
      expect(LearningProgress.read(store, today).dailySolved, 3);
      expect(
        LearningProgress.read(
          store,
          today.add(const Duration(days: 1)),
        ).dailyAvailable,
        false,
      );
    },
  );

  test(
    'JSON daily progress displays completed and total independently',
    () async {
      final store = await prefs({
        'daily_20260928': '{"completed":4,"total":10}',
      });
      final progress = LearningProgress.read(store, today);
      expect(progress.dailySolved, 4);
      expect(progress.dailyTotal, 10);
    },
  );

  for (final bad in <Object>[
    -1,
    19,
    true,
    '{bad json',
    '{"completed":1,"total":0}',
    '{"completed":"18"}',
  ]) {
    test(
      'invalid progress is visible and never treated as graduation: $bad',
      () async {
        final store = await prefs({'tutorial_progress': bad});
        final progress = LearningProgress.read(store, today);
        expect(progress.error, isNotNull);
        expect(progress.graduated, false);
        expect(progress.tutorialAvailable, false);
        expect(store.get('tutorial_progress'), bad);
      },
    );
  }

  test('bad daily data does not discard valid tutorial graduation', () async {
    final store = await prefs({'tutorial_progress': 18, 'daily_20260928': 12});
    final progress = LearningProgress.read(store, today);
    expect(progress.graduated, true);
    expect(progress.dailyAvailable, false);
    expect(progress.error, isNotNull);
  });
}
