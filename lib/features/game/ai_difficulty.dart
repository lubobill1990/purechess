import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart';

class AiGameConfig {
  AiGameConfig({this.humanColor = Color.white, this.difficulty = 1}) {
    RangeError.checkValueInInterval(difficulty, 1, 10, 'difficulty');
  }

  final Color humanColor;
  final int difficulty;
}

int nextDifficulty(int playedLevel, {required bool? won}) {
  RangeError.checkValueInInterval(playedLevel, 1, 10, 'playedLevel');
  return (playedLevel + (won == null ? 0 : (won ? 1 : -1))).clamp(1, 10);
}

class AiDifficulty {
  AiDifficulty(this.prefs);

  static const preferenceKey = 'chess.ai.recommendedLevel';
  final SharedPreferences? prefs;

  int get recommended {
    try {
      final level = prefs?.getInt(preferenceKey) ?? 1;
      return RangeError.checkValueInInterval(level, 1, 10, 'recommended');
    } catch (error, stack) {
      reportHandledError('game_preferences', error, stack);
      return 1;
    }
  }

  Future<void> recordResult(int level, {required bool? won}) async {
    final next = nextDifficulty(level, won: won);
    if (await prefs?.setInt(preferenceKey, next) != true) {
      throw StateError('Could not save recommended difficulty');
    }
  }
}
