import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/ai_game_screen.dart';
import 'package:purechess/features/game/new_game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';

class UnreadablePreferences extends InMemorySharedPreferencesStore {
  UnreadablePreferences() : super.empty();

  @override
  Future<Map<String, Object>> getAll() async => throw StateError('Read failed');
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> open(
    WidgetTester tester, {
    SharedPreferences? preferences,
  }) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(home: NewGameScreen(prefs: preferences ?? prefs)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('restores color and manual level while recommendation changes', (
    tester,
  ) async {
    await prefs.setInt(AiDifficulty.preferenceKey, 3);
    await open(tester);
    await tester.tap(find.text('黑棋 · 后走'));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(8);
    await tester.pumpAndSettle();
    await prefs.reload();
    expect(prefs.getString('newGame.color'), 'black');
    expect(prefs.getInt('newGame.level'), 8);
    await prefs.setInt(AiDifficulty.preferenceKey, 5);
    await open(tester);
    expect(find.text('难度 · 8 / 10'), findsOneWidget);
    expect(find.textContaining('推荐第 5 档'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<chess.Color>>(
            find.byType(SegmentedButton<chess.Color>),
          )
          .selected,
      {chess.Color.black},
    );
  });

  testWidgets('unselected difficulty keeps following adaptive recommendation', (
    tester,
  ) async {
    await prefs.setInt(AiDifficulty.preferenceKey, 2);
    await open(tester);
    await tester.tap(find.text('黑棋 · 后走'));
    await tester.pumpAndSettle();
    expect(prefs.containsKey('newGame.level'), isFalse);
    await prefs.setInt(AiDifficulty.preferenceKey, 7);
    await open(tester);
    expect(find.text('难度 · 7 / 10'), findsOneWidget);
    expect(prefs.containsKey('newGame.level'), isFalse);
  });

  testWidgets('malformed preferences use defaults without blocking play', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'newGame.color': 'purple',
      'newGame.level': 99,
      AiDifficulty.preferenceKey: 'bad',
    });
    await open(tester, preferences: await SharedPreferences.getInstance());
    expect(find.text('难度 · 1 / 10'), findsOneWidget);
    await tester.tap(find.text('开始对弈'));
    await tester.pumpAndSettle();
    final config = tester
        .widget<AiGameScreen>(find.byType(AiGameScreen))
        .config;
    expect(config.humanColor, chess.Color.white);
    expect(config.difficulty, 1);
  });

  testWidgets('platform read failure leaves the start button usable', (
    tester,
  ) async {
    SharedPreferencesStorePlatform.instance = UnreadablePreferences();
    SharedPreferences.resetStatic();
    await tester.pumpWidget(const MaterialApp(home: NewGameScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('已使用默认设置'), findsOneWidget);
    await tester.tap(find.text('开始对弈'));
    await tester.pumpAndSettle();
    expect(find.byType(AiGameScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed preference write reports feedback but does not block play',
    (tester) async {
      final platform = FailingPreferencesStore()
        ..failKey = 'flutter.newGame.level';
      SharedPreferencesStorePlatform.instance = platform;
      SharedPreferences.resetStatic();
      prefs = await SharedPreferences.getInstance();
      await open(tester);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(4);
      await tester.pumpAndSettle();
      expect(find.text('偏好未保存，不影响本次开局。'), findsOneWidget);
      await tester.tap(find.text('开始对弈'));
      await tester.pumpAndSettle();
      expect(find.byType(AiGameScreen), findsOneWidget);
      await open(tester);
      expect(find.text('难度 · 1 / 10'), findsOneWidget);
    },
  );
}
