import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/engine/stockfish_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final executable = Platform.environment['STOCKFISH_EXECUTABLE'];
  test(
    'real engine handshake, all levels, mate and restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final directory = await Directory.systemTemp.createTemp('chess_native_');
      final analytics = Analytics.testing(directory: directory);
      await analytics.init(prefs);
      final service = StockfishService(
        transportFactory: () =>
            ProcessStockfishTransport(executablePath: executable),
        analytics: analytics,
        prefs: prefs,
      );
      try {
        await service.ensureStarted();
        expect(service.engineName, contains('Stockfish'));
        for (var level = 1; level <= 10; level++) {
          final result = await service.analyzePosition(
            Fen.initial,
            difficulty: level,
          );
          expect(result.cp, isNotNull);
          expect(result.bestLine, isNotEmpty);
          expect(Board().isLegal(Move.fromUci(result.bestMove!)), isTrue);
          // Test output is a local smoke record, never telemetry.
          // ignore: avoid_print
          print(
            'level=$level cp=${result.cp} depth=${result.depth} '
            'best=${result.bestMove} pv=${result.bestLine.join(' ')}',
          );
        }
        final mate = await service.analyzePosition(
          '7k/5Q2/6K1/8/8/8/8/8 w - - 0 1',
          difficulty: 10,
          depth: 6,
        );
        expect(mate.mate, 1);
        await service.stop();
        await service.ensureStarted();
        expect(
          (await service.analyzePosition(Fen.initial, depth: 6)).cp,
          isNotNull,
        );
      } finally {
        await service.dispose();
        analytics.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: executable == null
        ? 'Set STOCKFISH_EXECUTABLE to a local engine binary'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
