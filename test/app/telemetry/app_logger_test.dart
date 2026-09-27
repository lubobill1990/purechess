import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/app_logger.dart';
import 'package:purechess/app/telemetry/crash_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'logger flushes structured diagnostics and bounds ring buffer',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'purechess_logger_test_',
      );
      final logger = AppLogger.testing();
      final output = <String?>[];
      final previousPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => output.add(message);
      try {
        await logger.init(directory: dir);
        for (var i = 0; i < 405; i++) {
          logger.log(LogLevel.info, 'chess', 'event $i');
        }
        await Future.wait(List.generate(3, (_) => logger.flush()));
        expect(logger.recent, hasLength(400));
        expect(logger.recent.first, contains('event 5'));
        expect(logger.recent.last, contains('[chess] event 404'));
        final flushing = logger.flush();
        logger.log(LogLevel.warn, 'chess', 'error during flush');
        await Future.wait([flushing, logger.flush()]);
        expect(
          File(logger.filePath!).readAsStringSync(),
          contains('event 404'),
        );
        expect(
          File(logger.filePath!).readAsStringSync(),
          contains('error during flush'),
        );
        expect(
          output.where((line) => line?.startsWith('logger:') == true),
          isEmpty,
        );
      } finally {
        await logger.dispose();
        await dir.delete(recursive: true);
        debugPrint = previousPrint;
      }
    },
  );

  test('logger rotates oversized file at startup', () async {
    final dir = await Directory.systemTemp.createTemp('purechess_logger_test_');
    final logger = AppLogger.testing();
    try {
      File('${dir.path}/app.log').writeAsStringSync('x' * (512 * 1024 + 1));
      await logger.init(directory: dir);
      await logger.flush();
      expect(File('${dir.path}/app.1.log').lengthSync(), 512 * 1024 + 1);
      expect(
        File(logger.filePath!).readAsStringSync(),
        contains('session start'),
      );
    } finally {
      await logger.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('runGuarded captures synchronous errors in local diagnostics', () {
    runGuarded<void>(() => throw StateError('chess failure'));
    expect(AppLogger.instance.recent.last, contains('zone_error'));
    expect(AppLogger.instance.recent.last, contains('chess failure'));
  });

  test('handled errors keep diagnostic context local', () {
    reportHandledError('chess_engine_start', StateError('private FEN'));
    expect(AppLogger.instance.recent.last, contains('handled_error'));
    expect(AppLogger.instance.recent.last, contains('private FEN'));
  });
}
