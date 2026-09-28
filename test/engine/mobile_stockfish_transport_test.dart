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
  }

  @override
  void dispose() {}
}

/// Fully self-contained per-test fixture: the transport keeps a resident
/// engine in process-wide static state, so nothing may leak between tests.
class Fixture {
  Fixture() {
    MobileStockfishTransport.debugResetShared();
  }

  final engine = FakeNativeStockfish();
  int builds = 0;
  final errors = <Object>[];
  final lines = <String>[];
  final _subscriptions = <StreamSubscription<String>>[];

  MobileStockfishTransport transport() {
    final t = MobileStockfishTransport(
      createEngine: () {
        builds++;
        return engine;
      },
    );
    _subscriptions.add(t.lines.listen(lines.add, onError: errors.add));
    return t;
  }

  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    if (!engine.output.isClosed) await engine.output.close();
    MobileStockfishTransport.debugResetShared();
  }
}

void main() {
  test(
    'startup waits for ready, forwards lines, stop keeps engine resident',
    () async {
      final f = Fixture();
      final t = f.transport();
      final launch = t.launch();
      f.engine.state.value = native.StockfishState.ready;
      await launch;
      f.engine.output.add('uciok');
      await Future<void>.delayed(Duration.zero);
      expect(f.lines, ['uciok']);
      t.send('isready');
      await t.stop();
      // The search is interrupted but the engine is never quit: the stockfish
      // package cannot relaunch C++ main() in the same process (truncated UCI
      // options on the second run — the on-device "AI 启动失败" bug).
      expect(f.engine.commands, ['isready', 'stop']);
      expect(f.engine.state.value, native.StockfishState.ready);
      expect(f.errors, isEmpty);
      await t.stop();
      expect(() => t.send('uci'), throwsStateError);
      expect(t.launch, throwsStateError); // transport stays single-use
      await f.close();
    },
  );

  test('second session reuses the resident engine without rebuilding',
      () async {
    final f = Fixture();
    final first = f.transport();
    final launch = first.launch();
    f.engine.state.value = native.StockfishState.ready;
    await launch;
    await first.stop();

    final second = f.transport();
    await second.launch();
    expect(f.builds, 1); // resident engine reused, not recreated
    second.send('uci');
    f.engine.output.add('uciok');
    await Future<void>.delayed(Duration.zero);
    expect(f.lines, ['uciok']);
    expect(f.engine.commands, contains('uci'));
    await second.stop();
    expect(f.engine.state.value, native.StockfishState.ready);
    await f.close();
  });

  test('stop during starting settles launch and leaves engine resident',
      () async {
    final f = Fixture();
    final t = f.transport();
    final launch = t.launch();
    final stop = t.stop();
    f.engine.state.value = native.StockfishState.ready;
    await launch;
    await stop;
    // No interrupt was needed: the session never attached to the engine.
    expect(f.engine.commands, isEmpty);
    expect(f.engine.state.value, native.StockfishState.ready);
    await f.close();
  });

  test('native init error fails launch and stop stays safe', () async {
    final f = Fixture();
    final t = f.transport();
    final launch = t.launch();
    final assertion = expectLater(launch, throwsStateError);
    f.engine.state.value = native.StockfishState.error;
    await assertion;
    await t.stop();
    // A later session tries a fresh engine instead of caching the dead one.
    final second = f.transport();
    await expectLater(second.launch(), throwsStateError);
    expect(f.builds, 2);
    await second.stop();
    await f.close();
  });

  test('unexpected native disposal reaches error stream', () async {
    final f = Fixture();
    final t = f.transport();
    final launch = t.launch();
    f.engine.state.value = native.StockfishState.ready;
    await launch;
    f.engine.state.value = native.StockfishState.disposed;
    await Future<void>.delayed(Duration.zero);
    expect(f.errors.single, isA<StateError>());
    await t.stop();
    await f.close();
  });

  test('native output errors are forwarded', () async {
    final f = Fixture();
    final t = f.transport();
    final launch = t.launch();
    f.engine.state.value = native.StockfishState.ready;
    await launch;
    f.engine.output.addError(StateError('worker failed'));
    await Future<void>.delayed(Duration.zero);
    expect(f.errors.single, isA<StateError>());
    await t.stop();
    await f.close();
  });

  test('command injection and use before launch are rejected', () async {
    final f = Fixture();
    final t = f.transport();
    expect(() => t.send('uci'), throwsStateError);
    final launch = t.launch();
    f.engine.state.value = native.StockfishState.ready;
    await launch;
    expect(() => t.send('uci\nquit'), throwsFormatException);
    await t.stop();
    await f.close();
  });

  test('synchronous package constructor failure is not lost', () async {
    MobileStockfishTransport.debugResetShared();
    final errors = <Object>[];
    final broken = MobileStockfishTransport(
      createEngine: () => throw StateError('singleton busy'),
    );
    final sub = broken.lines.listen((_) {}, onError: errors.add);
    await expectLater(broken.launch(), throwsStateError);
    await broken.stop();
    await sub.cancel();
    MobileStockfishTransport.debugResetShared();
  });
}
