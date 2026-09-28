import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/app_theme.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/main.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/ai_game_screen.dart';
import 'package:purechess/features/game/game_persistence.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/preferences_store.dart';
import 'support/fake_reminder_backend.dart';

void main() {
  late Directory dir;
  late SharedPreferences prefs;
  late Analytics analytics;
  late FailingPreferencesStore store;

  setUp(() async {
    store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    prefs = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('purechess_privacy_test_');
    analytics = Analytics.testing(directory: dir);
    await analytics.init(prefs);
  });

  tearDown(() async {
    analytics.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      MyApp(
        prefs: prefs,
        analytics: analytics,
        reminderBackend: FakeReminderBackend()..supported = false,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('system appearance updates home and pushed settings together', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await analytics.savePrivacyChoice(false, prefs);
    await launch(tester);
    for (final brightness in [Brightness.dark, Brightness.light]) {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          brightness;
      await tester.pumpAndSettle();
      final expected = brightness == Brightness.dark
          ? buildDarkTheme()
          : buildLightTheme();
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).colorScheme,
        expected.colorScheme,
      );
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold).last)).colorScheme,
        expected.colorScheme,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'first launch blocks dismissal and exposes policy before choice',
    (tester) async {
      await launch(tester);
      expect(find.text('隐私告知'), findsOneWidget);
      expect(analytics.consentGranted, isFalse);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('隐私告知'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('隐私告知'), findsOneWidget);
      await tester.tap(find.text('阅读隐私政策'));
      await tester.pumpAndSettle();
      expect(find.text('纯弈国象隐私说明（占位稿）'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('隐私告知'), findsOneWidget);
    },
  );

  testWidgets(
    'startup resume restores AI config and position from preferences',
    (tester) async {
      await analytics.savePrivacyChoice(false, prefs);
      final session = GameSession()
        ..play(chess.Move.fromUci('e2e4'))
        ..play(chess.Move.fromUci('e7e5'));
      final store = GameStore(prefs);
      await store.save(session, config: AiGameConfig(difficulty: 6));
      store.dispose();
      await launch(tester);
      await tester.tap(find.text('继续对局'));
      await tester.pumpAndSettle();
      final game = tester.widget<AiGameScreen>(find.byType(AiGameScreen));
      expect(game.resumed, isTrue);
      expect(game.config.difficulty, 6);
      expect(game.session!.board.toFen(), session.board.toFen());
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍后继续'));
      await tester.pumpAndSettle();
      expect(find.text('继续对局'), findsOneWidget);
    },
  );

  testWidgets(
    'local game can leave, resume, abandon and rematch without shifts',
    (tester) async {
      await analytics.savePrivacyChoice(false, prefs);
      await launch(tester);
      await tester.tap(find.text('双人对弈'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('square-e2')));
      await tester.tap(find.byKey(const ValueKey('square-e4')));
      await tester.pumpAndSettle();
      final fen = tester
          .widget<ChessBoard>(find.byType(ChessBoard))
          .board
          .toFen();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍后继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续对局'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).board.toFen(),
        fen,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃并离开'));
      await tester.pumpAndSettle();
      expect(find.text('继续对局'), findsNothing);
      expect(prefs.containsKey(GameStore.preferenceKey), isFalse);
      await tester.tap(find.text('双人对弈'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(ChessBoard));
      await tester.tap(find.byKey(const ValueKey('white-resign')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认认输'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ChessBoard)), rect);
      expect(prefs.containsKey(GameStore.preferenceKey), isFalse);
      await tester.tap(find.text('再来一局'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).board.plyCount,
        0,
      );
    },
  );

  testWidgets('corrupt startup save falls back to new game', (tester) async {
    await analytics.savePrivacyChoice(false, prefs);
    await prefs.setInt('tutorial_progress', 18);
    await prefs.setString(GameStore.preferenceKey, '{"version":99}');
    await launch(tester);
    expect(find.text('继续对局'), findsNothing);
    expect(find.text('新对局'), findsOneWidget);
    expect(prefs.containsKey(GameStore.preferenceKey), isFalse);
  });

  for (final ai in [true, false]) {
    testWidgets('resume emits one safe event without a new start (AI: $ai)', (
      tester,
    ) async {
      await prefs.setBool(Analytics.privacyAcceptedKey, true);
      final store = GameStore(prefs);
      await store.save(
        GameSession()
          ..play(chess.Move.fromUci('e2e4'))
          ..play(chess.Move.fromUci('e7e5')),
        config: ai ? AiGameConfig(difficulty: 4) : null,
      );
      store.dispose();
      await launch(tester);
      await tester.tap(find.text('继续对局'));
      await tester.pumpAndSettle();
      await tester.pump();
      final events = File('${dir.path}/pending_events.jsonl')
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, dynamic>);
      final resumes = events.where((event) => event['name'] == 'game_resume');
      expect(resumes, hasLength(1));
      expect(resumes.single['params']['mode'], ai ? 'ai' : 'local');
      expect(resumes.single['params']['move_count'], 2);
      expect(events.where((event) => event['name'] == 'game_start'), isEmpty);
    });
  }

  testWidgets('accept persists choice and opens local game from home', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('隐私告知'), findsNothing);
    expect(prefs.getBool(Analytics.privacyAcceptedKey), isTrue);
    expect(analytics.consentGranted, isTrue);
    expect(find.text('双人对弈'), findsOneWidget);
    await tester.tap(find.text('双人对弈'));
    await tester.pumpAndSettle();
    expect(find.text('面对面对弈'), findsOneWidget);
    expect(find.byKey(const ValueKey('square-e2')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('双人对弈'), findsOneWidget);
  });

  testWidgets(
    'decline keeps app usable and settings can re-enable statistics',
    (tester) async {
      await launch(tester);
      await tester.tap(find.text('关闭统计并继续'));
      await tester.pumpAndSettle();
      expect(analytics.enabled, isFalse);
      expect(
        File('${dir.path}/pending_events.jsonl').readAsStringSync(),
        isEmpty,
      );
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('analytics-toggle')),
            )
            .value,
        false,
      );
      await tester.tap(find.byKey(const ValueKey('analytics-toggle')));
      await tester.pumpAndSettle();
      expect(analytics.enabled, isTrue);
      expect(prefs.getBool(Analytics.enabledKey), isTrue);
      await tester.tap(find.byKey(const ValueKey('analytics-toggle')));
      await tester.pumpAndSettle();
      expect(analytics.enabled, isFalse);
      await tester.ensureVisible(find.text('隐私政策'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('隐私政策'));
      await tester.pumpAndSettle();
      expect(find.text('纯弈国象隐私说明（占位稿）'), findsOneWidget);
    },
  );

  testWidgets('saved decline skips first-launch dialog on next app mount', (
    tester,
  ) async {
    await analytics.savePrivacyChoice(false, prefs);
    await launch(tester);
    expect(find.text('隐私告知'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
  });

  testWidgets('failed privacy save keeps dialog open and allows retry', (
    tester,
  ) async {
    store.failKey = 'flutter.${Analytics.privacyAcceptedKey}';
    await launch(tester);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('隐私选择保存失败，请重试。确认前不会发送统计。'), findsOneWidget);
    expect(analytics.consentGranted, isFalse);
    expect(prefs.getBool(Analytics.privacyAcceptedKey), isNull);
    store.failKey = null;
    await tester.tap(find.text('关闭统计并继续'));
    await tester.pumpAndSettle();
    expect(find.text('隐私告知'), findsNothing);
    expect(analytics.enabled, isFalse);
  });

  testWidgets('failed settings save displays error and does not opt in', (
    tester,
  ) async {
    await analytics.savePrivacyChoice(false, prefs);
    await launch(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    store.failKey = 'flutter.${Analytics.enabledKey}';
    await tester.tap(find.byKey(const ValueKey('analytics-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('统计设置保存失败，请重试'), findsOneWidget);
    expect(analytics.enabled, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('analytics-toggle')),
          )
          .value,
      false,
    );
  });

  testWidgets('lifecycle transitions preserve queue while consent is absent', (
    tester,
  ) async {
    await launch(tester);
    final file = File('${dir.path}/pending_events.jsonl');
    final before = file.readAsStringSync();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(file.readAsStringSync(), before);
    expect(analytics.consentGranted, isFalse);
  });
}
