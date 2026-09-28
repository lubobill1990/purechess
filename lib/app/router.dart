import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/achievements/achievements_screen.dart';
import '../features/game/game_screen.dart';
import '../features/game/ai_difficulty.dart';
import '../features/game/ai_game_screen.dart';
import '../features/game/game_persistence.dart';
import '../features/game/new_game_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/classic_library_screen.dart';
import '../features/library/records_screen.dart';
import '../features/puzzle/puzzle_screen.dart';
import '../features/settings/settings.dart';
import '../features/tutorial/tutorial_screen.dart';
import 'telemetry/analytics.dart';
import 'notifications.dart';

class AppRouter {
  static const home = '/';
  static const game = '/game';
  static const newGame = '/game/new';
  static const records = '/records';
  static const settings = '/settings';
  static const puzzles = '/puzzles';
  static const tutorial = '/tutorial';
  static const dailyPuzzle = tutorialDailyRoute;
  static const daily = '/puzzles/daily';
  static const library = '/library';
  static const reading = '/library/reading';
  static const achievements = '/achievements';

  static Map<String, WidgetBuilder> routes({
    required SharedPreferences prefs,
    required Analytics analytics,
    DailyReminderService? reminders,
    WidgetBuilder? dailyBuilder,
    int? recommendedDifficulty,
    bool canResumeGame = false,
    GameStore? gameStore,
  }) => {
    achievements: (_) => AchievementsScreen(prefs: prefs),
    home: (_) => gameStore == null
        ? HomeScreen(
            prefs: prefs,
            recommendedDifficulty: recommendedDifficulty,
            canResumeGame: canResumeGame,
          )
        : ListenableBuilder(
            listenable: gameStore,
            builder: (_, _) => HomeScreen(
              prefs: prefs,
              recommendedDifficulty: recommendedDifficulty,
              canResumeGame: gameStore.canResume,
            ),
          ),
    game: (_) =>
        GameScreen(analytics: analytics, prefs: prefs, gameStore: gameStore),
    newGame: (context) {
      final arguments = ModalRoute.of(context)?.settings.arguments;
      final saved = arguments is Map && arguments['resume'] == true
          ? gameStore?.restore()
          : null;
      if (saved != null) {
        final config = saved.config;
        return config == null
            ? GameScreen(
                session: saved.session,
                prefs: prefs,
                analytics: analytics,
                gameStore: gameStore,
                resumed: true,
              )
            : AiGameScreen(
                config: config,
                session: saved.session,
                rating: AiDifficulty(prefs),
                analytics: analytics,
                gameStore: gameStore,
                resumed: true,
              );
      }
      return NewGameScreen(
        prefs: prefs,
        analytics: analytics,
        gameStore: gameStore,
      );
    },
    records: (_) => const RecordsScreen(),
    puzzles: (_) => PuzzleScreen(prefs: prefs, analytics: analytics),
    settings: (_) => SettingsScreen(
      prefs: prefs,
      analytics: analytics,
      reminders: reminders,
    ),
    tutorial: (_) => TutorialScreen(prefs: prefs, analytics: analytics),
    dailyPuzzle: (_) => TutorialDailyScreen(analytics: analytics, prefs: prefs),
    library: (_) => ClassicLibraryScreen(prefs: prefs),
    reading: (_) => ClassicLibraryScreen(prefs: prefs, resume: true),
    // Home's daily entry keeps its own path; both it and [dailyPuzzle]
    // resolve to the daily tactics screen.
    daily:
        dailyBuilder ??
        (_) => TutorialDailyScreen(analytics: analytics, prefs: prefs),
  };
}
