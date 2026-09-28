import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stockfish/stockfish.dart' as native;

import 'stockfish_transport.dart';

/// Android/iOS package adapter. The package's "ready" only means workers were
/// spawned; StockfishService still performs the complete UCI/ready handshake.
///
/// The in-process engine cannot survive quit/relaunch: the package re-enters
/// Stockfish's C++ main() whose static state (option registry, threads)
/// persists, so a second launch emits a truncated UCI option list and every
/// restart fails validation ("AI 启动失败" on device). One native engine is
/// therefore kept alive for the whole process; each transport session only
/// interrupts the search on stop and never sends quit.
class MobileStockfishTransport implements StockfishTransport {
  MobileStockfishTransport({native.Stockfish Function()? createEngine})
    : _createEngine = createEngine ?? native.Stockfish.new;

  static native.Stockfish? _shared;
  static Future<native.Stockfish>? _sharedStarting;

  /// Drops the resident engine reference (tests only — the real package
  /// cannot rebuild a healthy engine in the same process).
  @visibleForTesting
  static void debugResetShared() {
    _shared = null;
    _sharedStarting = null;
  }

  final native.Stockfish Function() _createEngine;
  final _lines = StreamController<String>();
  native.Stockfish? _engine;
  StreamSubscription<String>? _stdout;
  Future<void>? _launchFuture;
  bool _launched = false;
  bool _stopping = false;
  Future<void>? _stopFuture;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> launch() {
    if (_launched || _stopping) {
      throw StateError('AI transport is single-use');
    }
    _launched = true;
    return _launchFuture = _launch();
  }

  Future<void> _launch() async {
    final engine = await _acquireShared();
    if (_stopping) return; // stopped while starting; leave engine resident
    _engine = engine;
    _stdout = engine.stdout.listen(
      _lines.add,
      onError: _lines.addError,
      onDone: () {
        // The resident engine's stdout only closes when the native side died.
        if (!_stopping && !_lines.isClosed) {
          _lines.addError(StateError('AI native engine exited'));
        }
      },
    );
    engine.state.addListener(_onState);
    _onState();
  }

  Future<native.Stockfish> _acquireShared() async {
    final existing = _shared;
    if (existing != null) {
      if (existing.state.value == native.StockfishState.ready) {
        return existing;
      }
      // Native side died; drop the reference and attempt a best-effort
      // rebuild (may fail validation, but the session surfaces that error).
      _shared = null;
    }
    final starting = _sharedStarting ??= _startShared();
    return starting;
  }

  Future<native.Stockfish> _startShared() async {
    try {
      final engine = _createEngine();
      final ready = Completer<native.Stockfish>();
      void onState() {
        final state = engine.state.value;
        if (state == native.StockfishState.ready && !ready.isCompleted) {
          ready.complete(engine);
        }
        if ((state == native.StockfishState.error ||
                state == native.StockfishState.disposed) &&
            !ready.isCompleted) {
          ready.completeError(StateError('AI native startup failed'));
        }
      }

      engine.state.addListener(onState);
      onState();
      try {
        final result = await ready.future.timeout(
          const Duration(seconds: 15),
        );
        _shared = result;
        return result;
      } finally {
        engine.state.removeListener(onState);
      }
    } finally {
      _sharedStarting = null;
    }
  }

  void _onState() {
    final engine = _engine;
    if (engine == null) return;
    final state = engine.state.value;
    if (state == native.StockfishState.error ||
        state == native.StockfishState.disposed) {
      if (identical(_shared, engine)) _shared = null;
      if (!_stopping && !_lines.isClosed) {
        _lines.addError(StateError('AI native engine exited: $state'));
      }
    }
  }

  @override
  void send(String line) {
    final engine = _engine;
    if (_stopping || engine == null) throw StateError('AI transport stopped');
    if (line.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Expected one UCI command');
    }
    engine.stdin = line;
  }

  @override
  Future<void> stop() => _stopFuture ??= _stop();

  Future<void> _stop() async {
    _stopping = true;
    try {
      // Let an in-flight launch settle so the interrupt below reaches the
      // engine this session actually attached to.
      await _launchFuture?.catchError((_) {});
      final engine = _engine;
      if (engine != null && engine.state.value == native.StockfishState.ready) {
        // Interrupt any running search; the engine itself stays resident for
        // the next session (see class comment).
        engine.stdin = 'stop';
      }
    } finally {
      _engine?.state.removeListener(_onState);
      await _stdout?.cancel();
      await _lines.close();
    }
  }
}
