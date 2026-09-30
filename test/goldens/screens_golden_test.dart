@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/app_theme.dart';
import 'package:purechess/app/play_feedback.dart';
import 'package:purechess/app/notifications.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/features/achievements/achievements.dart';
import 'package:purechess/features/achievements/achievements_screen.dart';
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/ai_game_screen.dart';
import 'package:purechess/features/game/game_screen.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:purechess/features/game/new_game_screen.dart';
import 'package:purechess/features/game/review_screen.dart';
import 'package:purechess/features/home/home_screen.dart';
import 'package:purechess/features/library/classic_library.dart';
import 'package:purechess/features/library/classic_library_screen.dart';
import 'package:purechess/features/library/classic_reader_screen.dart';
import 'package:purechess/features/puzzle/puzzle_catalog.dart';
import 'package:purechess/features/puzzle/puzzle_repository.dart';
import 'package:purechess/features/puzzle/puzzle_screen.dart';
import 'package:purechess/features/settings/settings.dart';
import 'package:purechess/features/settings/backup.dart';
import 'package:purechess/features/settings/privacy.dart';
import 'package:purechess/features/tutorial/tutorial_engine.dart';
import 'package:purechess/features/tutorial/tutorial_level.dart';
import 'package:purechess/features/tutorial/tutorial_screen.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/game/fake_game_engine.dart';
import '../support/memory_records_repository.dart';
import '../support/fake_reminder_backend.dart';

const _surface = Size(1024, 1366);
const _captureKey = ValueKey('golden-screen');
final _now = DateTime(2026, 9, 28, 12);
const _initialFen =
    'r1bq1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 4 6';
const _midgameFen =
    'r1bq1rk1/ppp2pp1/2np1n1p/2b1p1B1/2B1P3/2NP1N2/PPP2PPP/R2Q1RK1 w - - 0 7';
const _puzzleId = '0030b';
const _puzzleFen = '6k1/5ppp/5n2/pp6/4b1rP/5N1Q/Pq2r1P1/3R2RK w - - 5 33';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PuzzleCatalog puzzles;
  late TutorialCatalog tutorials;
  late List<ClassicGame> classics;

  setUpAll(() async {
    if (!Platform.isWindows) {
      throw StateError(
        'These baselines require Windows. Use --exclude-tags golden on '
        'other platforms; do not overwrite Windows baselines there.',
      );
    }
    // Test-only font aliases keep Windows baselines reproducible.
    final chineseBytes = File(r'test\goldens\fonts\NotoSansSC.ttf')
        .readAsBytes()
        .then(ByteData.sublistView);
    final chinese = FontLoader('NotoSansSC')..addFont(chineseBytes);
    final songti = FontLoader('Songti SC')..addFont(chineseBytes);
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    final windows = Platform.environment['WINDIR']!;
    Future<ByteData> windowsFont(String name) =>
        File('$windows\\Fonts\\$name').readAsBytes().then(ByteData.sublistView);
    final ui = FontLoader('Segoe UI')..addFont(chineseBytes);
    final display = FontLoader('Georgia')
      ..addFont(windowsFont('georgia.ttf'))
      ..addFont(windowsFont('georgiab.ttf'));
    final coordinates = FontLoader('monospace')
      ..addFont(windowsFont('consola.ttf'));
    await Future.wait([
      chinese.load(),
      songti.load(),
      icons.load(),
      ui.load(),
      display.load(),
      coordinates.load(),
    ]);
    puzzles = await PuzzleCatalog.load();
    tutorials = await TutorialCatalog.load();
    classics = await ClassicLibrary.load();
    for (final side in ['w', 'b']) {
      for (final piece in ['K', 'Q', 'R', 'B', 'N', 'P']) {
        final loader = SvgAssetLoader('assets/pieces/$side$piece.svg');
        await svg.cache.putIfAbsent(
          loader.cacheKey(null),
          () => loader.loadBytes(null),
        );
      }
    }
  });

  for (final dark in [false, true]) {
    final themeName = dark ? 'dark' : 'light';
    for (final captureScene in [
      'home_learning',
      'home_graduated',
      'home_resume',
      'achievements',
      'new_game',
      'game_ai',
      'game_human',
      'game_ai_finished',
      'game_human_finished',
      'puzzle',
      'tutorial',
      'settings',
      'library',
      'reader',
      'puzzle_catalog',
      'puzzle_hint',
      'tutorial_play',
      'backup',
      'privacy',
      'celebration',
      'reminder_time',
      'board_selected',
      'board_check',
      'home_mobile',
      'settings_mobile',
      'review',
      'game_ai_phone',
      'game_human_phone',
      'puzzle_phone',
      'tutorial_play_phone',
      'review_phone',
      'reader_phone',
      'game_ai_landscape',
      'game_human_landscape',
      'puzzle_landscape',
      'tutorial_play_landscape',
      'review_landscape',
      'reader_landscape',
      'board_aim',
    ]) {
      testWidgets('$captureScene $themeName', (tester) async {
        final scene = captureScene.replaceFirst(
          RegExp(r'_(phone|landscape)$'),
          '',
        );
        final surface =
            captureScene.endsWith('_mobile') || captureScene.endsWith('_phone')
            ? const Size(390, 844)
            : captureScene.endsWith('_landscape')
            ? const Size(844, 390)
            : _surface;
        tester.view.physicalSize = surface;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'tutorial_progress': scene == 'home_graduated'
              ? '{"completed":19,"total":19}'
              : 4,
          'daily_20260928': '{"completed":2,"total":10}',
          AiDifficulty.preferenceKey: 3,
          Analytics.privacyAcceptedKey: true,
          Analytics.enabledKey: false,
          if (scene == 'achievements')
            AchievementData.preferenceKey: AchievementData(
              lastActiveDay: '20260928',
              streak: 7,
              bestStreak: 7,
              counters: {'gamesFinished': 12, 'winsVsAi': 3},
              earned: {
                'first_day': '20260922',
                'streak_7': '20260928',
                'first_win': '20260924',
                'games_10': '20260927',
              },
            ).encode(),
        });
        final prefs = await SharedPreferences.getInstance();
        final telemetry = Directory.systemTemp.createTempSync('chess-golden-');
        final analytics = Analytics.testing(directory: telemetry);
        addTearDown(() {
          analytics.dispose();
          telemetry.deleteSync(recursive: true);
        });
        await tester.runAsync(() => analytics.init(prefs));
        final records = MemoryRecordsRepository();
        FakeGameEngine? engine;
        late Widget screen;
        switch (scene) {
          case 'board_selected':
          case 'board_check':
          case 'board_aim':
            screen = Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 560,
                  child: ChessBoard(
                    board: scene == 'board_aim'
                        ? Board()
                        : Board.fromFen(
                            scene == 'board_selected'
                                ? _midgameFen
                                : '4r2k/8/8/8/8/8/8/4K3 w - - 0 1',
                          ),
                    onMove: (_) {},
                  ),
                ),
              ),
            );
          case 'review':
            final reviewEngine = FakeGameEngine();
            addTearDown(reviewEngine.dispose);
            screen = ReviewScreen(
              record: Pgn.parse('1. e4 e5 2. Nf3 Nc6 *'),
              engine: reviewEngine,
            );
          case 'library':
            screen = ClassicLibraryScreen(
              prefs: prefs,
              load: () async => classics,
            );
          case 'reader':
            screen = ClassicReaderScreen(
              prefs: prefs,
              game: classics.first,
              initialPly: 8,
            );
          case 'puzzle_catalog':
            screen = PuzzleScreen(
              prefs: prefs,
              analytics: analytics,
              now: () => _now,
              loadCatalog: () async => puzzles,
            );
          case 'backup':
            screen = BackupScreen(prefs: prefs, analytics: analytics);
          case 'privacy':
            screen = const PrivacyPolicyScreen();
          case 'celebration':
            screen = const Scaffold(
              body: Center(child: CelebrationBadge(title: '解题成功！')),
            );
          case 'reminder_time':
            final reminders = DailyReminderService(
              prefs,
              analytics: analytics,
              backend: FakeReminderBackend(),
            );
            addTearDown(reminders.dispose);
            await reminders.refresh();
            screen = SettingsScreen(
              prefs: prefs,
              analytics: analytics,
              reminders: reminders,
            );
          case 'achievements':
            screen = AchievementsScreen(prefs: prefs, now: () => _now);
          case 'home_learning':
          case 'home_mobile':
          case 'home_graduated':
          case 'home_resume':
            screen = HomeScreen(
              prefs: prefs,
              now: () => _now,
              canResumeGame: scene == 'home_resume',
            );
          case 'new_game':
            screen = NewGameScreen(prefs: prefs, analytics: analytics);
          case 'game_ai':
          case 'game_human':
          case 'game_ai_finished':
          case 'game_human_finished':
            final ai = scene.startsWith('game_ai');
            final session =
                GameSession(
                    initialFen: _initialFen,
                    startedAt: _now,
                    humanColor: ai ? chess.Color.white : null,
                  )
                  ..play(chess.Move.fromUci('c1g5'))
                  ..play(chess.Move.fromUci('h7h6'));
            expect(session.board.toFen(), _midgameFen);
            if (scene.endsWith('_finished')) session.resign(chess.Color.white);
            if (ai) {
              engine = FakeGameEngine();
              screen = AiGameScreen(
                config: AiGameConfig(difficulty: 3),
                rating: AiDifficulty(prefs),
                engine: engine,
                session: session,
                analytics: analytics,
                openRepository: () async => records,
              );
            } else {
              screen = GameScreen(
                session: session,
                analytics: analytics,
                openRepository: () async => records,
              );
            }
          case 'puzzle':
          case 'puzzle_hint':
            final repository = PuzzleRepository(prefs: prefs, catalog: puzzles);
            addTearDown(repository.dispose);
            screen = PuzzleSolveScreen(
              repository: repository,
              ids: const [_puzzleId],
              analytics: analytics,
            );
          case 'tutorial':
          case 'tutorial_play':
            screen = TutorialScreen(
              prefs: prefs,
              analytics: analytics,
              loadCatalog: () async => tutorials,
              createEngine: FakeEngine.new,
            );
          case 'settings':
          case 'settings_mobile':
            screen = SettingsScreen(prefs: prefs, analytics: analytics);
          default:
            throw StateError('Unknown golden scene: $scene');
        }
        final brightness = dark ? Brightness.dark : Brightness.light;
        final base = dark ? buildDarkTheme() : buildLightTheme();
        const fallback = ['NotoSansSC'];
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: base.copyWith(
              textTheme: base.textTheme.apply(fontFamilyFallback: fallback),
              primaryTextTheme: base.primaryTextTheme.apply(
                fontFamilyFallback: fallback,
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                platformBrightness: brightness,
                textScaler: TextScaler.noScaling,
                disableAnimations: true,
              ),
              child: RepaintBoundary(key: _captureKey, child: child!),
            ),
            home: screen,
          ),
        );
        if (scene.startsWith('home_')) {
          await tester.runAsync(
            () => precacheImage(
              const AssetImage('assets/icon/icon.png'),
              tester.element(find.byType(MaterialApp)),
            ),
          );
        }
        await tester.pumpAndSettle();
        if (scene == 'reminder_time') {
          await tester.tap(find.text('提醒时间'));
          await tester.pumpAndSettle();
          expect(find.text('选择提醒时间'), findsOneWidget);
        }
        if (scene == 'board_selected') {
          await tester.tap(
            find.byKey(const ValueKey('square-g5')),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
        }
        TestGesture? aim;
        if (scene == 'board_aim') {
          aim = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey('square-e2'))),
          );
          await aim.moveTo(
            tester.getCenter(find.byKey(const ValueKey('square-e4'))) +
                const Offset(0, 105),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('board-aim-ghost')), findsOneWidget);
        }
        if (scene == 'puzzle_hint') {
          await tester.tap(find.text('提示思路'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('亮起点格'));
          await tester.pumpAndSettle();
        }
        if (scene == 'tutorial_play') {
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('tutorial-level-4')),
            120,
          );
          await tester.tap(find.byKey(const ValueKey('tutorial-level-4')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('提示'));
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        for (final progress in tester.widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )) {
          expect(progress.value, isNotNull);
        }
        expect(tester.getSize(find.byKey(_captureKey)), surface);
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          brightness,
        );
        switch (scene) {
          case 'home_learning':
            expect(find.text('继续教程第 5 关'), findsOneWidget);
            expect(find.text('已完成 4 / 18 关'), findsOneWidget);
          case 'home_graduated':
            expect(find.text('今日 2 / 10 题'), findsOneWidget);
            expect(find.text('新对局'), findsOneWidget);
            expect(find.text('读一盘名局'), findsOneWidget);
          case 'home_resume':
            expect(find.text('继续对局'), findsOneWidget);
            expect(find.text('继续教程第 5 关'), findsOneWidget);
          case 'new_game':
            expect(find.text('难度 · 3 / 10'), findsOneWidget);
            expect(find.text('白棋 · 先走'), findsOneWidget);
            final start = find.byKey(const ValueKey('start-ai-game'));
            expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
            expect(
              tester.getRect(start).bottom,
              lessThanOrEqualTo(_surface.height),
            );
          case 'game_ai':
          case 'game_human':
          case 'game_ai_finished':
          case 'game_human_finished':
            final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
            expect(board.board.toFen(), _midgameFen);
            expect(board.enabled, !scene.endsWith('_finished'));
            expect(board.board.lastMove, chess.Move.fromUci('h7h6'));
            expect(find.text('保存棋谱'), findsOneWidget);
            if (scene.endsWith('_finished')) {
              expect(find.text('再来一局'), findsOneWidget);
              expect(find.text('黑方胜 · 对方认输'), findsOneWidget);
            }
            if (engine != null) {
              expect(engine.starts, 0);
              expect(engine.requests, isEmpty);
              if (!scene.endsWith('_finished')) {
                expect(find.text('轮到你走棋'), findsOneWidget);
              }
            }
          case 'puzzle':
            final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
            expect(board.board.toFen(), _puzzleFen);
            expect(board.enabled, isTrue);
            expect(find.text('第 1 / 1 题 · 538'), findsOneWidget);
            expect(find.text('提示思路'), findsOneWidget);
          case 'tutorial':
            expect(find.text('新手互动教程'), findsOneWidget);
            expect(find.text('每关只学一件事 · 已完成 4 / 19'), findsOneWidget);
            final unlocked = find.byKey(const ValueKey('tutorial-level-4'));
            final locked = find.byKey(const ValueKey('tutorial-level-5'));
            expect(tester.widget<ListTile>(unlocked).enabled, isTrue);
            expect(tester.widget<ListTile>(locked).onTap, isNull);
          case 'settings':
            expect(find.text('AI 尚未启动'), findsOneWidget);
            expect(find.text('隐私政策'), findsOneWidget);
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.byKey(const ValueKey('analytics-toggle')),
                  )
                  .value,
              isFalse,
            );
        }
        await expectLater(
          find.byKey(_captureKey),
          matchesGoldenFile('windows/${captureScene}_$themeName.png'),
        );
        await aim?.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        if (engine != null) expect(engine.disposals, 1);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }
  }
}
