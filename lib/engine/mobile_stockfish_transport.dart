import 'dart:async';

import 'package:stockfish/stockfish.dart' as native;

import 'stockfish_transport.dart';

/// Android/iOS package adapter. The package's "ready" only means workers were
/// spawned; StockfishService still performs the complete UCI/ready handshake.
class MobileStockfishTransport implements StockfishTransport {
  MobileStockfishTransport({native.Stockfish Function()? createEngine})
    : _createEngine = createEngine ?? native.Stockfish.new;

  final native.Stockfish Function() _createEngine;
  final _lines = StreamController<String>();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  native.Stockfish? _engine;
  StreamSubscription<String>? _stdout;
  bool _launched = false;
  bool _stopping = false;
  Future<void>? _stopFuture;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> launch() async {
    if (_launched || _stopping) throw StateError('AI transport is single-use');
    _launched = true;
    final ready = _ready.future.timeout(const Duration(seconds: 15));
    try {
      final engine = _engine = _createEngine();
      _stdout = engine.stdout.listen(
        _lines.add,
        onError: _lines.addError,
        onDone: () {
          if (!_stopping) _lines.close();
        },
      );
      engine.state.addListener(_onState);
      _onState();
    } catch (error, stack) {
      if (!_ready.isCompleted) _ready.completeError(error, stack);
    }
    await ready;
  }

  void _onState() {
    final state = _engine!.state.value;
    if (state == native.StockfishState.ready && !_ready.isCompleted) {
      _ready.complete();
    }
    if (state == native.StockfishState.error ||
        state == native.StockfishState.disposed) {
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('AI native startup failed'));
      }
      if (!_exited.isCompleted) _exited.complete();
      if (!_stopping && !_lines.isClosed) {
        _lines.addError(StateError('AI native engine exited: $state'));
      }
    }
  }

  @override
  void send(String line) {
    if (_stopping || _engine == null) throw StateError('AI transport stopped');
    if (line.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Expected one UCI command');
    }
    _engine!.stdin = line;
  }

  @override
  Future<void> stop() => _stopFuture ??= _stop();

  Future<void> _stop() async {
    _stopping = true;
    final engine = _engine;
    try {
      if (engine != null) {
        if (engine.state.value == native.StockfishState.starting) {
          await _ready.future.timeout(const Duration(seconds: 15));
        }
        if (engine.state.value == native.StockfishState.ready) {
          engine.stdin = 'stop';
          engine.stdin = 'quit';
          await _exited.future.timeout(const Duration(seconds: 5));
        }
        // The package has no force-kill API and its init-error state does not
        // prove that native workers/singleton were cleaned up. Fail closed.
        if (engine.state.value != native.StockfishState.disposed) {
          throw StateError('AI native shutdown could not be confirmed');
        }
      }
    } finally {
      engine?.state.removeListener(_onState);
      await _stdout?.cancel();
      await _lines.close();
    }
  }
}
