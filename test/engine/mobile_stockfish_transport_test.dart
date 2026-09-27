import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/engine/mobile_stockfish_transport.dart';
import 'package:stockfish/stockfish.dart' as native;

class FakeNativeStockfish implements native.Stockfish {
  @override
  final ValueNotifier<native.StockfishState> state = ValueNotifier(
    native.StockfishState.starting,
  );
  final output = StreamController<String>.broadcast();
  final commands = <String>[];
  @override
  Completer<native.Stockfish>? get completer => null;
  @override
  Stream<String> get stdout => output.stream;
  @override
  set stdin(String line) {
    if (state.value != native.StockfishState.ready) {
      throw StateError('not ready');
    }
    commands.add(line);
    if (line == 'quit') {
      scheduleMicrotask(() {
        state.value = native.StockfishState.disposed;
        output.close();
      });
    }
  }

  @override
  void dispose() => stdin = 'quit';
}

void main() {
  late FakeNativeStockfish engine;
  late MobileStockfishTransport transport;
  late List<Object> errors;
  late List<String> lines;
  late StreamSubscription<String> subscription;
  setUp(() {
    engine = FakeNativeStockfish();
    transport = MobileStockfishTransport(createEngine: () => engine);
    errors = [];
    lines = [];
    subscription = transport.lines.listen(lines.add, onError: errors.add);
  });
  tearDown(() async {
    await subscription.cancel();
    await engine.output.close();
    engine.state.dispose();
  });

  test(
    'native startup waits for ready, forwards lines, and confirms quit',
    () async {
      final launch = transport.launch();
      engine.state.value = native.StockfishState.ready;
      await launch;
      engine.output.add('uciok');
      await Future<void>.delayed(Duration.zero);
      expect(lines, ['uciok']);
      transport.send('isready');
      await transport.stop();
      expect(engine.commands, ['isready', 'stop', 'quit']);
      expect(engine.state.value, native.StockfishState.disposed);
      expect(errors, isEmpty);
      await transport.stop();
      expect(() => transport.send('uci'), throwsStateError);
      await expectLater(transport.launch(), throwsStateError);
    },
  );
  test('stop during starting waits for readiness then quits', () async {
    final launch = transport.launch();
    final stop = transport.stop();
    engine.state.value = native.StockfishState.ready;
    await launch;
    await stop;
    expect(engine.commands, ['stop', 'quit']);
  });
  test('native init error fails launch and refuses unsafe shutdown', () async {
    final launch = transport.launch();
    final assertion = expectLater(launch, throwsStateError);
    engine.state.value = native.StockfishState.error;
    await assertion;
    await expectLater(transport.stop(), throwsStateError);
    expect(errors, isNotEmpty);
  });
  test('unexpected native disposal reaches error stream', () async {
    final launch = transport.launch();
    engine.state.value = native.StockfishState.ready;
    await launch;
    engine.state.value = native.StockfishState.disposed;
    await Future<void>.delayed(Duration.zero);
    expect(errors.single, isA<StateError>());
    await transport.stop();
  });
  test('native output errors are forwarded', () async {
    final launch = transport.launch();
    engine.state.value = native.StockfishState.ready;
    await launch;
    engine.output.addError(StateError('worker failed'));
    await Future<void>.delayed(Duration.zero);
    expect(errors.single, isA<StateError>());
    await transport.stop();
  });
  test('command injection and use before launch are rejected', () async {
    expect(() => transport.send('uci'), throwsStateError);
    final launch = transport.launch();
    engine.state.value = native.StockfishState.ready;
    await launch;
    expect(() => transport.send('uci\nquit'), throwsFormatException);
    await transport.stop();
  });
  test('synchronous package constructor failure is not lost', () async {
    await subscription.cancel();
    final broken = MobileStockfishTransport(
      createEngine: () => throw StateError('singleton busy'),
    );
    subscription = broken.lines.listen(lines.add, onError: errors.add);
    await expectLater(broken.launch(), throwsStateError);
    await broken.stop();
  });
}
