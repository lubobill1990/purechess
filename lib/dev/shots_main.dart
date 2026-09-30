import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_theme.dart';
import '../core/move.dart' as chess;
import '../features/game/ai_difficulty.dart';
import '../features/game/ai_game_screen.dart';
import '../features/game/game_screen.dart';
import '../features/game/game_session.dart';

/// Design-review entrypoint (never shipped): renders one play scene chosen
/// via --dart-define=SCENE so simulator-level screenshots show the real app.
const _scene = String.fromEnvironment('SCENE', defaultValue: 'human_portrait');

GameSession _midgame() => GameSession()
  ..play(chess.Move.fromUci('e2e4'))
  ..play(chess.Move.fromUci('e7e5'))
  ..play(chess.Move.fromUci('g1f3'))
  ..play(chess.Move.fromUci('b8c6'))
  ..play(chess.Move.fromUci('f1c4'))
  ..play(chess.Move.fromUci('g8f6'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
    _scene.endsWith('landscape')
        ? [DeviceOrientation.landscapeLeft]
        : [DeviceOrientation.portraitUp],
  );
  final prefs = await SharedPreferences.getInstance();
  final home = _scene.startsWith('ai')
      ? AiGameScreen(
          config: AiGameConfig(difficulty: 3),
          rating: AiDifficulty(prefs),
          session: _midgame(),
        )
      : GameScreen(prefs: prefs, session: _midgame());
  runApp(
    MaterialApp(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: home,
    ),
  );
}
