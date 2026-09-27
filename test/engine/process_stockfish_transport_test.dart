import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/engine/stockfish_transport.dart';

void main() {
  test(
    'missing executable fails launch explicitly and cleanup is repeatable',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'chess_missing_ai_',
      );
      final transport = ProcessStockfishTransport(
        executablePath:
            '${directory.path}${Platform.pathSeparator}not-installed',
      );
      final subscription = transport.lines.listen((_) {});
      try {
        expect(() => transport.send('uci'), throwsStateError);
        await expectLater(transport.launch(), throwsA(isA<ProcessException>()));
        await transport.stop();
        await transport.stop();
        await expectLater(transport.launch(), throwsStateError);
      } finally {
        await subscription.cancel();
        await directory.delete();
      }
    },
  );
  test('stop before launch prevents a late child process', () async {
    final transport = ProcessStockfishTransport();
    final subscription = transport.lines.listen((_) {});
    await transport.stop();
    await expectLater(transport.launch(), throwsStateError);
    await subscription.cancel();
  });
}
