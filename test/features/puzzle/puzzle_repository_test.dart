import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/features/puzzle/puzzle_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';
import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late PuzzleRepository repository;
  late FailingPreferencesStore store;
  final day = DateTime(2026, 9, 28);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    repository = PuzzleRepository(prefs: prefs, catalog: catalog());
  });
  tearDown(() => repository.dispose());

  test('wrong book survives reopening, successful retry removes it', () async {
    await repository.record('p0', correct: false);
    expect(repository.mistakes, {'p0'});
    expect(repository.solved, isEmpty);
    final reopened = PuzzleRepository(prefs: prefs, catalog: catalog());
    addTearDown(reopened.dispose);
    expect(reopened.mistakes, {'p0'});
    await reopened.record('p0', correct: true);
    expect(reopened.mistakes, isEmpty);
    expect(reopened.solved, {'p0'});
    expect(
      jsonDecode(prefs.getString(PuzzleRepository.progressKey)!)['mistakes'],
      isEmpty,
    );
  });
  test(
    'duplicate success is idempotent; later wrong move enters notebook',
    () async {
      await repository.record('p0', correct: true);
      await repository.record('p0', correct: true);
      expect(repository.solved, {'p0'});
      await repository.record('p0', correct: false);
      expect(repository.mistakes, {'p0'});
      expect(() => repository.solved.clear(), throwsUnsupportedError);
    },
  );
  test('parallel writes across repositories preserve both results', () async {
    final other = PuzzleRepository(prefs: prefs, catalog: catalog());
    addTearDown(other.dispose);
    await Future.wait([
      repository.record('p0', correct: true),
      other.record('p1', correct: false),
      repository.record('p2', correct: true),
    ]);
    expect(repository.solved, {'p0', 'p2'});
    expect(repository.mistakes, {'p1'});
  });
  test('daily has ten unique IDs and persists under daily_YYYYMMDD', () async {
    final ids = await repository.daily(day);
    expect(ids.length, 10);
    expect(ids.toSet().length, 10);
    expect(jsonDecode(prefs.getString('daily_20260928')!), ids);
    final reopened = PuzzleRepository(prefs: prefs, catalog: catalog());
    addTearDown(reopened.dispose);
    expect(await reopened.daily(DateTime(2026, 9, 28, 23, 59)), ids);
    final tomorrow = await reopened.daily(day.add(const Duration(days: 1)));
    expect(tomorrow, isNot(ids));
    expect(await reopened.daily(day), ids);
  });
  test(
    'daily completion is per-day, not inherited from all-time completion',
    () async {
      final ids = await repository.daily(day);
      await repository.record(ids.first, correct: true);
      expect(repository.completed('daily_20260928'), isEmpty);
      await repository.record(ids.first, correct: false, day: 'daily_20260928');
      expect(repository.completed('daily_20260928'), isEmpty);
      await repository.record(ids.first, correct: true, day: 'daily_20260928');
      expect(repository.completed('daily_20260928'), {ids.first});
      expect(repository.mistakes, isEmpty);
      final reopened = PuzzleRepository(prefs: prefs, catalog: catalog());
      addTearDown(reopened.dispose);
      expect(reopened.completed('daily_20260928'), {ids.first});
      expect(reopened.completed('daily_20260929'), isEmpty);
    },
  );
  test(
    'failed progress save is visible, does not mutate state, can retry',
    () async {
      store.failKey = 'flutter.${PuzzleRepository.progressKey}';
      await expectLater(
        repository.record('p0', correct: true),
        throwsStateError,
      );
      expect(repository.solved, isEmpty);
      expect(prefs.getString(PuzzleRepository.progressKey), isNull);
      store.failKey = null;
      await repository.record('p0', correct: true);
      expect(repository.solved, {'p0'});
    },
  );
  test('failed daily save is not returned as a successful daily set', () async {
    store.failKey = 'flutter.daily_20260928';
    await expectLater(repository.daily(day), throwsStateError);
    expect(prefs.getString('daily_20260928'), isNull);
    store.failKey = null;
    expect((await repository.daily(day)).length, 10);
  });
  test(
    'corrupted daily selection is rejected, never silently regenerated',
    () async {
      await prefs.setString('daily_20260928', jsonEncode(['missing']));
      await expectLater(repository.daily(day), throwsFormatException);
      expect(prefs.getString('daily_20260928'), jsonEncode(['missing']));
    },
  );
  test('corrupt progress and unknown puzzle IDs surface errors', () async {
    await expectLater(
      repository.record('missing', correct: true),
      throwsArgumentError,
    );
    await prefs.setString(PuzzleRepository.progressKey, '{broken');
    expect(
      () => PuzzleRepository(prefs: prefs, catalog: catalog()),
      throwsFormatException,
    );
  });
  test('daily results must belong to a persisted daily selection', () async {
    await expectLater(
      repository.record('p0', correct: true, day: 'daily_20260928'),
      throwsArgumentError,
    );
  });
  test('date key handles month/year boundaries with zero padding', () {
    expect(PuzzleRepository.dailyKey(DateTime(2027, 1, 2)), 'daily_20270102');
    expect(PuzzleRepository.dailyKey(DateTime(2026, 12, 31)), 'daily_20261231');
  });
}
