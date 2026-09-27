import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../support/preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalHttpOverrides = HttpOverrides.current;

  late Directory dir;
  late SharedPreferences prefs;
  late HttpServer server;
  late List<Analytics> clients;
  late List<Map<String, dynamic>> requests;
  Future<void> Function(HttpRequest)? respond;

  Analytics createClient({bool configured = true}) {
    final client = Analytics.testing(
      directory: dir,
      endpoint: configured
          ? Uri.parse('http://127.0.0.1:${server.port}/mp/collect')
          : null,
    );
    clients.add(client);
    return client;
  }

  File pendingFile() => File('${dir.path}/pending_events.jsonl');
  List<Map<String, dynamic>> pending() => pendingFile()
      .readAsLinesSync()
      .where((line) => line.isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();

  setUp(() async {
    // These tests use only an ephemeral loopback server, not Flutter's HTTP 400 stub.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('purechess_telemetry_test_');
    clients = [];
    requests = [];
    respond = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add(jsonDecode(body) as Map<String, dynamic>);
      if (respond != null) {
        await respond!(request);
      } else {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }
    });
  });

  tearDown(() async {
    for (final client in clients) {
      client.dispose();
    }
    await server.close(force: true);
    await dir.delete(recursive: true);
    HttpOverrides.global = originalHttpOverrides;
  });

  test('queue round trip replays only safe chess parameters', () async {
    final first = createClient();
    await first.prepare(prefs, appVersion: '1.2.3+4');
    first.event('game_start', {
      'mode': 'ai',
      'difficulty': 3,
      'fen': 'private position',
      'pgn': 'private game',
    });
    final disk = pending();
    expect(disk.map((e) => e['name']), ['app_open', 'game_start']);
    expect(pendingFile().readAsStringSync(), isNot(contains('private')));
    expect(File('${pendingFile().path}.tmp').existsSync(), isFalse);
    first.dispose();

    final second = createClient();
    await second.init(prefs, appVersion: '1.2.4+5');
    expect(pending().length, 3);
    expect(pending()[1]['params']['deferred'], 1);
    await second.savePrivacyChoice(true, prefs);
    await second.flushNow();
    expect(requests, hasLength(1));
    final events = requests.single['events'] as List;
    expect(events[1]['name'], 'game_start');
    expect(events[1]['params']['app_name'], 'purechess');
    expect(events[1]['params']['difficulty'], 3);
    expect(events[1]['params']['app_version'], '1.2.4+5');
    expect(pending(), isEmpty);
  });

  test('consent gate blocks manual and threshold sending', () async {
    final client = createClient();
    await client.init(prefs);
    for (var i = 0; i < 25; i++) {
      client.event('puzzle_result', {'correct': true, 'attempts': 1});
    }
    await client.flushNow();
    expect(client.consentGranted, isFalse);
    expect(requests, isEmpty);
    expect(pending(), hasLength(26));
    await client.savePrivacyChoice(true, prefs);
    await client.flushNow();
    expect(requests.single['events'], hasLength(25));
    await client.flushNow();
    expect(requests.last['events'], hasLength(1));
    expect(pending(), isEmpty);
  });

  test(
    'backup events retain only outcome and never archive contents',
    () async {
      final client = createClient();
      await client.prepare(prefs);
      client.event('backup_export', {'ok': true, 'pgn': 'private game'});
      client.event('backup_import', {'ok': false, 'path': 'private path'});
      final events = pending();
      expect(events[1]['name'], 'backup_export');
      expect(events[1]['params']['ok'], 1);
      expect(events[2]['name'], 'backup_import');
      expect(events[2]['params']['ok'], 0);
      expect(pendingFile().readAsStringSync(), isNot(contains('private')));
    },
  );

  test('placeholder GA configuration never contacts the network', () async {
    final client = createClient(configured: false);
    await client.init(prefs);
    await client.savePrivacyChoice(true, prefs);
    await client.flushNow();
    expect(client.consentGranted, isTrue);
    expect(requests, isEmpty);
    expect(pending(), hasLength(1));
  });

  test(
    'flush timer is created only after consent and cancelled on opt-out',
    () async {
      final timers = <Timer>[];
      final client = createClient();
      await runZoned(
        () async {
          await client.init(prefs);
          client.event('game_start');
          expect(timers, isEmpty);
          await client.savePrivacyChoice(true, prefs);
          expect(timers, hasLength(1));
          expect(timers.single.isActive, isTrue);
          await client.setEnabled(false, prefs);
          expect(timers.single.isActive, isFalse);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            if (duration == const Duration(seconds: 8)) timers.add(timer);
            return timer;
          },
        ),
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'declining clears disk and blocks future events across restart',
    () async {
      final first = createClient();
      await first.init(prefs);
      await first.savePrivacyChoice(false, prefs);
      first.event('engine_start');
      await first.flushNow();
      expect(pending(), isEmpty);
      expect(requests, isEmpty);
      expect(prefs.getBool(Analytics.enabledKey), isFalse);
      expect(prefs.getBool(Analytics.privacyAcceptedKey), isTrue);
      first.dispose();

      final second = createClient();
      await second.init(prefs);
      expect(second.enabled, isFalse);
      expect(pending(), isEmpty);
      await second.setEnabled(true, prefs);
      second.event('game_start', {'mode': 'local'});
      await second.flushNow();
      expect(requests.single['events'], hasLength(1));
    },
  );

  test(
    'turning statistics on alone does not grant first-launch consent',
    () async {
      final client = createClient();
      await client.init(prefs);
      await client.setEnabled(false, prefs);
      await client.setEnabled(true, prefs);
      client.event('game_start');
      await client.flushNow();
      expect(requests, isEmpty);
      expect(client.consentGranted, isFalse);
    },
  );

  test(
    'failed consent persistence keeps gate closed and clears cached choice',
    () async {
      final store = FailingPreferencesStore()
        ..failKey = 'flutter.${Analytics.privacyAcceptedKey}';
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      prefs = await SharedPreferences.getInstance();
      final client = createClient();
      await client.init(prefs);
      await expectLater(
        client.savePrivacyChoice(true, prefs),
        throwsStateError,
      );
      expect(client.consentGranted, isFalse);
      expect(prefs.getBool(Analytics.privacyAcceptedKey), isNull);
      await client.flushNow();
      expect(requests, isEmpty);
      store.failKey = null;
      await client.savePrivacyChoice(true, prefs);
      await client.flushNow();
      expect(requests, hasLength(1));
    },
  );

  test('failed opt-in preference does not enable sending', () async {
    final store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    prefs = await SharedPreferences.getInstance();
    final client = createClient();
    await client.init(prefs);
    await client.savePrivacyChoice(false, prefs);
    store.failKey = 'flutter.${Analytics.enabledKey}';
    await expectLater(client.setEnabled(true, prefs), throwsStateError);
    expect(client.enabled, isFalse);
    client.event('game_start');
    await client.flushNow();
    expect(requests, isEmpty);
  });

  test('failed HTTP response keeps queue durable for retry', () async {
    respond = (request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    };
    final client = createClient();
    await client.init(prefs);
    await client.savePrivacyChoice(true, prefs);
    await client.flushNow();
    expect(pending(), hasLength(1));
    respond = null;
    await client.flushNow();
    expect(requests, hasLength(2));
    expect(pending(), isEmpty);
  });

  test('in-flight batch stays on disk alongside newly queued events', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    respond = (request) async {
      received.complete();
      await release.future;
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    };
    final client = createClient();
    await client.init(prefs);
    await client.savePrivacyChoice(true, prefs);
    final flush = client.flushNow();
    await received.future;
    expect(identical(client.flushNow(), flush), isTrue);
    client.event('engine_start', {'success': true});
    expect(pending().map((e) => e['name']), ['app_open', 'engine_start']);
    release.complete();
    await flush;
    expect(pending().single['name'], 'engine_start');
  });

  test(
    'opting out aborts in-flight send without resurrecting backlog',
    () async {
      final received = Completer<void>();
      final release = Completer<void>();
      final responded = Completer<void>();
      respond = (request) async {
        received.complete();
        await release.future;
        await request.response.close();
        responded.complete();
      };
      final client = createClient();
      await client.init(prefs);
      await client.savePrivacyChoice(true, prefs);
      final flush = client.flushNow();
      await received.future;
      await client.setEnabled(false, prefs);
      release.complete();
      await flush;
      await responded.future;
      expect(pending(), isEmpty);
      expect(client.enabled, isFalse);
      await client.setEnabled(true, prefs);
      client.event('engine_start');
      respond = null;
      await client.flushNow();
      expect(requests.last['events'].single['name'], 'engine_start');
    },
  );

  test('Dart and native sentinels replay once without phase details', () async {
    final first = createClient();
    await first.init(prefs);
    first.setPhase('chess_engine_start /private/position.fen');
    File(first.nativeBreadcrumbPath!).writeAsStringSync('uci_go private PGN');
    first.dispose();
    final second = createClient();
    await second.init(prefs);
    final crash = pending().singleWhere((e) => e['name'] == 'abnormal_exit');
    expect(crash['params']['streak'], 1);
    expect(crash['params']['dart_sentinel'], 1);
    expect(crash['params']['native_sentinel'], 1);
    expect(pendingFile().readAsStringSync(), isNot(contains('private')));
    expect(File('${dir.path}/phase.txt').existsSync(), isFalse);
    expect(File(second.nativeBreadcrumbPath!).existsSync(), isFalse);
    second.setPhase('chess_engine_start');
    await second.clearPhase(prefs: prefs);
    expect(prefs.getInt('crashStreak'), 0);
    expect(File('${dir.path}/phase.txt').existsSync(), isFalse);
  });

  test(
    'malformed rows and stale temp file do not hide committed events',
    () async {
      pendingFile().writeAsStringSync(
        'not-json\n'
        '{"name":"game_start","params":{"difficulty":2,"pgn":"private"}}\n'
        '{"name":"weiqi_event","params":{}}\n'
        '{"broken":true}\n',
      );
      File('${pendingFile().path}.tmp')
          .writeAsStringSync('partial new snapshot');
      final client = createClient();
      await client.prepare(prefs);
      expect(pending().map((e) => e['name']), ['game_start', 'app_open']);
      expect(pending().first['params']['difficulty'], 2);
      expect(pendingFile().readAsStringSync(), isNot(contains('private')));
    },
  );

  test('bounded backlog and schemas reject unsupported data', () async {
    final client = createClient();
    await client.prepare(prefs);
    client.event('unknown_event');
    client.event('app_error', {
      'error_kind': 'flutter_error',
      'error_message': 'private',
      'stack_head': 'private',
    });
    client.event('game_end', {
      'result': 'private',
      'pgn': 'private',
      'fen': 'private',
      'moves': ['e2e4'],
      'duration_ms': double.nan,
    });
    expect(pending().last['params'].containsKey('duration_ms'), isFalse);
    for (var i = 0; i < Analytics.maxPendingEvents + 5; i++) {
      client.event('game_start');
    }
    expect(pending(), hasLength(Analytics.maxPendingEvents));
    expect(pendingFile().readAsStringSync(), isNot(contains('private')));
    expect(pendingFile().readAsStringSync(), isNot(contains('unknown_event')));
  });

  test('each launch uses a new non-persistent client ID', () async {
    final first = createClient();
    await first.init(prefs);
    await first.savePrivacyChoice(true, prefs);
    await first.flushNow();
    first.dispose();
    final second = createClient();
    await second.init(prefs);
    await second.flushNow();
    expect(requests[0]['client_id'], isNot(requests[1]['client_id']));
    expect(prefs.containsKey('analyticsClientId'), isFalse);
  });

  test('opt-out clears a pre-existing durable queue on startup', () async {
    pendingFile().writeAsStringSync('{"name":"game_start","params":{}}\n');
    await prefs.setBool(Analytics.enabledKey, false);
    await prefs.setBool(Analytics.privacyAcceptedKey, true);
    final client = createClient();
    await client.init(prefs);
    await client.flushNow();
    expect(pending(), isEmpty);
    expect(requests, isEmpty);
  });

  test('failed queue deletion still saves opt-out and blocks sends', () async {
    final client = createClient();
    await client.init(prefs);
    // A directory at the temporary-file path forces a real filesystem error.
    Directory('${pendingFile().path}.tmp').createSync();
    await expectLater(
      client.setEnabled(false, prefs),
      throwsA(isA<FileSystemException>()),
    );
    expect(client.enabled, isFalse);
    expect(prefs.getBool(Analytics.enabledKey), isFalse);
    await client.flushNow();
    expect(requests, isEmpty);
  });
}
