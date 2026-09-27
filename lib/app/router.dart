import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/game/game_screen.dart';
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

  static Map<String, WidgetBuilder> routes({
    required SharedPreferences prefs,
    required Analytics analytics,
    DailyReminderService? reminders,
    WidgetBuilder? dailyBuilder,
    int? recommendedDifficulty,
    bool canResumeGame = false,
  }) => {
    home: (_) => HomeScreen(
      prefs: prefs,
      recommendedDifficulty: recommendedDifficulty,
      canResumeGame: canResumeGame,
    ),
    game: (_) => GameScreen(analytics: analytics, prefs: prefs),
    newGame: (_) => NewGameScreen(prefs: prefs, analytics: analytics),
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
