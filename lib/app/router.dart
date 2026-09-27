import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/game/game_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/records_screen.dart';
import '../features/puzzle/puzzle_screen.dart';
import '../features/settings/settings.dart';
import 'telemetry/analytics.dart';

class AppRouter {
  static const home = '/';
  static const game = '/game';
  static const records = '/records';
  static const settings = '/settings';
  static const puzzles = '/puzzles';

  static Map<String, WidgetBuilder> routes({
    required SharedPreferences prefs,
    required Analytics analytics,
  }) => {
    home: (_) => const HomeScreen(),
    game: (_) => GameScreen(analytics: analytics),
    records: (_) => const RecordsScreen(),
    puzzles: (_) => PuzzleScreen(prefs: prefs, analytics: analytics),
    settings: (_) => SettingsScreen(prefs: prefs, analytics: analytics),
  };
}
