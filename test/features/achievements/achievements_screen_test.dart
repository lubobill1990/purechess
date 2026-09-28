import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/play_feedback.dart';
import 'package:purechess/app/router.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/features/achievements/achievements.dart';
import 'package:purechess/features/achievements/achievements_screen.dart';
import 'package:purechess/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets(
    'wall renders earned date, locked conditions and real statistics',
    (tester) async {
      await prefs.setString(
        'achievements',
        AchievementData(
          lastActiveDay: '20260928',
          streak: 3,
          bestStreak: 7,
          counters: {'gamesFinished': 12, 'winsVsAi': 4},
          earned: {'first_day': '20260926'},
        ).encode(),
      );
      await prefs.setString(
        'puzzle_progress_v1',
        jsonEncode({
          'solved': ['a', 'b'],
          'mistakes': <String>[],
          'dailySolved': <String, Object>{},
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            prefs: prefs,
            now: () => DateTime(2026, 9, 28, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('连续打卡 3 天'), findsOneWidget);
      expect(find.text('今日已打卡'), findsOneWidget);
      expect(find.text('最佳连续 7 天'), findsOneWidget);
      expect(find.text('累计对局 12 局'), findsOneWidget);
      expect(find.text('战胜 AI 4 局'), findsOneWidget);
      expect(find.text('累计答对 2 题'), findsOneWidget);
      expect(find.text('获得于 2026-09-26'), findsOneWidget);
      expect(find.text('连续打卡 7 天'), findsOneWidget);
      final earned = tester.widget<Card>(
        find.byKey(const ValueKey('badge-first_day-earned')),
      );
      final locked = tester.widget<Card>(
        find.byKey(const ValueKey('badge-streak_7-locked')),
      );
      expect(earned.color, isNot(locked.color));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('wall refreshes at midnight and stale streak displays zero', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 28, 23, 59, 59);
    await prefs.setString(
      'achievements',
      AchievementData(
        lastActiveDay: '20260927',
        streak: 7,
        bestStreak: 7,
      ).encode(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(prefs: prefs, now: () => now),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('achievement-streak')))
          .data,
      '连续打卡 7 天',
    );
    now = DateTime(2026, 9, 29);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('连续打卡 0 天'), findsOneWidget);
    expect(find.textContaining('今日未打卡'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'wall supports 320px, dark mode and double-size text through final badge',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              platformBrightness: Brightness.dark,
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: AchievementsScreen(prefs: prefs),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('战术百炼'),
        400,
        maxScrolls: 40,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('累计做对 200 道不同战术题'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('home achievement entry uses named route', (tester) async {
    final dir = Directory.systemTemp.createTempSync('badge-route-');
    final analytics = Analytics.testing(directory: dir);
    addTearDown(() {
      analytics.dispose();
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        routes: AppRouter.routes(prefs: prefs, analytics: analytics),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.byTooltip('成就'));
    await tester.pumpAndSettle();
    expect(find.byType(AchievementsScreen), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(AchievementsScreen)))!
          .settings
          .name,
      '/achievements',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'multiple earned badges queue without moving board or emitting celebration telemetry',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('badge-queue-');
      final analytics = Analytics.testing(directory: directory);
      addTearDown(() {
        analytics.dispose();
        directory.deleteSync(recursive: true);
      });
      await tester.runAsync(() => analytics.prepare(prefs));
      final boardKey = GlobalKey();
      final session = Object();
      Widget host(FeedbackResult result) => MaterialApp(
        home: Scaffold(
          body: PlayFeedback(
            session: session,
            board: Board(),
            source: 'ai',
            prefs: prefs,
            analytics: analytics,
            result: result,
            celebration: result == FeedbackResult.win ? '你赢了！' : null,
            child: SizedBox(key: boardKey, width: 320, height: 320),
          ),
        ),
      );
      await tester.pumpWidget(host(FeedbackResult.playing));
      final rect = tester.getRect(find.byKey(boardKey));
      await tester.pumpWidget(host(FeedbackResult.win));
      await Achievements.of(prefs).record(
        const ActivityEvent.gameFinished(won: true),
        analytics: analytics,
      );
      await tester.pump();
      expect(find.text('你赢了！'), findsOneWidget);
      expect(find.byType(CelebrationBadge), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('获得奖章 · 落子启程'), findsOneWidget);
      expect(find.byType(CelebrationBadge), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('获得奖章 · 首胜'), findsOneWidget);
      expect(tester.getRect(find.byKey(boardKey)), rect);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(CelebrationBadge), findsNothing);
      final events = File(
        '${directory.path}${Platform.pathSeparator}pending_events.jsonl',
      ).readAsLinesSync().map((line) => jsonDecode(line) as Map).toList();
      expect(
        events.where((event) => event['name'] == 'celebrate_shown'),
        hasLength(1),
      );
      expect(
        events
            .where((event) => event['name'] == 'badge_earned')
            .map((event) => (event['params'] as Map)['badge']),
        ['first_day', 'first_win'],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
