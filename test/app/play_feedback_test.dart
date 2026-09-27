import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/play_feedback.dart';
import 'package:purechess/app/sound.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/ai_game_screen.dart';
import 'package:purechess/features/game/game_screen.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:purechess/features/puzzle/puzzle_repository.dart';
import 'package:purechess/features/puzzle/puzzle_screen.dart';
import 'package:purechess/features/settings/settings.dart';
import 'package:purechess/features/tutorial/tutorial_controller.dart';
import 'package:purechess/features/tutorial/tutorial_engine.dart';
import 'package:purechess/features/tutorial/tutorial_level.dart';
import 'package:purechess/features/tutorial/tutorial_screen.dart';
import 'package:purechess/main.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../features/game/fake_game_engine.dart';
import '../features/puzzle/fixtures.dart';
import '../support/preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late List<String> sounds;
  late Directory directory;
  late Analytics analytics;
  late TutorialCatalog tutorialCatalog;
  setUpAll(() async {
    // Cache asset futures outside any individual widget test's fake clock.
    tutorialCatalog = await TutorialCatalog.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    directory = Directory.systemTemp.createTempSync('chess-feedback-');
    analytics = Analytics.testing(directory: directory);
    sounds = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemSound.play') {
            sounds.add(call.arguments as String);
          }
          return null;
        });
  });
  tearDown(() async {
    analytics.dispose();
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  List<Map<String, dynamic>> celebrations() =>
      File('${directory.path}${Platform.pathSeparator}pending_events.jsonl')
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .where((event) => event['name'] == 'celebrate_shown')
          .toList();

  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    bool loadAssets = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => analytics.init(prefs));
    await tester.pumpWidget(
      MaterialApp(theme: quietControlsTheme(ThemeData()), home: screen),
    );
    if (loadAssets) await tester.runAsync(TutorialCatalog.load);
    await tester.pumpAndSettle();
  }

  Future<void> move(WidgetTester tester, String uci) async {
    tester
        .widget<ChessBoard>(find.byType(ChessBoard))
        .onMove(chess.Move.fromUci(uci));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('settings switch persists, silences every cue and can reenable', (
    tester,
  ) async {
    await open(tester, SettingsScreen(prefs: prefs, analytics: analytics));
    final toggle = find.widgetWithText(SwitchListTile, '音效');
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    final service = SoundService(prefs: prefs);
    addTearDown(service.dispose);
    await service.play([ChessSound.victory], isCurrent: () => true);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(sounds.length, 1);
    expect(prefs.getBool(SoundService.enabledKey), isFalse);
    await service.play(ChessSound.values, isCurrent: () => true);
    expect(sounds.length, 1);
    await prefs.reload();
    expect(prefs.getBool(SoundService.enabledKey), isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await service.play([ChessSound.move], isCurrent: () => true);
    expect(sounds.length, 2);
    expect(find.text('匿名使用统计'), findsOneWidget);
  });

  testWidgets('failed sound preference write is visible and retryable', (
    tester,
  ) async {
    final store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    await prefs.reload();
    store.failKey = 'flutter.${SoundService.enabledKey}';
    await open(tester, SettingsScreen(prefs: prefs, analytics: analytics));
    final toggle = find.widgetWithText(SwitchListTile, '音效');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('音效设置保存失败，请重试'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    store.failKey = null;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(prefs.getBool(SoundService.enabledKey), isFalse);
  });

  testWidgets('real app mute includes navigation and default Material clicks', (
    tester,
  ) async {
    await prefs.setBool(Analytics.privacyAcceptedKey, true);
    await prefs.setBool(SoundService.enabledKey, false);
    await tester.runAsync(() => analytics.init(prefs));
    await tester.pumpWidget(MyApp(prefs: prefs, analytics: analytics));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '音效'))
          .value,
      isFalse,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('双人对弈'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('square-e2')));
    await tester.tap(find.byKey(const ValueKey('square-e4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('翻转棋盘'));
    await tester.pumpAndSettle();
    expect(sounds, isEmpty);
  });

  testWidgets('local moves and captures sound; undo and flip are silent', (
    tester,
  ) async {
    await open(tester, GameScreen(prefs: prefs, analytics: analytics));
    await move(tester, 'e2e4');
    await move(tester, 'd7d5');
    await move(tester, 'e4d5');
    expect(sounds.length, 4);
    await tester.tap(find.byKey(const ValueKey('black-undo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('翻转棋盘'));
    await tester.pumpAndSettle();
    expect(sounds.length, 4);
    expect(find.byType(CelebrationBadge), findsNothing);
    expect(celebrations(), isEmpty);
  });

  testWidgets('AI human win celebrates once, muted, without moving board', (
    tester,
  ) async {
    await prefs.setBool(SoundService.enabledKey, false);
    final session = GameSession(initialFen: '7k/5Q2/6K1/8/8/8/8/8 w - - 0 1');
    await open(
      tester,
      AiGameScreen(
        config: AiGameConfig(),
        rating: AiDifficulty(prefs),
        engine: FakeGameEngine(),
        session: session,
        analytics: analytics,
      ),
    );
    final rect = tester.getRect(find.byType(ChessBoard));
    await move(tester, 'f7g7');
    expect(find.text('你赢了！'), findsOneWidget);
    expect(sounds, isEmpty);
    expect(tester.getRect(find.byType(ChessBoard)), rect);
    expect(celebrations(), hasLength(1));
    expect(celebrations().single['params']['source'], 'ai');
    await tester.tap(find.byTooltip('翻转棋盘'));
    await tester.pumpAndSettle();
    expect(celebrations(), hasLength(1));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(CelebrationBadge), findsNothing);
  });

  testWidgets('AI mating reply gives terminal sound but no victory badge', (
    tester,
  ) async {
    final session = GameSession();
    for (final uci in ['f2f3', 'e7e5']) {
      session.play(chess.Move.fromUci(uci));
    }
    final engine = FakeGameEngine()
      ..replies.add((_) async => FakeGameEngine.result('d8h4'));
    await open(
      tester,
      AiGameScreen(
        config: AiGameConfig(),
        rating: AiDifficulty(prefs),
        engine: engine,
        session: session,
        analytics: analytics,
      ),
    );
    await move(tester, 'g2g4');
    expect(session.finished, isTrue);
    expect(sounds.length, 1 + soundPulses[ChessSound.checkmate]!.length);
    expect(find.byType(CelebrationBadge), findsNothing);
    expect(celebrations(), isEmpty);
  });

  testWidgets('agreement and loading a completed game do not celebrate', (
    tester,
  ) async {
    await open(tester, GameScreen(prefs: prefs, analytics: analytics));
    await tester.tap(find.byKey(const ValueKey('white-offer-draw')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('black-accept-draw')));
    await tester.pumpAndSettle();
    expect(find.byType(CelebrationBadge), findsNothing);
    expect(celebrations(), isEmpty);
    final ended = GameSession(initialFen: '7k/6Q1/6K1/8/8/8/8/8 b - - 1 1');
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          key: UniqueKey(),
          prefs: prefs,
          session: ended,
          analytics: analytics,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CelebrationBadge), findsNothing);
    expect(celebrations(), isEmpty);
  });

  testWidgets(
    'puzzle wrong, retry, all correct; save retry celebrates only once',
    (tester) async {
      final store = FailingPreferencesStore();
      SharedPreferencesStorePlatform.instance = store;
      await prefs.reload();
      final repository = PuzzleRepository(prefs: prefs, catalog: catalog());
      addTearDown(repository.dispose);
      await open(
        tester,
        PuzzleSolveScreen(
          repository: repository,
          ids: const ['p0'],
          analytics: analytics,
        ),
      );
      final rect = tester.getRect(find.byType(ChessBoard));
      await move(tester, 'd2d4');
      expect(sounds.length, soundPulses[ChessSound.incorrect]!.length);
      expect(find.byType(CelebrationBadge), findsNothing);
      await tester.tap(find.text('再试一次'));
      await tester.pumpAndSettle();
      await move(tester, 'e2e4');
      store.failKey = 'flutter.${PuzzleRepository.progressKey}';
      await move(tester, 'g1f3');
      expect(find.byType(CelebrationBadge), findsNothing);
      expect(find.text('进度保存失败，请重试保存'), findsOneWidget);
      final soundCount = sounds.length;
      store.failKey = null;
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(find.text('题集完成！'), findsOneWidget);
      expect(sounds.length, soundCount);
      expect(tester.getRect(find.byType(ChessBoard)), rect);
      expect(celebrations(), hasLength(1));
      expect(celebrations().single['params']['source'], 'puzzle');
    },
  );

  testWidgets(
    'tutorial celebrates saved completion once and clears on next level',
    (tester) async {
      final store = FailingPreferencesStore();
      SharedPreferencesStorePlatform.instance = store;
      await prefs.reload();
      final catalog = tutorialCatalog;
      final controller = TutorialController(
        catalog: catalog,
        prefs: prefs,
        engine: FakeEngine(),
        analytics: analytics,
      )..start(0);
      addTearDown(controller.dispose);
      await open(
        tester,
        TutorialPlayScreen(controller: controller, analytics: analytics),
      );
      final rect = tester.getRect(find.byType(ChessBoard));
      store.failKey = 'flutter.${TutorialController.progressKey}';
      await tester.tap(find.byKey(const ValueKey('square-d4')));
      await tester.tap(find.byKey(const ValueKey('square-e4')));
      await tester.pumpAndSettle();
      expect(find.byType(CelebrationBadge), findsNothing);
      expect(celebrations(), isEmpty);
      store.failKey = null;
      await tester.tap(find.text('重新保存'));
      await tester.pumpAndSettle();
      expect(find.text('本关完成！'), findsOneWidget);
      expect(tester.getRect(find.byType(ChessBoard)), rect);
      expect(celebrations(), hasLength(1));
      await controller.saveCompletion();
      await tester.pumpAndSettle();
      expect(celebrations(), hasLength(1));
      await tester.tap(find.text('下一关'));
      await tester.pumpAndSettle();
      expect(find.byType(CelebrationBadge), findsNothing);
    },
  );

  testWidgets(
    'last daily puzzle celebrates only after the whole set is saved',
    (tester) async {
      final repository = PuzzleRepository(prefs: prefs, catalog: catalog());
      addTearDown(repository.dispose);
      final date = DateTime(2026, 9, 28);
      final day = PuzzleRepository.dailyKey(date);
      final ids = await repository.daily(date);
      for (final id in ids.take(9)) {
        await repository.record(id, correct: true, day: day);
      }
      await open(
        tester,
        PuzzleSolveScreen(
          repository: repository,
          ids: ids,
          initialIndex: 9,
          day: day,
          analytics: analytics,
        ),
      );
      expect(find.byType(CelebrationBadge), findsNothing);
      await move(tester, 'e2e4');
      expect(find.byType(CelebrationBadge), findsNothing);
      await move(tester, 'g1f3');
      expect(repository.completed(day), hasLength(10));
      expect(find.text('每日练习完成！'), findsOneWidget);
      expect(celebrations(), hasLength(1));
      expect(celebrations().single['params']['source'], 'daily');
    },
  );

  testWidgets(
    'graduation celebrates tutorial completion even after resignation',
    (tester) async {
      final catalog = tutorialCatalog;
      await prefs.setInt(
        TutorialController.progressKey,
        catalog.levels.length - 1,
      );
      final controller = TutorialController(
        catalog: catalog,
        prefs: prefs,
        engine: FakeEngine(),
        analytics: analytics,
      )..start(catalog.levels.length - 1);
      addTearDown(controller.dispose);
      await open(
        tester,
        TutorialPlayScreen(controller: controller, analytics: analytics),
      );
      await move(tester, 'e2e4');
      await controller.resign();
      await tester.pumpAndSettle();
      expect(find.text('教程毕业！'), findsOneWidget);
      expect(celebrations(), hasLength(1));
      expect(celebrations().single['params']['result'], 'completed');
    },
  );

  testWidgets(
    'daily introductory puzzle sounds and celebrates on success only',
    (tester) async {
      await open(
        tester,
        TutorialDailyScreen(prefs: prefs, analytics: analytics),
        loadAssets: true,
      );
      expect(find.byType(CelebrationBadge), findsNothing);
      final board = tester.widget<ChessBoard>(find.byType(ChessBoard)).board;
      await move(
        tester,
        board.pieceAt(chess.parseSquare('d1')) != null ? 'd1d8' : 'g6g7',
      );
      expect(find.text('入门练习完成！'), findsOneWidget);
      expect(sounds.length, soundPulses[ChessSound.correct]!.length);
      expect(celebrations(), hasLength(1));
      expect(celebrations().single['params']['source'], 'daily_intro');
      await tester.tap(find.text('再练一次'));
      await tester.pumpAndSettle();
      expect(find.byType(CelebrationBadge), findsNothing);
    },
  );

  testWidgets('badge supports reduced motion and narrow double-size text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: CelebrationBadge(title: '每日练习完成！'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final animation = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(animation.duration, Duration.zero);
    expect(animation.tween.begin, 1);
    expect(tester.takeException(), isNull);
  });
}
