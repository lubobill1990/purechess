import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/game/game_screen.dart';
import '../features/game/new_game_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/feature_pending_screen.dart';
import '../features/library/classic_library_screen.dart';
import '../features/library/records_screen.dart';
import '../features/puzzle/puzzle_screen.dart';
import '../features/settings/settings.dart';
import '../features/tutorial/tutorial_screen.dart';
import 'telemetry/analytics.dart';

class AppRouter {
  static const home = '/';
  static const game = '/game';
  static const newGame = '/game/new';
  static const records = '/records';
  static const settings = '/settings';
  static const puzzles = '/puzzles';
  static const tutorial = '/tutorial';
  static const dailyPuzzle = tutorialDailyRoute;
  static const tutorial = '/tutorial';
  static const daily = '/puzzles/daily';
  static const newGame = '/game/new';
  static const library = '/library';
  static const reading = '/library/reading';

  static Map<String, WidgetBuilder> routes({
    required SharedPreferences prefs,
    required Analytics analytics,
    WidgetBuilder? tutorialBuilder,
    WidgetBuilder? dailyBuilder,
    WidgetBuilder? aiGameBuilder,
    int? recommendedDifficulty,
    bool canResumeGame = false,
  }) => {
    home: (_) => HomeScreen(
      prefs: prefs,
      recommendedDifficulty: recommendedDifficulty,
      canResumeGame: canResumeGame,
    ),
    game: (_) => GameScreen(analytics: analytics),
    newGame: (_) => NewGameScreen(prefs: prefs, analytics: analytics),
    records: (_) => const RecordsScreen(),
    puzzles: (_) => PuzzleScreen(prefs: prefs, analytics: analytics),
    settings: (_) => SettingsScreen(prefs: prefs, analytics: analytics),
    tutorial: (_) => TutorialScreen(prefs: prefs, analytics: analytics),
    dailyPuzzle: (_) => TutorialDailyScreen(analytics: analytics),
    library: (_) => ClassicLibraryScreen(prefs: prefs),
    reading: (_) => ClassicLibraryScreen(prefs: prefs, resume: true),
    tutorial:
        tutorialBuilder ??
        (_) => const FeaturePendingScreen(
          title: '互动教程',
          message: '教程正在准备中。学习记录会保留，你也可以先到名局库看看。',
        ),
    daily:
        dailyBuilder ??
        (_) => const FeaturePendingScreen(
          title: '每日战术题',
          message: '每日题正在准备中。现在可以先读一盘名局。',
        ),
    newGame:
        aiGameBuilder ??
        (_) => const FeaturePendingScreen(
          title: 'AI 对弈',
          message: 'AI 对弈正在准备中。可返回首页，选择双人对弈。',
        ),
  };
}
