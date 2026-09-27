/// GA4 Measurement Protocol telemetry, ported from pureweiqi's A1 client.
/// Events stay local until the first-launch privacy choice has been saved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';

// TODO: Maintainer: create a separate chess GA4 property and fill MEASUREMENT_ID.
const _measurementId = 'TODO_CHESS_MEASUREMENT_ID';
// TODO: Maintainer: fill API_SECRET from the new chess web data stream.
const _apiSecret = 'TODO_CHESS_API_SECRET';

class Analytics {
  static final Analytics instance = Analytics._();
  Analytics._() : _storageDirectory = null, _endpointOverride = null;

  @visibleForTesting
  Analytics.testing({required Directory directory, Uri? endpoint})
    : _storageDirectory = directory,
      _endpointOverride = endpoint;

  static const privacyAcceptedKey = 'privacyAccepted';
  static const enabledKey = 'analyticsEnabled';
  static const maxPendingEvents = 100;
  static const _flushDelay = Duration(seconds: 8);
  static const _requestTimeout = Duration(seconds: 15);

  // Explicit schemas keep PGN, FEN, moves, error text and paths off the wire.
  static const _eventParams = <String, Set<String>>{
    'app_open': {},
    'game_start': {'mode', 'difficulty', 'player_color'},
    'game_end': {'mode', 'difficulty', 'duration_ms', 'move_count'},
    'puzzle_result': {'correct', 'attempts', 'duration_ms', 'rating'},
    'celebrate_shown': {'source', 'result'},
    'daily_reminder_toggle': {'on'},
    'engine_start': {'duration_ms', 'success'},
    'backup_export': {'ok'},
    'backup_import': {'ok'},
    'app_error': {'error_kind'},
    'abnormal_exit': {'streak', 'dart_sentinel', 'native_sentinel'},
  };

  final Directory? _storageDirectory;
  final Uri? _endpointOverride;
  bool _enabled = true;
  bool _prepared = false;
  bool _consentGranted = false;
  bool _disposed = false;
  int _generation = 0;
  String _clientId = '';
  String _appVersion = '';
  String _sessionId = '';
  final List<Map<String, Object>> _queue = [];
  final List<Map<String, Object>> _inFlight = [];
  Timer? _flushTimer;
  HttpClient? _http;
  Future<void>? _activeFlush;
  File? _pendingFile;
  File? _phaseFile;

  /// Absolute sandbox path for future chess native-engine breadcrumbs.
  String? nativeBreadcrumbPath;

  bool get enabled => _enabled;
  bool get consentGranted => _consentGranted;
  bool get _configured =>
      _endpointOverride != null ||
      (!_measurementId.startsWith('TODO_') && !_apiSecret.startsWith('TODO_'));
  bool get _canSend =>
      _prepared && !_disposed && _enabled && _consentGranted && _configured;

  Uri get _endpoint =>
      _endpointOverride ??
      Uri.https('www.google-analytics.com', '/mp/collect', {
        'measurement_id': _measurementId,
        'api_secret': _apiSecret,
      });

  /// Local-only startup: replay the durable queue and inspect crash sentinels.
  Future<void> prepare(
    SharedPreferences prefs, {
    String appVersion = '',
  }) async {
    if (_prepared) return;
    if (_disposed) throw StateError('Analytics has been disposed');
    _enabled = prefs.getBool(enabledKey) ?? true;
    _appVersion = appVersion;
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final rng = Random.secure();
    _clientId = List.generate(
      4,
      (_) => rng.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
    ).join();

    try {
      final dir =
          _storageDirectory ??
          Directory(
            '${(await getApplicationDocumentsDirectory()).path}/telemetry',
          );
      await dir.create(recursive: true);
      _pendingFile = File('${dir.path}/pending_events.jsonl');
      _phaseFile = File('${dir.path}/phase.txt');
      nativeBreadcrumbPath = '${dir.path}/native_phase.txt';
    } catch (error) {
      logE('analytics', 'local storage unavailable: $error');
    }

    _prepared = true;
    if (_enabled) _replayPending();
    _persistQueue();
    await _detectAbnormalExit(prefs);
    event('app_open');
    if (!_configured) {
      logI('analytics', 'chess GA4 configuration pending; network disabled');
    }
  }

  Future<void> init(SharedPreferences prefs, {String appVersion = ''}) async {
    await prepare(prefs, appVersion: appVersion);
    _consentGranted = prefs.getBool(privacyAcceptedKey) == true;
    _scheduleFlush();
  }

  /// Save both choices before opening the network gate. Failure is fail-closed.
  Future<void> savePrivacyChoice(bool enabled, SharedPreferences prefs) async {
    _consentGranted = false;
    _stopSending();
    try {
      await setEnabled(enabled, prefs);
      if (!await prefs.setBool(privacyAcceptedKey, true)) {
        throw StateError('Could not save privacy choice');
      }
      _consentGranted = true;
      _scheduleFlush();
    } catch (error) {
      logE('privacy', 'could not save privacy choice: $error');
      // SharedPreferences changes its cache even when the platform write fails.
      try {
        if (!await prefs.remove(privacyAcceptedKey)) {
          throw StateError('Could not clear unsaved privacy choice');
        }
      } catch (rollbackError) {
        logE('privacy', 'could not clear privacy choice: $rollbackError');
      }
      rethrow;
    }
  }

  Future<void> setEnabled(bool value, SharedPreferences prefs) async {
    if (!value) {
      _enabled = false;
      _stopSending();
      _queue.clear();
      _inFlight.clear();
    }
    try {
      if (!await prefs.setBool(enabledKey, value)) {
        throw StateError('Could not save analytics preference');
      }
      _enabled = value;
    } catch (error) {
      logE('privacy', 'could not save statistics setting: $error');
      rethrow;
    } finally {
      if (!value) _persistQueue(failOnError: true);
    }
    _scheduleFlush();
  }

  void _stopSending() {
    _generation++;
    _flushTimer?.cancel();
    _flushTimer = null;
    _http?.close(force: true);
    _http = null;
    // Preserve unacknowledged events unless the caller is opting out.
    _queue.insertAll(0, _inFlight);
    _inFlight.clear();
  }

  Future<void> _detectAbnormalExit(SharedPreferences prefs) async {
    if (_phaseFile == null) return;
    try {
      final native = File(nativeBreadcrumbPath!);
      final dartPhase = _phaseFile!.existsSync()
          ? _phaseFile!.readAsStringSync().trim()
          : '';
      final nativePhase = native.existsSync()
          ? native.readAsStringSync().trim()
          : '';
      if (dartPhase.isEmpty && nativePhase.isEmpty) return;
      final streak = (prefs.getInt('crashStreak') ?? 0) + 1;
      if (!await prefs.setInt('crashStreak', streak)) {
        logW('crash', 'could not save crash streak');
      }
      logW(
        'crash',
        'abnormal exit: dart=$dartPhase native=$nativePhase streak=$streak',
      );
      event('abnormal_exit', {
        'streak': streak,
        'dart_sentinel': dartPhase.isNotEmpty,
        'native_sentinel': nativePhase.isNotEmpty,
      });
      _deleteSentinels();
    } catch (error) {
      logE('crash', 'could not inspect phase sentinel: $error');
    }
  }

  /// Synchronous, flushed write survives a native crash immediately afterward.
  void setPhase(String phase) {
    if (_phaseFile == null) {
      logW('crash', 'phase storage unavailable');
      return;
    }
    try {
      _phaseFile!.writeAsStringSync(phase, flush: true);
    } catch (error) {
      logE('crash', 'could not persist phase: $error');
    }
  }

  Future<void> clearPhase({SharedPreferences? prefs}) async {
    try {
      _deleteSentinels();
      if (prefs != null && !await prefs.setInt('crashStreak', 0)) {
        throw StateError('Could not reset crash streak');
      }
    } catch (error) {
      logE('crash', 'could not clear phase: $error');
    }
  }

  void _deleteSentinels() {
    if (_phaseFile?.existsSync() == true) _phaseFile!.deleteSync();
    final native = nativeBreadcrumbPath == null
        ? null
        : File(nativeBreadcrumbPath!);
    if (native?.existsSync() == true) native!.deleteSync();
  }

  void _replayPending() {
    try {
      if (_pendingFile?.existsSync() != true) return;
      for (final line in _pendingFile!.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        try {
          final value = jsonDecode(line);
          if (value is! Map ||
              value['name'] is! String ||
              value['params'] is! Map ||
              !_eventParams.containsKey(value['name'])) {
            throw const FormatException('Invalid chess telemetry event');
          }
          final name = value['name'] as String;
          _queue.add(_makeEvent(name, value['params'] as Map, deferred: true));
          if (_queue.length >= maxPendingEvents) break;
        } catch (error) {
          logW(
            'analytics',
            'skipping invalid pending event: ${error.runtimeType}',
          );
        }
      }
      logI('analytics', 'replaying ${_queue.length} chess events');
    } catch (error) {
      logE('analytics', 'could not replay local queue: $error');
    }
  }

  void _persistQueue({bool failOnError = false}) {
    try {
      if (_pendingFile == null) {
        throw StateError('Telemetry storage unavailable');
      }
      final contents = StringBuffer();
      for (final event in [..._inFlight, ..._queue]) {
        contents.writeln(jsonEncode(event));
      }
      // Never truncate the last committed queue before its replacement is durable.
      final temp = File('${_pendingFile!.path}.tmp');
      temp.writeAsStringSync(contents.toString(), flush: true);
      temp.renameSync(_pendingFile!.path);
    } catch (error) {
      logE('analytics', 'could not persist local queue: $error');
      if (failOnError) rethrow;
    }
  }

  Map<String, Object> _makeEvent(
    String name,
    Map params, {
    bool deferred = false,
  }) => {
    'name': name,
    'params': {
      'engagement_time_msec': 1,
      'session_id': _sessionId,
      'app_name': 'purechess',
      'app_version': _appVersion,
      'platform': Platform.operatingSystem,
      if (deferred) 'deferred': 1,
      ..._safeParams(name, params),
    },
  };

  static Map<String, Object> _safeParams(String name, Map params) {
    final cleaned = <String, Object>{};
    for (final key in _eventParams[name]!) {
      final value = params[key];
      if (value is String) {
        cleaned[key] = value.length <= 100 ? value : value.substring(0, 100);
      } else if (value is bool) {
        cleaned[key] = value ? 1 : 0;
      } else if (value is num) {
        if (value.isFinite) {
          cleaned[key] = value;
        } else {
          logW('analytics', 'non-finite measurement rejected: $name/$key');
        }
      }
    }
    return cleaned;
  }

  void event(String name, [Map<String, Object?> params = const {}]) {
    if (!_enabled || !_prepared || _disposed) return;
    if (!_eventParams.containsKey(name)) {
      logW('analytics', 'event rejected: unknown chess event schema');
      return;
    }
    if (_queue.length + _inFlight.length >= maxPendingEvents) {
      logW('analytics', 'pending queue full; dropping new event');
      _scheduleFlush();
      return;
    }
    _queue.add(_makeEvent(name, params));
    _persistQueue();
    if (_queue.length >= 20) {
      unawaited(flushNow());
    } else {
      _scheduleFlush();
    }
  }

  void _scheduleFlush() {
    if (_canSend && _queue.isNotEmpty) {
      _flushTimer ??= Timer(_flushDelay, () => unawaited(flushNow()));
    }
  }

  /// Best-effort flush. Unacknowledged events remain durable during the request.
  Future<void> flushNow() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_activeFlush != null) return _activeFlush!;
    if (!_canSend || _queue.isEmpty) return Future<void>.value();
    final future = _flush();
    _activeFlush = future;
    return future;
  }

  Future<void> _flush() async {
    final generation = _generation;
    final batch = _queue.take(25).toList();
    _queue.removeRange(0, batch.length);
    _inFlight.addAll(batch);
    var failed = false;
    var expired = false;
    HttpClientRequest? request;
    final client = _http ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      await (() async {
        request = await client.postUrl(_endpoint);
        if (expired || !_canSend || generation != _generation) {
          request!.abort();
          return;
        }
        request!.headers.contentType = ContentType.json;
        request!.write(jsonEncode({'client_id': _clientId, 'events': batch}));
        final response = await request!.close();
        await response.drain<void>();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('analytics HTTP ${response.statusCode}');
        }
      })().timeout(_requestTimeout);
      if (generation == _generation) {
        _inFlight.clear();
        _persistQueue();
      }
    } catch (error) {
      failed = true;
      expired = true;
      request?.abort();
      client.close(force: true);
      if (identical(_http, client)) _http = null;
      if (generation == _generation) {
        _inFlight.clear();
        _queue.insertAll(0, batch);
        _persistQueue();
        // Do not log URLs: the MP query contains the API secret.
        logW(
          'analytics',
          'flush failed (${error.runtimeType}); queue retained',
        );
      }
    } finally {
      _activeFlush = null;
      // A bounded delay prevents a network failure from becoming a hot loop.
      if (!failed || generation != _generation) _scheduleFlush();
    }
  }

  void dispose() {
    _stopSending();
    _consentGranted = false;
    _disposed = true;
    _prepared = false;
  }
}
