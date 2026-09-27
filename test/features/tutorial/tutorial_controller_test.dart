import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/features/tutorial/tutorial_controller.dart';
import 'package:purechess/features/tutorial/tutorial_engine.dart';
import 'package:purechess/features/tutorial/tutorial_level.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';

class ControlledEngine implements TutorialEngine {
  final Completer<Move> reply = Completer<Move>();
  int calls = 0;
  int closes = 0;
  bool failClose = false;

  @override
  Future<Move> chooseMove(Board board) {
    calls++;
    return reply.future;
  }

  @override
  Future<void> dispose() async {
    closes++;
    if (failClose) throw StateError('Cannot close test AI');
  }
}

class SequenceEngine extends FakeEngine {
  SequenceEngine(this.moves);
  final List<String> moves;
  int calls = 0;

  @override
  Future<Move> chooseMove(Board board) async => Move.fromUci(moves[calls++]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TutorialCatalog catalog;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    catalog = await TutorialCatalog.load();
  });

  TutorialController create({TutorialEngine? engine, bool dispose = true}) {
    final controller = TutorialController(
      catalog: catalog,
      prefs: prefs,
      engine: engine ?? FakeEngine(random: Random(42)),
    );
    if (dispose) addTearDown(controller.dispose);
    return controller;
  }

  Future<TutorialController> graduate({TutorialEngine? engine}) async {
    await prefs.setInt(TutorialController.progressKey, 18);
    return create(engine: engine)..start(18);
  }

  test('first run unlocks only first level, invalid indices rejected', () {
    final c = create();
    expect(c.completed, 0);
    for (final index in [-1, 1, 19]) {
      expect(() => c.start(index), throwsStateError);
    }
    c.start(0);
    expect(c.hint, Move.fromUci('d4e4'));
  });

  test('solving persists exactly one unlock and survives reload', () async {
    final c = create()..start(0);
    await c.play(Move.fromUci('d4e4'));
    expect(c.solved, isTrue);
    expect(c.saved, isTrue);
    expect(c.completed, 1);
    await prefs.reload();
    expect(create().completed, 1);
    c.start(1);
    expect(c.level.id, 'queen');
    expect(() => c.start(2), throwsStateError);
  });

  test('replaying an old level never decreases progress', () async {
    await prefs.setInt(TutorialController.progressKey, 10);
    final c = create()..start(0);
    await c.play(Move.fromUci('d4e4'));
    expect(c.completed, 10);
    expect(prefs.getInt(TutorialController.progressKey), 10);
  });

  test(
    'legal wrong move keeps board, fails, and retry resets attempt',
    () async {
      final c = create()..start(0);
      final initial = c.board.toFen();
      await c.play(Move.fromUci('d4d5'));
      expect(c.failed, isTrue);
      expect(c.board.toFen(), initial);
      expect(c.message, c.level.failure);
      expect(c.completed, 0);
      await c.play(Move.fromUci('d4e4'));
      expect(c.solved, isFalse);
      c.start(0);
      expect(c.failed, isFalse);
      expect(c.message, isNull);
      await c.play(Move.fromUci('d4e4'));
      expect(c.saved, isTrue);
    },
  );

  test('illegal input explains rule without consuming attempt', () async {
    final c = create()..start(0);
    final fen = c.board.toFen();
    await c.play(Move.fromUci('d4d8'));
    expect(c.failed, isFalse);
    expect(c.board.toFen(), fen);
    expect(c.message, contains('不合法'));
    await c.play(Move.fromUci('d4e4'));
    expect(c.saved, isTrue);
  });

  test('completion cannot be saved without solving', () async {
    final c = create()..start(0);
    await c.saveCompletion();
    expect(c.completed, 0);
    expect(prefs.getInt(TutorialController.progressKey), isNull);
  });

  test(
    'each lesson unlocks the next, graduation not a fixed solution',
    () async {
      final c = create();
      for (var i = 0; i < 18; i++) {
        c.start(i);
        await c.play(c.level.line.first);
        expect(c.saved, isTrue, reason: c.level.id);
        expect(c.completed, i + 1);
      }
      c.start(18);
      expect(c.solved, isFalse);
      expect(c.hint, isNull);
      await c.saveCompletion();
      expect(c.completed, 18);
    },
  );

  test(
    'save failure preserves solved board and does not cache an unlock',
    () async {
      final store = FailingPreferencesStore();
      SharedPreferencesStorePlatform.instance = store;
      await prefs.reload();
      store.failKey = 'flutter.tutorial_progress';
      final c = create()..start(0);
      await c.play(Move.fromUci('d4e4'));
      expect(c.solved, isTrue);
      expect(c.saved, isFalse);
      expect(c.saving, isFalse);
      expect(c.completed, 0);
      expect(create().completed, 0);
      expect(c.explanation, contains('重新保存'));
      final solvedFen = c.board.toFen();
      store.failKey = null;
      await c.saveCompletion();
      expect(c.saved, isTrue);
      expect(c.completed, 1);
      expect(c.board.toFen(), solvedFen);
    },
  );

  test(
    'invalid stored progress is surfaced instead of silently reset',
    () async {
      for (final invalid in [-1, 20]) {
        await prefs.setInt(TutorialController.progressKey, invalid);
        expect(() => create(), throwsFormatException);
      }
    },
  );

  test(
    'puzzle controller preserves automatic opponent reply semantics',
    () async {
      final exercise = TutorialLevel.fromJson({
        'id': 'reply',
        'title': 'Reply',
        'goal': 'movement',
        'fen': Board().toFen(),
        'line': ['e2e4', 'e7e5', 'g1f3'],
        'intro': 'Start',
        'success': 'Done',
        'failure': 'Retry',
      });
      catalog = TutorialCatalog([exercise, catalog.levels.last]);
      final c = create()..start(0);
      await c.play(Move.fromUci('e2e4'));
      expect(c.board.pieceAt(parseSquare('e5'))?.color, Color.black);
      expect(c.board.turn, Color.white);
      expect(c.solved, isFalse);
      c.revealHint();
      expect(c.hint, Move.fromUci('g1f3'));
      await c.play(Move.fromUci('g1f3'));
      expect(c.saved, isTrue);
    },
  );

  test(
    'graduation is a real game and requires play before resignation',
    () async {
      final c = await graduate();
      expect(c.board.pieceAt(parseSquare('d8')), isNull);
      await c.resign();
      expect(c.solved, isFalse);
      await c.play(Move.fromUci('e2e4'));
      expect(c.board.plyCount, 2);
      expect(c.board.turn, Color.white);
      expect(c.solved, isFalse);
      expect(c.completed, 18);
      await c.resign();
      expect(c.solved, isTrue);
      expect(c.saved, isTrue);
      expect(c.completed, 19);
      expect(c.outcome, contains('认输'));
    },
  );

  test('pending AI blocks duplicate moves, reset and resignation', () async {
    final engine = ControlledEngine();
    final c = await graduate(engine: engine);
    final playing = c.play(Move.fromUci('e2e4'));
    expect(c.thinking, isTrue);
    expect(c.canPlay, isFalse);
    expect(() => c.start(18), throwsStateError);
    await c.play(Move.fromUci('d2d4'));
    await c.resign();
    expect(engine.calls, 1);
    expect(c.solved, isFalse);
    engine.reply.complete(Move.fromUci('e7e5'));
    await playing;
    expect(c.board.plyCount, 2);
    expect(c.thinking, isFalse);
    expect(c.board.turn, Color.white);
  });

  for (final illegal in [false, true]) {
    test(
      'AI ${illegal ? 'illegal reply' : 'failure'} visibly switches to fallback',
      () async {
        final engine = ControlledEngine();
        final c = await graduate(engine: engine);
        final playing = c.play(Move.fromUci('e2e4'));
        if (illegal) {
          engine.reply.complete(Move.fromUci('a8a1'));
        } else {
          engine.reply.completeError(StateError('Unavailable'));
        }
        await playing;
        expect(c.fallback, isTrue);
        expect(c.aiNotice, contains('简易 AI'));
        expect(engine.closes, 1);
        expect(c.board.plyCount, 2);
        expect(c.board.turn, Color.white);
        await c.play(c.board.legalMoves().first);
        expect(engine.calls, 1);
        expect(c.board.plyCount, 4);
      },
    );
  }

  test(
    'AI cleanup failure is reported and fallback still completes a reply',
    () async {
      final engine = ControlledEngine()..failClose = true;
      final c = await graduate(engine: engine);
      final playing = c.play(Move.fromUci('e2e4'));
      engine.reply.completeError(StateError('Unavailable'));
      await playing;
      expect(c.board.plyCount, 2);
      expect(c.aiNotice, contains('关闭'));
      expect(c.fallback, isTrue);
    },
  );

  for (final fail in [false, true]) {
    test(
      'late AI ${fail ? 'failure' : 'reply'} after disposal cannot change state',
      () async {
        await prefs.setInt(TutorialController.progressKey, 18);
        final engine = ControlledEngine();
        final c = create(engine: engine, dispose: false)..start(18);
        var notifications = 0;
        c.addListener(() => notifications++);
        final playing = c.play(Move.fromUci('e2e4'));
        c.dispose();
        final count = notifications;
        if (fail) {
          engine.reply.completeError(StateError('Late failure'));
        } else {
          engine.reply.complete(Move.fromUci('e7e5'));
        }
        await playing;
        expect(c.board.plyCount, 1);
        expect(notifications, count);
        expect(prefs.getInt(TutorialController.progressKey), 18);
        expect(engine.closes, 1);
      },
    );
  }

  for (final entry in {
    'checkmate': ['7k/5K2/6Q1/8/8/8/8/8 w - - 0 1', 'g6g7'],
    'stalemate': ['7k/5K2/8/6Q1/8/8/8/8 w - - 0 1', 'g5g6'],
    'insufficient material': ['7k/8/8/8/8/8/r7/K7 w - - 0 1', 'a1a2'],
    'fifty moves': ['7k/8/8/8/8/8/R7/K7 w - - 99 1', 'a2b2'],
  }.entries) {
    test('graduation ${entry.key} finishes without an AI reply', () async {
      final graduation = TutorialLevel.fromJson({
        'id': 'endgame',
        'title': 'End',
        'goal': 'graduation',
        'fen': entry.value.first,
        'line': <String>[],
        'intro': 'Start',
        'success': 'Done',
        'failure': 'Retry',
      });
      catalog = TutorialCatalog([graduation]);
      final engine = ControlledEngine();
      final c = create(engine: engine)..start(0);
      await c.play(Move.fromUci(entry.value.last));
      expect(c.solved, isTrue);
      expect(c.saved, isTrue);
      expect(c.completed, 1);
      expect(engine.calls, 0);
    });
  }

  test('FakeEngine chooses only legal moves over a full game', () async {
    final engine = FakeEngine(random: Random(3));
    final board = Board.fromFen(catalog.levels.last.fen);
    for (var ply = 0; ply < 400 && board.status == GameStatus.playing; ply++) {
      final move = await engine.chooseMove(board);
      expect(board.isLegal(move), isTrue);
      board.play(move);
    }
    await engine.dispose();
  });

  test('AI checkmates white and graduation still persists', () async {
    catalog = TutorialCatalog([
      TutorialLevel.fromJson({
        'id': 'loss',
        'title': 'Loss',
        'goal': 'graduation',
        'fen': '8/8/8/8/8/6q1/P4k2/7K w - - 0 1',
        'line': <String>[],
        'intro': 'Start',
        'success': 'Done',
        'failure': 'Retry',
      }),
    ]);
    final engine = SequenceEngine(['g3g2']);
    final c = create(engine: engine)..start(0);
    await c.play(Move.fromUci('a2a3'));
    expect(c.board.status, GameStatus.checkmate);
    expect(c.outcome, 'AI 获胜 · 将杀');
    expect(c.completed, 1);
    expect(c.saved, isTrue);
    expect(engine.calls, 1);
  });

  test('graduation retains history and auto-adjudicates repetition', () async {
    final c = await graduate(
      engine: SequenceEngine(['g8f6', 'f6g8', 'g8f6', 'f6g8']),
    );
    for (final move in ['g1f3', 'f3g1', 'g1f3', 'f3g1']) {
      await c.play(Move.fromUci(move));
    }
    expect(c.board.status, GameStatus.threefoldRepetition);
    expect(c.completed, 19);
    expect(c.saved, isTrue);
    expect(c.outcome, contains('三次重复'));
  });
}
