import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app/telemetry/app_logger.dart';

/// Single-use, line-oriented transport. Errors and unexpected EOF are fatal.
/// stop must also cancel an in-progress launch.
abstract interface class StockfishTransport {
  Stream<String> get lines;
  Future<void> launch();
  void send(String line);
  Future<void> stop();
}

/// Desktop fallback. No shell, network download, or global working-dir changes.
class ProcessStockfishTransport implements StockfishTransport {
  ProcessStockfishTransport({
    this.executablePath,
    this.shutdownTimeout = const Duration(seconds: 2),
  });

  final String? executablePath;
  final Duration shutdownTimeout;
  final _lines = StreamController<String>();
  final _launchDone = Completer<void>();
  Process? _process;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;
  bool _launched = false;
  bool _exited = false;
  bool _stopping = false;
  Future<void>? _stopFuture;

  @override
  Stream<String> get lines => _lines.stream;

  static Future<String> locate() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError(
        'AI subprocess transport requires a desktop platform',
      );
    }
    const configured = String.fromEnvironment('STOCKFISH_EXECUTABLE');
    if (configured.isNotEmpty) return File(configured).absolute.path;
    final name = Platform.isWindows ? 'stockfish.exe' : 'stockfish';
    final sep = Platform.pathSeparator;
    final candidates = <String>[];
    var directory = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 6; i++) {
      candidates.add('${directory.path}${sep}engine_assets$sep$name');
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    candidates.add('${Directory.current.path}${sep}engine_assets$sep$name');
    for (final path in candidates) {
      if (await File(path).exists()) return File(path).absolute.path;
    }
    throw FileSystemException('AI executable not found in engine_assets', name);
  }

  @override
  Future<void> launch() async {
    if (_launched || _stopping) throw StateError('AI transport is single-use');
    _launched = true;
    try {
      final path = executablePath ?? await locate();
      if (_stopping) throw StateError('AI startup cancelled');
      final executable = File(path).absolute;
      final process = await Process.start(
        executable.path,
        const [],
        workingDirectory: executable.parent.path,
      );
      _process = process;
      _stdout = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _lines.add,
            onError: _lines.addError,
            onDone: () {
              if (!_stopping) _lines.close();
            },
          );
      _stderr = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.trim().isNotEmpty && !_stopping && !_lines.isClosed) {
              _lines.addError(StateError('AI stderr: $line'));
            }
          }, onError: _lines.addError);
      unawaited(
        process.exitCode.then((code) {
          _exited = true;
          if (!_stopping && !_lines.isClosed && code != 0) {
            _lines.addError(StateError('AI process exited with code $code'));
          }
        }),
      );
      unawaited(
        process.stdin.done.then<void>(
          (_) {},
          onError: (Object error) {
            if (!_stopping && !_lines.isClosed) {
              _lines.addError(error);
            } else {
              logW('engine', 'AI input closed during shutdown: $error');
            }
          },
        ),
      );
    } finally {
      _launchDone.complete();
    }
  }

  @override
  void send(String line) {
    if (_stopping || _exited || _process == null) {
      throw StateError('AI transport is not running');
    }
    if (line.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Expected one UCI command');
    }
    _process!.stdin.writeln(line);
  }

  @override
  Future<void> stop() => _stopFuture ??= _stop();

  Future<void> _stop() async {
    _stopping = true;
    if (_launched) await _launchDone.future;
    final process = _process;
    try {
      if (process != null) {
        if (!_exited) {
          process.stdin.writeln('stop');
          process.stdin.writeln('quit');
          try {
            await process.stdin.flush().timeout(shutdownTimeout);
          } catch (error) {
            logW('engine', 'AI graceful shutdown write failed: $error');
          }
          try {
            await process.exitCode.timeout(shutdownTimeout);
          } on TimeoutException {
            if (!process.kill(ProcessSignal.sigkill)) {
              // It may have exited between timeout and kill; still confirm exit.
              logW('engine', 'AI kill raced with process exit');
            }
            await process.exitCode.timeout(shutdownTimeout);
          }
        }
      }
    } finally {
      await _stdout?.cancel();
      await _stderr?.cancel();
      if (process != null) {
        try {
          await process.stdin.close();
        } catch (error) {
          logW('engine', 'AI input cleanup failed: $error');
        }
      }
      await _lines.close();
    }
  }
}
