import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/telemetry/analytics.dart';
import '../app/telemetry/app_logger.dart';
import '../core/board.dart';
import '../core/move.dart';
import 'mobile_stockfish_transport.dart';
import 'stockfish_transport.dart';
import 'uci_protocol.dart';

enum StockfishState {
  stopped,
  starting,
  ready,
  analyzing,
  stopping,
  failed,
  disposed,
}

class StockfishException implements Exception {
  const StockfishException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

class StockfishStatus {
  const StockfishStatus(this.state, {this.error});
  final StockfishState state;
  final StockfishException? error;
}

class StockfishDifficulty {
  const StockfishDifficulty(
    this.level,
    this.movetimeMs, {
    this.skill = 20,
    this.elo,
  });
  final int level;
  final int movetimeMs;
  final int skill;
  final int? elo;

  List<String> get commands => [
    UciCommand.setOption('UCI_LimitStrength', elo != null),
    UciCommand.setOption('Skill Level', skill),
    if (elo != null) UciCommand.setOption('UCI_Elo', elo!),
  ];
}

const stockfishDifficulties = [
  StockfishDifficulty(1, 100, skill: 0),
  StockfishDifficulty(2, 150, skill: 2),
  StockfishDifficulty(3, 250, skill: 4),
  StockfishDifficulty(4, 400, skill: 6),
  StockfishDifficulty(5, 600, skill: 8),
  StockfishDifficulty(6, 800, elo: 1600),
  StockfishDifficulty(7, 1000, elo: 1900),
  StockfishDifficulty(8, 1200, elo: 2200),
  StockfishDifficulty(9, 1600, elo: 2500),
  StockfishDifficulty(10, 2000, elo: 2800),
];

class PositionAnalysis {
  PositionAnalysis({
    required this.score,
    required this.bestMove,
    required List<String> bestLine,
    required this.depth,
  }) : bestLine = List.unmodifiable(bestLine);

  /// Side-to-move perspective; mate is signed moves to mate (not centipawns).
  final UciScore score;
  final String? bestMove;

  /// Strongest principal variation. At reduced strength bestMove may differ.
  final List<String> bestLine;
  final int? depth;
  int? get cp => score.cp;
  int? get mate => score.mate;
}

/// One owner per app. Operations fail explicitly; searches are never overlapped.
/// UI observes status and displays error.message, not the local diagnostic cause.
class StockfishService {
  StockfishService({
    StockfishTransport Function()? transportFactory,
    Analytics? analytics,
    this.prefs,
    this.handshakeTimeout = const Duration(seconds: 20),
    this.analysisTimeout = const Duration(seconds: 30),
  }) : _transportFactory = transportFactory ?? _defaultTransport,
       _analytics = analytics ?? Analytics.instance;

  final StockfishTransport Function() _transportFactory;
  final Analytics _analytics;
  final SharedPreferences? prefs;
  final Duration handshakeTimeout;
  final Duration analysisTimeout;
  final _status = ValueNotifier(const StockfishStatus(StockfishState.stopped));
  ValueListenable<StockfishStatus> get status => _status;
  StockfishState get state => _status.value.state;
  StockfishException? get lastError => _status.value.error;
  StockfishTransport? _transport;
  StreamSubscription<String>? _subscription;
  Future<void>? _starting;
  Future<void>? _stopping;
  Future<void>? _releasing;
  Future<void>? _disposing;
  Future<PositionAnalysis>? _analysis;
  bool _restartBlocked = false;
  Completer<UciMessage>? _pending;
  bool Function(UciMessage)? _accept;
  UciInfo? _principal;
  final Map<String, UciOption> _options = {};
  int _generation = 0;
  String? engineName;

  static StockfishTransport _defaultTransport() =>
      Platform.isAndroid || Platform.isIOS
      ? MobileStockfishTransport()
      : ProcessStockfishTransport();

  void _setState(StockfishState value, {StockfishException? error}) {
    _status.value = StockfishStatus(value, error: error);
  }

  StockfishException _error(String message, [Object? cause]) {
    final error = cause is StockfishException
        ? cause
        : StockfishException(message, cause: cause);
    logE('engine', '$message${cause == null ? '' : ': $cause'}');
    return error;
  }

  void _fail(StockfishException error) {
    if (state == StockfishState.stopping || state == StockfishState.disposed) {
      return;
    }
    _setState(StockfishState.failed, error: error);
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
    if (_starting == null && _analysis == null) {
      unawaited(_releaseAfterFailure());
    }
  }

  Future<void> ensureStarted() {
    if (_restartBlocked) {
      return Future.error(_error('AI 无法安全重启，请重新打开应用'));
    }
    if (_disposing != null || state == StockfishState.disposed) {
      return Future.error(_error('AI 已关闭'));
    }
    if (_stopping != null) return Future.error(_error('AI 正在停止，请稍后重试'));
    if (_starting != null) return _starting!;
    if (state == StockfishState.ready || state == StockfishState.analyzing) {
      return Future.value();
    }
    final generation = ++_generation;
    _setState(StockfishState.starting);
    return _starting = _start(generation);
  }

  Future<void> _start(int generation) async {
    final watch = Stopwatch()..start();
    var success = false;
    _analytics.setPhase('chess_engine_start');
    try {
      await _release();
      _checkGeneration(generation);
      _options.clear();
      engineName = null;
      final transport = _transportFactory();
      _transport = transport;
      _subscription = transport.lines.listen(
        _onLine,
        onError: (Object error) => _fail(_error('AI 运行失败，请重试', error)),
        onDone: () => _fail(_error('AI 意外退出，请重试')),
      );
      await transport.launch().timeout(handshakeTimeout);
      _checkGeneration(generation);
      await _exchange(UciCommand.uci, (m) => m is UciOk, handshakeTimeout);
      _validateOptions();
      transport.send(UciCommand.setOption('Threads', 1));
      transport.send(UciCommand.setOption('Hash', 16));
      transport.send(UciCommand.setOption('MultiPV', 1));
      await _exchange(
        UciCommand.isReady,
        (m) => m is UciReady,
        handshakeTimeout,
      );
      _checkGeneration(generation);
      _setState(StockfishState.ready);
      success = true;
    } catch (cause) {
      final error = _error('AI 启动失败，请重试', cause);
      if (generation == _generation) _fail(error);
      await _releaseAfterFailure();
      throw error;
    } finally {
      await _analytics.clearPhase(prefs: success ? prefs : null);
      _analytics.event('engine_start', {
        'duration_ms': watch.elapsedMilliseconds,
        'success': success,
      });
      _starting = null;
    }
  }

  void _checkGeneration(int generation) {
    if (generation != _generation) throw const StockfishException('AI 操作已取消');
    if (state == StockfishState.failed) throw lastError!;
  }

  void _validateOptions() {
    void spin(String name, int low, int high) {
      final option = _options[name];
      if (option == null ||
          option.type != 'spin' ||
          option.min == null ||
          option.max == null ||
          option.min! > low ||
          option.max! < high) {
        throw StateError('Required UCI range unavailable: $name $low..$high');
      }
    }

    spin('Skill Level', 0, 20);
    spin('UCI_Elo', 1600, 2800);
    spin('Threads', 1, 1);
    spin('Hash', 16, 16);
    spin('MultiPV', 1, 1);
    if (_options['UCI_LimitStrength']?.type != 'check') {
      throw StateError('Required UCI_LimitStrength unavailable');
    }
  }

  void _onLine(String line) {
    try {
      final message = parseUciLine(line);
      if (message is UciInfo && message.text?.startsWith('ERROR') == true) {
        throw StateError(message.text!);
      }
      if (message is UciOption && state == StockfishState.starting) {
        _options[message.name] = message;
      }
      if (message is UciId && message.field == 'name') {
        engineName = message.value;
      }
      if (message is UciInfo &&
          state == StockfishState.analyzing &&
          message.multiPv == 1 &&
          message.score != null &&
          message.score!.bound == UciScoreBound.exact &&
          (message.pv.isNotEmpty || message.score!.mate == 0)) {
        _principal = message;
      }
      final pending = _pending;
      if (pending != null && !pending.isCompleted && _accept!(message)) {
        pending.complete(message);
      }
    } catch (error) {
      _fail(_error('AI 返回了无效结果，请重试', error));
    }
  }

  Future<UciMessage> _exchange(
    String command,
    bool Function(UciMessage) accept,
    Duration timeout,
  ) async {
    final pending = Completer<UciMessage>();
    _pending = pending;
    _accept = accept;
    final response = pending.future.timeout(timeout);
    try {
      try {
        if (state == StockfishState.failed) throw lastError!;
        _transport!.send(command);
      } catch (error, stack) {
        if (!pending.isCompleted) pending.completeError(error, stack);
      }
      return await response;
    } finally {
      _pending = null;
      _accept = null;
    }
  }

  /// depth overrides the level's movetime; timeout still bounds the search.
  Future<PositionAnalysis> analyzePosition(
    String fen, {
    int difficulty = 5,
    int? depth,
  }) async {
    if (_analysis != null) throw _error('AI 正忙，请稍后重试');
    try {
      return await (_analysis = _analyzePosition(fen, difficulty, depth));
    } finally {
      _analysis = null;
    }
  }

  Future<PositionAnalysis> _analyzePosition(
    String fen,
    int difficulty,
    int? depth,
  ) async {
    late Board board;
    late String go;
    try {
      if (difficulty < 1 || difficulty > 10) {
        throw RangeError.range(difficulty, 1, 10, 'difficulty');
      }
      board = Board.fromFen(fen);
      // A king left attacked by its own previous move is illegal and can crash
      // native Stockfish. Core FEN parsing deliberately only checks structure.
      final previousKing = board.position.squares.indexOf(-6 * board.turn.sign);
      if (board.isAttacked(previousKing, board.turn)) {
        throw const FormatException('Side not to move is in check');
      }
      final position = board.position;
      for (final color in Color.values) {
        final pieces = position.squares.where((p) => p * color.sign > 0);
        if (pieces.length > 16 ||
            pieces.where((p) => p.abs() == 1).length > 8) {
          throw const FormatException('Impossible piece count');
        }
      }
      for (final right in [
        (1, 4, 7, 1),
        (2, 4, 0, 1),
        (4, 116, 119, -1),
        (8, 116, 112, -1),
      ]) {
        if ((position.castlingRights & right.$1) != 0 &&
            (position.squares[right.$2] != 6 * right.$4 ||
                position.squares[right.$3] != 4 * right.$4)) {
          throw const FormatException('Castling right without king and rook');
        }
      }
      final ep = position.enPassant;
      if (ep != null &&
          (position.squares[ep - 16 * board.turn.sign] != -board.turn.sign ||
              position.squares[ep + 16 * board.turn.sign] != 0)) {
        throw const FormatException('En passant without a double pawn push');
      }
      go = depth == null
          ? UciCommand.go(
              movetime: stockfishDifficulties[difficulty - 1].movetimeMs,
            )
          : UciCommand.go(depth: depth);
    } catch (cause) {
      throw _error('局面或 AI 难度无效，请检查后重试', cause);
    }
    await ensureStarted();
    if (state != StockfishState.ready) throw _error('AI 正忙，请稍后重试');
    final generation = _generation;
    _setState(StockfishState.analyzing);
    _principal = null;
    _analytics.setPhase('chess_engine_analyze');
    try {
      final transport = _transport!;
      transport.send(UciCommand.newGame);
      for (final command in stockfishDifficulties[difficulty - 1].commands) {
        transport.send(command);
      }
      await _exchange(
        UciCommand.isReady,
        (m) => m is UciReady,
        handshakeTimeout,
      );
      transport.send(UciCommand.position(board.toFen()));
      final message = await _exchange(
        go,
        (m) => m is UciBestMove,
        analysisTimeout,
      );
      _checkGeneration(generation);
      final best = message as UciBestMove;
      final legal = board.legalMoves();
      if (best.move == null) {
        if (legal.isNotEmpty) throw StateError('Missing legal bestmove');
        final result = PositionAnalysis(
          score: board.inCheck
              ? const UciScore(UciScoreKind.mate, 0)
              : const UciScore(UciScoreKind.cp, 0),
          bestMove: null,
          bestLine: [],
          depth: _principal?.depth,
        );
        _setState(StockfishState.ready);
        return result;
      }
      if (!legal.contains(Move.fromUci(best.move!))) {
        throw StateError('Illegal bestmove');
      }
      final principal = _principal;
      if (principal == null || principal.pv.isEmpty) {
        throw StateError('Missing scored principal variation');
      }
      for (final move in principal.pv) {
        board.play(Move.fromUci(move));
      }
      final result = PositionAnalysis(
        score: principal.score!,
        bestMove: best.move,
        bestLine: principal.pv,
        depth: principal.depth,
      );
      _setState(StockfishState.ready);
      return result;
    } catch (cause) {
      final error = _error('AI 分析失败，请重试', cause);
      if (generation == _generation) _fail(error);
      // A timed-out search must not leak its late bestmove into the next one.
      await _releaseAfterFailure();
      throw error;
    } finally {
      await _analytics.clearPhase();
    }
  }

  Future<void> _release() {
    if (_releasing != null) return _releasing!;
    final transport = _transport;
    final subscription = _subscription;
    _transport = null;
    _subscription = null;
    if (transport == null) return Future.value();
    return _releasing = () async {
      try {
        await subscription?.cancel();
        await transport.stop();
      } finally {
        _releasing = null;
      }
    }();
  }

  Future<void> _releaseAfterFailure() async {
    try {
      await _release();
    } catch (cause) {
      _restartBlocked = true;
      final error = _error('AI 无法安全停止，请重新打开应用', cause);
      if (state != StockfishState.disposed) {
        _setState(StockfishState.failed, error: error);
      }
    }
  }

  Future<void> stop() {
    if (_stopping != null) return _stopping!;
    if (state == StockfishState.disposed) return Future.value();
    return _stopping = _stop();
  }

  Future<void> _stop() async {
    ++_generation;
    _setState(StockfishState.stopping);
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const StockfishException('AI 操作已取消'));
    }
    try {
      await _release();
      final analysis = _analysis;
      if (analysis != null) {
        try {
          await analysis;
        } on StockfishException catch (error) {
          logI('engine', 'Analysis cancelled: $error');
        }
      }
      final starting = _starting;
      if (starting != null) {
        try {
          await starting;
        } on StockfishException catch (error) {
          logI('engine', 'Startup cancelled: $error');
        }
      }
      _setState(StockfishState.stopped);
    } catch (cause) {
      _restartBlocked = true;
      final error = _error('AI 停止失败，请重新打开应用', cause);
      _setState(StockfishState.failed, error: error);
      throw error;
    } finally {
      await _analytics.clearPhase();
      _stopping = null;
    }
  }

  Future<void> dispose() => _disposing ??= () async {
    try {
      await stop();
    } finally {
      _setState(StockfishState.disposed);
      _status.dispose();
    }
  }();
}
