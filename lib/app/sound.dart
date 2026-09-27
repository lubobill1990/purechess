import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/board.dart';
import 'telemetry/app_logger.dart';

/// Material's automatic tap clicks bypass the sound preference on Android.
/// Keep controls quiet; only accepted chess/learning events produce audio.
ThemeData quietControlsTheme(ThemeData theme) {
  ButtonStyle quiet(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(enableFeedback: false);
  return theme.copyWith(
    textButtonTheme: TextButtonThemeData(
      style: quiet(theme.textButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: quiet(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: quiet(theme.outlinedButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: quiet(theme.elevatedButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: quiet(theme.iconButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: quiet(theme.segmentedButtonTheme.style),
    ),
    listTileTheme: theme.listTileTheme.copyWith(enableFeedback: false),
  );
}

enum ChessSound {
  move,
  capture,
  check,
  checkmate,
  victory,
  correct,
  incorrect,
  end,
}

/// Relative pulse times: use click only (alert is unsupported on some phones).
const soundPulses = <ChessSound, List<int>>{
  ChessSound.move: [0],
  ChessSound.capture: [0, 90],
  ChessSound.check: [0, 220],
  ChessSound.checkmate: [0, 90, 180, 400],
  ChessSound.victory: [0, 130, 260, 520],
  ChessSound.correct: [0, 100, 200],
  ChessSound.incorrect: [0, 350],
  ChessSound.end: [0, 250, 500],
};

class SoundService with WidgetsBindingObserver {
  SoundService({this.prefs}) {
    WidgetsBinding.instance.addObserver(this);
    _instances.add(this);
  }

  static const enabledKey = 'soundEnabled';
  static final _instances = <SoundService>{};
  final SharedPreferences? prefs;
  final List<Timer> _timers = [];
  int _generation = 0;
  bool _disposed = false;
  bool _failed = false;

  bool get _active {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  Future<void> play(
    List<ChessSound> sounds, {
    required bool Function() isCurrent,
  }) async {
    stop();
    final generation = _generation;
    try {
      final preferences = prefs ?? await SharedPreferences.getInstance();
      bool allowed() =>
          !_disposed &&
          !_failed &&
          generation == _generation &&
          _active &&
          isCurrent() &&
          (preferences.getBool(enabledKey) ?? true);
      if (!allowed()) return;
      var offset = 0;
      for (final sound in sounds) {
        for (final pulse in soundPulses[sound]!) {
          if (!allowed()) return;
          final delay = offset + pulse;
          if (delay == 0) {
            await _click(allowed);
          } else {
            _timers.add(
              Timer(Duration(milliseconds: delay), () {
                unawaited(_click(allowed));
              }),
            );
          }
        }
        offset += soundPulses[sound]!.last + 180;
      }
    } on Exception catch (error) {
      _failed = true;
      logW('sound', 'Sound settings unavailable: $error');
    }
  }

  Future<void> _click(bool Function() allowed) async {
    if (!allowed()) {
      stop();
      return;
    }
    try {
      await SystemSound.play(SystemSoundType.click);
    } on PlatformException catch (error) {
      _failed = true;
      stop();
      logW('sound', 'System sound unavailable: $error');
    } on MissingPluginException catch (error) {
      _failed = true;
      stop();
      logW('sound', 'System sound unsupported: $error');
    }
  }

  void stop() {
    _generation++;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  static void stopAll() {
    for (final service in _instances) {
      service.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  void dispose() {
    _disposed = true;
    stop();
    _instances.remove(this);
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// Reconstruct forward plies when an immediate AI reply shares the same frame.
/// A matching prefix excludes resets, undo, loading positions and navigation.
List<ChessSound> soundsForBoards(Board before, Board after) {
  if (after.plyCount <= before.plyCount) return const [];
  final cursor = after.copy();
  final sounds = <ChessSound>[];
  while (cursor.plyCount > before.plyCount) {
    final next = cursor.copy();
    cursor.undo();
    sounds.add(
      next.status == GameStatus.checkmate
          ? ChessSound.checkmate
          : next.inCheck
          ? ChessSound.check
          : _pieceCount(next) < _pieceCount(cursor)
          ? ChessSound.capture
          : ChessSound.move,
    );
  }
  if (cursor.toFen() != before.toFen()) return const [];
  return sounds.reversed.toList();
}

int _pieceCount(Board board) {
  var count = 0;
  for (var rank = 0; rank < 8; rank++) {
    for (var file = 0; file < 8; file++) {
      if (board.pieceAt(rank * 16 + file) != null) count++;
    }
  }
  return count;
}
