import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart';
import '../../core/pgn.dart';
import 'ai_difficulty.dart';
import 'game_session.dart';

class SavedGame {
  SavedGame({required this.session, this.config});

  final GameSession session;
  final AiGameConfig? config;

  String encode() => jsonEncode({
    'version': 1,
    'mode': config == null ? 'local' : 'ai',
    'pgn': Pgn.generate(session.snapshot()),
    'startedAt': session.startedAt.toUtc().toIso8601String(),
    'hintsUsed': session.hintsUsed,
    'drawOffer': session.drawOffer?.name,
    'config': config == null
        ? null
        : {'color': config!.humanColor.name, 'difficulty': config!.difficulty},
  });

  static SavedGame decode(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['version'] is! int ||
        !['ai', 'local'].contains(data['mode']) ||
        data['pgn'] is! String ||
        data['startedAt'] is! String ||
        data['hintsUsed'] is! int ||
        (data['hintsUsed'] as int) < 0 ||
        ![null, 'white', 'black'].contains(data['drawOffer'])) {
      throw const FormatException('Invalid saved game');
    }
    AiGameConfig? config;
    final settings = data['config'];
    if (data['mode'] == 'ai') {
      if (settings is! Map<String, dynamic> ||
          !['white', 'black'].contains(settings['color']) ||
          settings['difficulty'] is! int ||
          data['drawOffer'] != null) {
        throw const FormatException('Invalid saved AI configuration');
      }
      config = AiGameConfig(
        humanColor: Color.values.byName(settings['color'] as String),
        difficulty: settings['difficulty'] as int,
      );
    } else if (settings != null || data['hintsUsed'] != 0) {
      throw const FormatException('Invalid saved local configuration');
    }
    return SavedGame(
      config: config,
      session: GameSession.restore(
        pgn: data['pgn'] as String,
        startedAt: DateTime.parse(data['startedAt'] as String),
        hintsUsed: data['hintsUsed'] as int,
        drawOffer: data['drawOffer'] == null
            ? null
            : Color.values.byName(data['drawOffer'] as String),
      ),
    );
  }
}

/// A single slot, with ordered writes so a delayed save cannot undo a clear.
class GameStore extends ChangeNotifier {
  GameStore(this.prefs) {
    try {
      final value = prefs.getString(preferenceKey);
      if (value != null) {
        SavedGame.decode(value);
        _saved = value;
      }
    } catch (error, stack) {
      reportHandledError('game_restore', error, stack);
      unawaited(clear());
    }
  }

  static const preferenceKey = 'game.unfinished';
  final SharedPreferences prefs;
  String? _saved;
  Future<void> _pending = Future.value();
  bool _disposed = false;

  bool get canResume => _saved != null;
  SavedGame? restore() => _saved == null ? null : SavedGame.decode(_saved!);

  Future<void> save(GameSession session, {AiGameConfig? config}) {
    if (session.finished) return clear();
    try {
      return _write(SavedGame(session: session, config: config).encode());
    } catch (error, stack) {
      reportHandledError('game_autosave', error, stack);
      return Future.value();
    }
  }

  Future<void> clear() => _write(null);

  Future<void> _write(String? value) {
    _saved = value;
    return _pending = _pending.then((_) async {
      try {
        final ok = value == null
            ? await prefs.remove(preferenceKey)
            : await prefs.setString(preferenceKey, value);
        if (!ok) throw StateError('Could not persist unfinished game');
      } catch (error, stack) {
        reportHandledError('game_autosave', error, stack);
      }
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the screen's autosave lifetime, including pending draw/hint metadata.
class GamePersistence with WidgetsBindingObserver {
  GamePersistence({required this.store, required this.session, this.config}) {
    WidgetsBinding.instance.addObserver(this);
    save();
  }

  final GameStore? store;
  final GameSession Function() session;
  final AiGameConfig? config;
  bool _closed = false;

  void save() {
    if (!_closed) unawaited(store?.save(session(), config: config));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      save();
    }
  }

  Future<void> close({bool abandon = false}) async {
    if (_closed) return;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (abandon) {
      await store?.clear();
    } else {
      await store?.save(session(), config: config);
    }
  }
}
