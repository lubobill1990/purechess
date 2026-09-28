import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/features/achievements/achievements.dart';
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/game_controller.dart';
import 'package:purechess/features/game/game_screen.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:purechess/features/puzzle/puzzle_repository.dart';
import 'package:purechess/features/puzzle/puzzle_screen.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';
import '../game/fake_game_engine.dart';
import '../puzzle/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  AchievementData data() => AchievementData.decode(prefs.get('achievements'));

  GameController ai({
    GameSession? session,
    chess.Color color = chess.Color.white,
  }) {
    final engine = FakeGameEngine();
    final controller = GameController(
      config: AiGameConfig(humanColor: color),
      rating: AiDifficulty(prefs),
      engine: engine,
      session: session,
    );
    addTearDown(() async {
      controller.dispose();
      await engine.dispose();
    });
    return controller;
  }

  test('AI resignation records once, resets win streak; reopened terminal game does not record', () async {
    await prefs.setString(
      'achievements',
      AchievementData(
        counters: {
          'gamesFinished': 2,
          'winsVsAi': 2,
          'winStreak': 2,
          'bestWinStreak': 2,
        },
      ).encode(),
    );
    final game = ai();
    await game.start();
    await game.resign();
    await game.resign();
    await game.saveAchievement();
    expect(data().counters['gamesFinished'], 3);
    expect(data().counters['winsVsAi'], 2);
    expect(data().counters['winStreak'], 0);
    expect(data().earned, isNot(contains('win_streak_3')));
    final restored = ai(session: game.session);
    await restored.start();
    expect(data().counters['gamesFinished'], 3);
  });

  test('black player checkmate counts as AI win, not AI color', () async {
    final game = ai(
      color: chess.Color.black,
      session: GameSession(initialFen: '8/8/8/8/8/6k1/5q2/7K b - - 0 1'),
    );
    await game.start();
    await game.play(chess.Move.fromUci('f2g2'));
    expect(game.session.finished, isTrue);
    expect(data().counters['winsVsAi'], 1);
    expect(data().earned, contains('first_win'));
  });

  test('achievement save failure is separate from rating and retry counts only once', () async {
    final store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    await prefs.reload();
    store.failKey = 'flutter.achievements';
    final game = ai();
    await game.start();
    await game.resign();
    expect(game.achievementError, '成就未保存，请重试');
    expect(game.ratingError, isNull);
    expect(prefs.get('achievements'), isNull);
    store.failKey = null;
    await game.saveAchievement();
    await game.saveAchievement();
    expect(game.achievementError, isNull);
    expect(data().counters['gamesFinished'], 1);
  });

  testWidgets(
    'local resignation and save retry count one game, never an AI victory',
    (tester) async {
      final store = FailingPreferencesStore();
      SharedPreferencesStorePlatform.instance = store;
      await prefs.reload();
      store.failKey = 'flutter.achievements';
      await tester.pumpWidget(MaterialApp(home: GameScreen(prefs: prefs)));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(ChessBoard));
      await tester.tap(find.byKey(const ValueKey('white-resign')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认认输'));
      await tester.pumpAndSettle();
      expect(find.text('成就未保存，请重试保存'), findsOneWidget);
      expect(prefs.get('achievements'), isNull);
      store.failKey = null;
      await tester.tap(find.text('成就未保存，请重试保存'));
      await tester.pumpAndSettle();
      expect(data().counters['gamesFinished'], 1);
      expect(data().counters['winsVsAi'], 0);
      expect(tester.getRect(find.byType(ChessBoard)), rect);
      await tester.tap(find.byTooltip('翻转棋盘'));
      await tester.pumpAndSettle();
      expect(data().counters['gamesFinished'], 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'puzzle progress saved before achievement failure can be retried',
    (tester) async {
      final store = FailingPreferencesStore();
      SharedPreferencesStorePlatform.instance = store;
      await prefs.reload();
      final repository = PuzzleRepository(prefs: prefs, catalog: catalog());
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PuzzleSolveScreen(repository: repository, ids: const ['p0']),
        ),
      );
      await tester.pumpAndSettle();
      store.failKey = 'flutter.achievements';
      for (final move in ['e2e4', 'g1f3']) {
        tester
            .widget<ChessBoard>(find.byType(ChessBoard))
            .onMove(chess.Move.fromUci(move));
        await tester.pumpAndSettle();
      }
      expect(repository.solved, {'p0'});
      expect(prefs.get('achievements'), isNull);
      expect(find.text('进度保存失败，请重试保存'), findsOneWidget);
      store.failKey = null;
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(data().earned.keys, ['first_day']);
      expect(AchievementProgress.read(prefs).puzzles, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
