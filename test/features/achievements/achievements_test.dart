import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/app_logger.dart';
import 'package:purechess/features/achievements/achievements.dart';
import 'package:purechess/features/settings/backup_data.dart';
import 'package:purechess/features/tutorial/tutorial_level.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late DateTime now;
  late Achievements service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 9, 28, 12);
    service = Achievements(prefs, now: () => now);
  });

  Future<void> progress({
    int puzzles = 0,
    int tutorial = 0,
    int days = 0,
  }) async {
    await prefs.setInt('tutorial_progress', tutorial);
    final ids = List.generate(puzzles, (i) => 'p$i');
    final daily = <String, List<String>>{};
    for (var i = 0; i < days; i++) {
      final key = 'daily_${achievementDay(DateTime(2026, 1, i + 1))}';
      final ten = List.generate(10, (n) => 'p$n');
      await prefs.setString(key, jsonEncode(ten));
      daily[key] = ten;
    }
    await prefs.setString(
      'puzzle_progress_v1',
      jsonEncode({'solved': ids, 'mistakes': <String>[], 'dailySolved': daily}),
    );
  }

  test(
    'first activity, same day, yesterday and gap use local calendar dates',
    () async {
      await service.record(const ActivityEvent.puzzleSolved());
      var data = await service.read();
      expect(data.lastActiveDay, '20260928');
      expect(data.streak, 1);
      expect(data.activeToday(now), isTrue);
      expect(data.earned, {'first_day': '20260928'});
      now = DateTime(2026, 9, 28, 23, 59);
      await service.record(const ActivityEvent.tutorialLevelDone());
      expect((await service.read()).streak, 1);
      now = DateTime(2026, 9, 29);
      await service.record(const ActivityEvent.puzzleSolved());
      data = await service.read();
      expect(data.streak, 2);
      expect(data.bestStreak, 2);
      expect(data.currentStreak(DateTime(2026, 9, 30)), 2);
      expect(data.activeToday(DateTime(2026, 9, 30)), isFalse);
      expect(data.currentStreak(DateTime(2026, 10, 1)), 0);
      now = DateTime(2026, 10, 1);
      await service.record(const ActivityEvent.puzzleSolved());
      data = await service.read();
      expect(data.streak, 1);
      expect(data.bestStreak, 2);
    },
  );

  for (final pair in [
    (DateTime(2026, 1, 31, 23, 59), DateTime(2026, 2, 1)),
    (DateTime(2026, 12, 31, 23, 59), DateTime(2027, 1, 1)),
    (DateTime(2028, 2, 28), DateTime(2028, 2, 29)),
    (DateTime(2028, 2, 29), DateTime(2028, 3, 1)),
  ]) {
    test('calendar rollover ${pair.$1} -> ${pair.$2}', () async {
      now = pair.$1;
      await service.record(const ActivityEvent.puzzleSolved());
      now = pair.$2;
      await service.record(const ActivityEvent.puzzleSolved());
      expect((await service.read()).streak, 2);
    });
  }

  test('UTC injected clock is converted to device local date', () async {
    now = DateTime.utc(2026, 12, 31, 23, 30);
    await service.record(const ActivityEvent.puzzleSolved());
    expect((await service.read()).lastActiveDay, achievementDay(now.toLocal()));
  });

  for (final badge in achievementBadges.where((b) => b.id != 'first_day')) {
    test(
      '${badge.id} is locked below threshold, earned at threshold only once',
      () async {
        Future<void> seed(int value) async {
          await progress(
            puzzles: badge.metric == 'puzzles' ? value : 0,
            tutorial: badge.metric == 'tutorial' ? value : 0,
          );
          await prefs.setString(
            AchievementData.preferenceKey,
            AchievementData(
              lastActiveDay: achievementDay(now),
              streak: 1,
              bestStreak: badge.metric == 'bestStreak' ? value : 1,
              counters: AchievementData.counterKeys.contains(badge.metric)
                  ? {badge.metric: value}
                  : {},
              earned: {'first_day': '20260101'},
            ).encode(),
          );
        }

        await seed(badge.target - 1);
        expect(
          (await service.record(const ActivityEvent.puzzleSolved()))
              .map((b) => b.id),
          isNot(contains(badge.id)),
        );
        expect((await service.read()).earned, isNot(contains(badge.id)));
        await seed(badge.target);
        final fresh = await service.record(const ActivityEvent.puzzleSolved());
        expect(fresh.map((b) => b.id), contains(badge.id));
        expect((await service.read()).earned[badge.id], '20260928');
        expect(
          await service.record(const ActivityEvent.puzzleSolved()),
          isEmpty,
        );
        expect(
          await Achievements(prefs).record(const ActivityEvent.puzzleSolved()),
          isEmpty,
        );
      },
    );
  }

  test(
    'catalog has exactly the fixed 15 IDs and graduation matches real tutorial',
    () async {
      expect(achievementBadges.map((b) => b.id).toSet(), {
        'first_day',
        'streak_7',
        'streak_30',
        'streak_100',
        'streak_365',
        'tutorial_grad',
        'first_win',
        'win_streak_3',
        'games_10',
        'games_100',
        'daily_7',
        'daily_30',
        'puzzles_10',
        'puzzles_50',
        'puzzles_200',
      });
      expect(
        achievementBadges.singleWhere((b) => b.id == 'tutorial_grad').target,
        (await TutorialCatalog.load()).levels.length,
      );
    },
  );

  test(
    'AI wins, draws/losses, local games and concurrent calls preserve counters',
    () async {
      await service.record(const ActivityEvent.gameFinished(won: true));
      await service.record(
        const ActivityEvent.gameFinished(won: false, versusAi: false),
      );
      expect((await service.read()).counters['winStreak'], 1);
      await service.record(const ActivityEvent.gameFinished(won: false));
      expect((await service.read()).counters['winStreak'], 0);
      final results = await Future.wait(
        List.generate(
          3,
          (_) => service.record(const ActivityEvent.gameFinished(won: true)),
        ),
      );
      final data = await service.read();
      expect(data.counters['gamesFinished'], 6);
      expect(data.counters['winsVsAi'], 4);
      expect(data.counters['bestWinStreak'], 3);
      expect(
        results.expand((badges) => badges).where((b) => b.id == 'win_streak_3'),
        hasLength(1),
      );
      await prefs.reload();
      expect(
        AchievementData.decode(prefs.get('achievements')).encode(),
        data.encode(),
      );
      final raw = jsonDecode(data.encode()) as Map;
      expect(raw.keys.toSet(), {
        'lastActiveDay',
        'streak',
        'bestStreak',
        'counters',
        'earned',
      });
      expect((raw['counters'] as Map).keys, isNot(contains('puzzles')));
    },
  );

  test(
    'daily completion uses persisted sets, not repeated attempts or launches',
    () async {
      await progress(puzzles: 10, days: 7);
      await service.record(const ActivityEvent.dailyCompleted());
      expect((await service.read()).counters['dailyCompleted'], 7);
      expect((await service.read()).earned, contains('daily_7'));
      await service.record(const ActivityEvent.dailyCompleted());
      await Achievements(prefs).record(const ActivityEvent.dailyCompleted());
      expect((await service.read()).counters['dailyCompleted'], 7);
      await progress(puzzles: 10, days: 30);
      await service.record(const ActivityEvent.dailyCompleted());
      expect((await service.read()).counters['dailyCompleted'], 30);
      expect((await service.read()).earned, contains('daily_30'));
      expect(AchievementProgress.read(prefs).puzzles, 10);
    },
  );

  for (final raw in [
    '{broken',
    '[]',
    '{}',
    '{"streak":-1}',
    42,
    AchievementData(lastActiveDay: '20260230').encode(),
    AchievementData(earned: {'first_day': 'not-a-date'}).encode(),
  ]) {
    test('corrupt data resets durably and reports: $raw', () async {
      if (raw is int) {
        await prefs.setInt('achievements', raw);
      } else {
        await prefs.setString('achievements', raw as String);
      }
      expect((await service.read()).encode(), AchievementData().encode());
      await prefs.reload();
      expect(prefs.getString('achievements'), AchievementData().encode());
      expect(
        AppLogger.instance.recent.join('\n'),
        contains('achievements_decode'),
      );
      await service.record(const ActivityEvent.puzzleSolved());
      expect((await service.read()).earned.keys, ['first_day']);
    });
  }

  test('failed writes emit no badge and retry does not double count', () async {
    final store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    await prefs.reload();
    final earned = <String>[];
    final subscription = service.earned.listen((badge) => earned.add(badge.id));
    addTearDown(subscription.cancel);
    store.failKey = 'flutter.achievements';
    await expectLater(
      service.record(const ActivityEvent.gameFinished(won: true)),
      throwsStateError,
    );
    expect(prefs.get('achievements'), isNull);
    expect(earned, isEmpty);
    store.failKey = null;
    await service.record(const ActivityEvent.gameFinished(won: true));
    expect((await service.read()).counters['gamesFinished'], 1);
    expect(earned, ['first_day', 'first_win']);
  });

  test(
    'backup round trip and merge use maxima, union and earliest award date',
    () {
      final local = AchievementData(
        lastActiveDay: '20260927',
        streak: 5,
        bestStreak: 30,
        counters: {
          'gamesFinished': 100,
          'winsVsAi': 40,
          'winStreak': 2,
          'bestWinStreak': 8,
          'dailyCompleted': 7,
        },
        earned: {'first_day': '20260101', 'games_100': '20260927'},
      );
      final incoming = AchievementData(
        lastActiveDay: '20260928',
        streak: 7,
        bestStreak: 10,
        counters: {
          'gamesFinished': 80,
          'winsVsAi': 50,
          'winStreak': 3,
          'bestWinStreak': 6,
          'dailyCompleted': 30,
        },
        earned: {'first_day': '20260201', 'daily_30': '20260928'},
      );
      expect(BackupData.includes('achievements'), isTrue);
      final archive = BackupData.create({
        'achievements': incoming.encode(),
      }, {});
      final decoded = BackupData.decode(archive.encode());
      final merged = BackupData.mergePreferences({
        'achievements': local.encode(),
      }, decoded.preferences);
      final data = AchievementData.decode(merged['achievements']);
      expect(data.lastActiveDay, '20260928');
      expect(data.streak, 7);
      expect(data.bestStreak, 30);
      expect(data.counters, {
        'gamesFinished': 100,
        'winsVsAi': 50,
        'winStreak': 3,
        'bestWinStreak': 8,
        'dailyCompleted': 30,
      });
      expect(data.earned, {
        'first_day': '20260101',
        'games_100': '20260927',
        'daily_30': '20260928',
      });
      expect(
        jsonDecode(AchievementData.merge(incoming, local).encode()),
        jsonDecode(data.encode()),
      );
      expect(AchievementData.merge(data, data).encode(), data.encode());
      expect(
        () => BackupData.create({'achievements': '{}'}, {}),
        throwsFormatException,
      );
      expect(
        BackupData.mergePreferences({}, decoded.preferences),
        decoded.preferences,
      );
    },
  );
}
