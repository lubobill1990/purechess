import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/engine/uci_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_stockfish_transport.dart';

void main() {
  late Directory dir;
  late Analytics analytics;
  late SharedPreferences prefs;
  late FakeStockfishTransport transport;
  late StockfishService service;
  late List<StockfishState> states;
  final failure = isA<StockfishException>();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'crashStreak': 3});
    prefs = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('chess_engine_test_');
    analytics = Analytics.testing(directory: dir);
    await analytics.init(prefs);
    transport = FakeStockfishTransport();
    service = StockfishService(
      transportFactory: () => transport,
      analytics: analytics,
      prefs: prefs,
      handshakeTimeout: const Duration(milliseconds: 100),
      analysisTimeout: const Duration(milliseconds: 100),
    );
    states = [];
    service.status.addListener(() => states.add(service.state));
  });

  tearDown(() async {
    await service.dispose();
    analytics.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> waitFor(StockfishState target) async {
    for (var i = 0; i < 100; i++) {
      if (service.state == target) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('Did not reach $target: ${service.state}');
  }

  test(
    'shared startup, handshake order, ready, sentinel and safe telemetry',
    () async {
      final first = service.ensureStarted();
      final second = service.ensureStarted();
      expect(identical(first, second), isTrue);
      expect(
        File('${dir.path}/phase.txt').readAsStringSync(),
        'chess_engine_start',
      );
      await Future.wait([first, second]);
      expect(service.state, StockfishState.ready);
      expect(service.engineName, 'Stockfish Fake');
      expect(states, [StockfishState.starting, StockfishState.ready]);
      expect(transport.commands, [
        'uci',
        'setoption name Threads value 1',
        'setoption name Hash value 16',
        'setoption name MultiPV value 1',
        'isready',
      ]);
      expect(File('${dir.path}/phase.txt').existsSync(), isFalse);
      expect(prefs.getInt('crashStreak'), 0);
      await service.ensureStarted();
      expect(transport.commands.where((c) => c == 'uci'), hasLength(1));
      final events = File('${dir.path}/pending_events.jsonl')
          .readAsLinesSync()
          .map(jsonDecode);
      final params = (events.last as Map)['params'] as Map;
      expect(params['success'], 1);
      expect(params['duration_ms'], isA<int>());
      expect(params.containsKey('fen'), isFalse);
      expect(params.containsKey('error'), isFalse);
    },
  );

  for (final mode in [
    'launch',
    'uci timeout',
    'ready timeout',
    'write',
    'options',
  ]) {
    test('startup failure visible and cleaned: $mode', () async {
      switch (mode) {
        case 'launch':
          transport.launchError = StateError('native failed');
        case 'uci timeout':
          transport.handshake = false;
        case 'ready timeout':
          transport.ready = false;
        case 'write':
          transport.sendErrorPrefix = 'uci';
        case 'options':
          transport.omitElo = true;
      }
      await expectLater(service.ensureStarted(), throwsA(failure));
      expect(service.state, StockfishState.failed);
      expect(service.lastError, isNotNull);
      expect(service.lastError!.message, isNot(contains('Stockfish')));
      expect(transport.stopped, isTrue);
      expect(File('${dir.path}/phase.txt').existsSync(), isFalse);
      expect(prefs.getInt('crashStreak'), 3);
      final text = File('${dir.path}/pending_events.jsonl').readAsStringSync();
      expect(text, contains('"success":0'));
      expect(text, isNot(contains('native failed')));
    });
  }
  test('failed startup may retry with fresh transport', () async {
    transport.launchError = StateError('missing');
    await expectLater(service.ensureStarted(), throwsA(failure));
    transport = FakeStockfishTransport();
    await service.ensureStarted();
    expect(service.state, StockfishState.ready);
    expect(service.lastError, isNull);
  });
  test('cp evaluation, legal principal variation and depth command', () async {
    final result = await service.analyzePosition(Fen.initial, depth: 8);
    expect(result.cp, 24);
    expect(result.mate, isNull);
    expect(result.bestMove, 'e2e4');
    expect(result.bestLine, ['e2e4', 'e7e5']);
    expect(result.depth, 8);
    expect(() => result.bestLine.clear(), throwsUnsupportedError);
    expect(transport.commands.last, 'go depth 8');
    expect(transport.commands, contains('position fen ${Fen.initial}'));
    expect(service.state, StockfishState.ready);
    expect(File('${dir.path}/phase.txt').existsSync(), isFalse);
  });
  test('black side score remains side-to-move relative', () async {
    transport.result = ['info depth 4 score cp -32 pv e7e5', 'bestmove e7e5'];
    final result = await service.analyzePosition(
      'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
    );
    expect(result.cp, -32);
  });
  test('mate evaluation remains distinct from centipawns', () async {
    transport.result = ['info depth 4 score mate 1 pv f7g7', 'bestmove f7g7'];
    final result = await service.analyzePosition(
      '7k/5Q2/6K1/8/8/8/8/8 w - - 0 1',
    );
    expect(result.mate, 1);
    expect(result.cp, isNull);
  });
  test(
    'multipv, bounds, and partial info never corrupt exact principal score',
    () async {
      transport.result = [
        'info depth 8 score cp 24 pv e2e4 e7e5',
        'info depth 9 multipv 2 score cp 80 pv d2d4',
        'info depth 9 score cp 50 lowerbound pv d2d4',
        'info depth 10 score cp 10 upperbound pv d2d4',
        'info depth 10 nodes 500',
        'bestmove d2d4',
      ];
      final result = await service.analyzePosition(Fen.initial);
      expect(result.cp, 24);
      expect(result.score.bound, UciScoreBound.exact);
      expect(result.bestMove, 'd2d4');
      expect(result.bestLine.first, 'e2e4');
    },
  );
  for (final level in stockfishDifficulties) {
    test(
      'difficulty ${level.level} sends exact limits and resets strength modes',
      () async {
        await service.analyzePosition(Fen.initial, difficulty: level.level);
        expect(
          transport.commands,
          containsAllInOrder([
            'ucinewgame',
            ...level.commands,
            'isready',
            'position fen ${Fen.initial}',
            'go movetime ${level.movetimeMs}',
          ]),
        );
        if (level.level <= 5) {
          expect(level.skill, (level.level - 1) * 2);
          expect(level.elo, isNull);
        } else {
          expect(level.elo, 1600 + (level.level - 6) * 300);
          expect(level.skill, 20);
        }
      },
    );
  }
  test('switching high to low difficulty disables Elo limit', () async {
    await service.analyzePosition(Fen.initial, difficulty: 10);
    transport.commands.clear();
    await service.analyzePosition(Fen.initial, difficulty: 1);
    expect(
      transport.commands,
      contains('setoption name UCI_LimitStrength value false'),
    );
    expect(transport.commands, contains('setoption name Skill Level value 0'));
    expect(transport.commands.any((c) => c.contains('UCI_Elo')), isFalse);
  });
  for (final entry in [
    ('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1', true),
    ('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1', false),
  ]) {
    test('terminal position: mate=${entry.$2}', () async {
      transport.result = ['bestmove (none)'];
      final result = await service.analyzePosition(entry.$1);
      expect(result.bestMove, isNull);
      expect(result.bestLine, isEmpty);
      expect(entry.$2 ? result.mate : result.cp, 0);
    });
  }
  for (final entry in [
    ('bad fen', 1, null),
    ('${Fen.initial}\nquit', 1, null),
    ('7k/6Q1/6K1/8/8/8/8/8 w - - 0 1', 1, null),
    ('4k3/8/8/8/8/8/8/4K3 w K - 0 1', 1, null),
    ('4k3/8/8/8/8/8/8/4K3 w - d6 0 1', 1, null),
    ('4k3/8/8/8/PPPPPPPP/PP6/8/4K3 w - - 0 1', 1, null),
    (Fen.initial, 0, null),
    (Fen.initial, 11, null),
    (Fen.initial, 1, 0),
  ]) {
    test('invalid input never enters native transport: $entry', () async {
      await expectLater(
        service.analyzePosition(
          entry.$1,
          difficulty: entry.$2,
          depth: entry.$3,
        ),
        throwsA(failure),
      );
      expect(transport.launched, isFalse);
    });
  }
  for (final lines in [
    ['bestmove 0000'],
    ['bestmove e2e4'],
    ['info depth 2 score cp 10 pv e2e5', 'bestmove e2e4'],
    ['info depth 2 score cp 10 pv e2e4', 'bestmove e2e5'],
    ['info score cp nope'],
    ['info string ERROR: network unavailable'],
  ]) {
    test(
      'malformed or incomplete result fails without success fallback: $lines',
      () async {
        transport.result = lines;
        await expectLater(
          service.analyzePosition(Fen.initial),
          throwsA(failure),
        );
        expect(service.state, StockfishState.failed);
        expect(service.lastError, isNotNull);
        expect(transport.stopped, isTrue);
      },
    );
  }
  test('analysis timeout tears down old session before retry', () async {
    transport.analysis = false;
    await expectLater(service.analyzePosition(Fen.initial), throwsA(failure));
    expect(service.state, StockfishState.failed);
    expect(transport.stopped, isTrue);
    transport = FakeStockfishTransport();
    final result = await service.analyzePosition(Fen.initial);
    expect(result.cp, 24);
  });
  for (final exit in [true, false]) {
    test(
      'unexpected ${exit ? 'EOF' : 'stream error'} fails pending search',
      () async {
        transport.analysis = false;
        final pending = service.analyzePosition(Fen.initial);
        final assertion = expectLater(pending, throwsA(failure));
        await waitFor(StockfishState.analyzing);
        if (exit) {
          await transport.output.close();
        } else {
          transport.output.addError(StateError('native stderr'));
        }
        await assertion;
        expect(service.state, StockfishState.failed);
        expect(service.lastError, isNotNull);
      },
    );
  }
  test('idle engine exit is visible immediately', () async {
    await service.ensureStarted();
    await transport.output.close();
    expect(service.state, StockfishState.failed);
    expect(service.lastError!.message, contains('意外退出'));
  });
  test(
    'overlapping analysis is rejected without damaging first request',
    () async {
      transport.analysis = false;
      final first = service.analyzePosition(Fen.initial);
      await waitFor(StockfishState.analyzing);
      await expectLater(service.analyzePosition(Fen.initial), throwsA(failure));
      await Future<void>.delayed(Duration.zero);
      for (final line in transport.result) {
        transport.output.add(line);
      }
      expect((await first).cp, 24);
      expect(service.state, StockfishState.ready);
    },
  );
  test('stop cancels analysis and awaits cleanup before restart', () async {
    transport.analysis = false;
    final first = service.analyzePosition(Fen.initial);
    final assertion = expectLater(first, throwsA(failure));
    await waitFor(StockfishState.analyzing);
    await service.stop();
    await assertion;
    expect(service.state, StockfishState.stopped);
    transport = FakeStockfishTransport();
    expect((await service.analyzePosition(Fen.initial)).cp, 24);
  });
  test('stop during launch prevents ready resurrection', () async {
    transport.launchGate = Completer<void>();
    final startup = service.ensureStarted();
    final assertion = expectLater(startup, throwsA(failure));
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    await assertion;
    expect(service.state, StockfishState.stopped);
    expect(states.last, StockfishState.stopped);
    expect(states, isNot(contains(StockfishState.ready)));
  });
  test('start while stopping is rejected; stop is idempotent', () async {
    await service.ensureStarted();
    transport.stopGate = Completer<void>();
    final stopping = service.stop();
    expect(identical(stopping, service.stop()), isTrue);
    await expectLater(service.ensureStarted(), throwsA(failure));
    transport.stopGate!.complete();
    await stopping;
    await service.stop();
    expect(service.state, StockfishState.stopped);
  });
  test('cleanup error is visible and prevents unsafe native restart', () async {
    await service.ensureStarted();
    transport.stopError = StateError('native thread still alive');
    await expectLater(service.stop(), throwsA(failure));
    expect(service.state, StockfishState.failed);
    expect(service.lastError!.message, contains('停止失败'));
    await expectLater(service.ensureStarted(), throwsA(failure));
  });
  test('dispose cancels active work and is terminal/idempotent', () async {
    await service.ensureStarted();
    await service.dispose();
    await service.dispose();
    expect(service.state, StockfishState.disposed);
    await expectLater(service.ensureStarted(), throwsA(failure));
  });
}
