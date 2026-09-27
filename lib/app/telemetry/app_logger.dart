/// Local diagnostic ring buffer and rolling log, ported from pureweiqi.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  @visibleForTesting
  AppLogger.testing();

  static const _ringCapacity = 400;
  static const _maxFileBytes = 512 * 1024;
  final ListQueue<String> _ring = ListQueue(_ringCapacity);
  final List<String> _pendingLines = [];
  IOSink? _sink;
  Future<void>? _activeFlush;
  File? _file;
  int _fileBytes = 0;

  Future<void> init({Directory? directory}) async {
    if (_sink != null) return;
    try {
      final dir =
          directory ??
          Directory('${(await getApplicationDocumentsDirectory()).path}/logs');
      await dir.create(recursive: true);
      final file = File('${dir.path}/app.log');
      if (await file.exists() && await file.length() > _maxFileBytes) {
        final old = File('${dir.path}/app.1.log');
        if (await old.exists()) await old.delete();
        await file.rename(old.path);
      }
      _file = File('${dir.path}/app.log');
      _fileBytes = await _file!.exists() ? await _file!.length() : 0;
      final sink = _file!.openWrite(mode: FileMode.append);
      _sink = sink;
      // IOSink file errors arrive asynchronously, not at writeln().
      sink.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_sink, sink)) _sink = null;
          debugPrint('logger: file output failed: $error');
        },
      );
      log(LogLevel.info, 'logger', 'session start');
    } catch (error) {
      debugPrint('logger: local file unavailable: $error');
    }
  }

  void log(LogLevel level, String tag, String message) {
    final line =
        '${DateTime.now().toIso8601String()} '
        '${level.name.toUpperCase().padRight(5)} [$tag] $message';
    if (_ring.length >= _ringCapacity) _ring.removeFirst();
    _ring.addLast(line);
    debugPrint(line);
    try {
      if (_sink != null && _fileBytes < _maxFileBytes * 2) {
        // IOSink rejects writes while its flush future is pending.
        if (_activeFlush != null) {
          _pendingLines.add(line);
        } else {
          _sink!.writeln(line);
        }
        _fileBytes += utf8.encode(line).length + 1;
      }
    } catch (error) {
      debugPrint('logger: could not append log: $error');
    }
  }

  List<String> get recent => _ring.toList();
  String? get filePath => _file?.path;

  Future<void> flush() {
    if (_activeFlush != null) return _activeFlush!;
    final sink = _sink;
    if (sink == null) return Future<void>.value();
    final future = _flush(sink);
    _activeFlush = future;
    return future;
  }

  Future<void> _flush(IOSink sink) async {
    try {
      while (true) {
        await sink.flush();
        if (_pendingLines.isEmpty) break;
        for (final line in _pendingLines) {
          sink.writeln(line);
        }
        _pendingLines.clear();
      }
    } catch (error) {
      debugPrint('logger: could not flush log: $error');
    } finally {
      _pendingLines.clear();
      _activeFlush = null;
    }
  }

  Future<void> dispose() async {
    await flush();
    final sink = _sink;
    _sink = null;
    try {
      await sink?.close();
    } catch (error) {
      debugPrint('logger: could not close log: $error');
    }
  }
}

void logD(String tag, String message) =>
    AppLogger.instance.log(LogLevel.debug, tag, message);
void logI(String tag, String message) =>
    AppLogger.instance.log(LogLevel.info, tag, message);
void logW(String tag, String message) =>
    AppLogger.instance.log(LogLevel.warn, tag, message);
void logE(String tag, String message) =>
    AppLogger.instance.log(LogLevel.error, tag, message);
