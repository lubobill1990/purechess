import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/game_persistence.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';

class DelayedStore extends InMemorySharedPreferencesStore {
  DelayedStore() : super.empty();

  final gate = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await gate.future;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late GameStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = GameStore(prefs);
  });

  tearDown(() => store.dispose());

  test(
    'AI PGN/config/metadata round trip preserves undo and repetition',
    () async {
      final session = GameSession(
        startedAt: DateTime.utc(2026, 9, 28, 1, 2, 3),
        humanColor: Color.black,
      );
      for (final san in ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3']) {
        session.play(session.board.parseSan(san));
      }
      session.hintsUsed = 3;
      await store.save(
        session,
        config: AiGameConfig(humanColor: Color.black, difficulty: 8),
      );
      final reopened = GameStore(prefs);
      addTearDown(reopened.dispose);
      final saved = reopened.restore()!;
      expect(saved.config!.humanColor, Color.black);
      expect(saved.config!.difficulty, 8);
      expect(saved.session.startedAt, session.startedAt);
      expect(saved.session.hintsUsed, 3);
      expect(saved.session.board.toFen(), session.board.toFen());
      expect(
        Pgn.generate(saved.session.snapshot()),
        Pgn.generate(session.snapshot()),
      );
      saved.session.undo();
      for (final san in ['Nf3', 'Nf6', 'Ng1', 'Ng8']) {
        saved.session.play(saved.session.board.parseSan(san));
      }
      expect(saved.session.outcome!.reason, GameEndReason.threefoldRepetition);
    },
  );

  test(
    'local resume retains a pending draw offer and can decline it',
    () async {
      final session = GameSession()..offerDraw(Color.white);
      await store.save(session);
      final saved = store.restore()!;
      expect(saved.config, isNull);
      expect(saved.session.drawOffer, Color.white);
      expect(saved.session.canPlay, isFalse);
      saved.session.respondToDraw(Color.black, accept: false);
      saved.session.play(Move.fromUci('e2e4'));
      expect(saved.session.moveCount, 1);
    },
  );

  test('custom FEN and promotion survive PGN restoration', () async {
    final session = GameSession(initialFen: '7k/P7/8/8/8/8/8/7K w - - 0 1');
    session.play(Move.fromUci('a7a8q'));
    await store.save(session);
    final restored = store.restore()!.session;
    expect(restored.board.toFen(), session.board.toFen());
    restored.undo();
    expect(restored.board.toFen(), session.snapshot().initialFen);
  });

  for (final finish in ['mate', 'resign', 'agreement']) {
    test('$finish removes the unfinished slot', () async {
      final session = GameSession();
      await store.save(session);
      if (finish == 'resign') {
        session.resign(Color.white);
      } else if (finish == 'agreement') {
        session.offerDraw(Color.white);
        session.respondToDraw(Color.black, accept: true);
      } else {
        for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
          session.play(session.board.parseSan(san));
        }
      }
      await store.save(session);
      expect(store.canResume, isFalse);
      expect(prefs.containsKey(GameStore.preferenceKey), isFalse);
    });
  }

  final valid = jsonDecode(
    SavedGame(session: GameSession()).encode(),
  ) as Map<String, dynamic>;
  for (final entry in <String, Object>{
    'malformed JSON': '{',
    'wrong preference type': 42,
    'unknown version': jsonEncode({...valid, 'version': 2}),
    'noninteger version': jsonEncode({...valid, 'version': 1.0}),
    'invalid PGN': jsonEncode({...valid, 'pgn': '1. e5 *'}),
    'completed PGN': jsonEncode({...valid, 'pgn': '1. e4 1-0'}),
    'negative hints': jsonEncode({...valid, 'hintsUsed': -1}),
    'bad date': jsonEncode({...valid, 'startedAt': 'bad'}),
    'bad mode': jsonEncode({...valid, 'mode': 'unknown'}),
    'wrong draw offer': jsonEncode({...valid, 'drawOffer': 'black'}),
    'missing AI config': jsonEncode({...valid, 'mode': 'ai'}),
    'invalid AI level': jsonEncode({
      ...valid,
      'mode': 'ai',
      'config': {'color': 'white', 'difficulty': 11},
    }),
    'invalid AI color': jsonEncode({
      ...valid,
      'mode': 'ai',
      'config': {'color': 'red', 'difficulty': 2},
    }),
    'terminal board with unfinished result': jsonEncode({
      ...valid,
      'pgn': '1. f3 e5 2. g4 Qh4# *',
    }),
  }.entries) {
    test('discards ${entry.key}', () async {
      SharedPreferences.setMockInitialValues({
        GameStore.preferenceKey: entry.value,
      });
      final corruptedPrefs = await SharedPreferences.getInstance();
      final corrupted = GameStore(corruptedPrefs);
      addTearDown(corrupted.dispose);
      expect(corrupted.canResume, isFalse);
      expect(corrupted.restore(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(corruptedPrefs.containsKey(GameStore.preferenceKey), isFalse);
    });
  }

  test('clear is ordered after an in-flight write', () async {
    final platform = DelayedStore();
    SharedPreferencesStorePlatform.instance = platform;
    SharedPreferences.resetStatic();
    final delayedPrefs = await SharedPreferences.getInstance();
    final delayed = GameStore(delayedPrefs);
    addTearDown(delayed.dispose);
    final saving = delayed.save(GameSession());
    final clearing = delayed.clear();
    platform.gate.complete();
    await Future.wait([saving, clearing]);
    expect(await platform.getAll(), isEmpty);
    expect(delayed.canResume, isFalse);
  });

  test('write failure is handled and later saving still works', () async {
    final platform = FailingPreferencesStore()
      ..failKey = 'flutter.${GameStore.preferenceKey}';
    SharedPreferencesStorePlatform.instance = platform;
    SharedPreferences.resetStatic();
    final failing = GameStore(await SharedPreferences.getInstance());
    addTearDown(failing.dispose);
    await failing.save(GameSession());
    expect(await platform.getAll(), isEmpty);
    platform.failKey = null;
    await failing.save(GameSession()..play(Move.fromUci('e2e4')));
    expect(
      await platform.getAll(),
      contains('flutter.${GameStore.preferenceKey}'),
    );
  });

  for (final state in [
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.detached,
  ]) {
    testWidgets('$state saves current metadata via the lifecycle observer', (
      tester,
    ) async {
      final lifecycleStore = GameStore(prefs);
      addTearDown(lifecycleStore.dispose);
      final session = GameSession();
      final binding = GamePersistence(
        store: lifecycleStore,
        session: () => session,
        config: AiGameConfig(),
      );
      await tester.pump();
      session.hintsUsed = 2;
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(lifecycleStore.restore()!.session.hintsUsed, 2);
      await binding.close(abandon: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(lifecycleStore.canResume, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }
}
