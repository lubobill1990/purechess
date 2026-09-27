import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/notifications.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../support/fake_reminder_backend.dart';
import '../support/preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  const enabled = DailyReminderSettings(enabled: true);
  late SharedPreferences prefs;
  late FakeReminderBackend backend;
  late DailyReminderService service;
  late FailingPreferencesStore store;
  late Analytics analytics;
  late Directory directory;

  setUp(() async {
    store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('chess_reminders_');
    analytics = Analytics.testing(directory: directory);
    await analytics.init(prefs);
    backend = FakeReminderBackend();
    service = DailyReminderService(
      prefs,
      backend: backend,
      analytics: analytics,
      now: () => DateTime.utc(2026, 9, 28, 12),
    );
  });

  tearDown(() async {
    service.dispose();
    analytics.dispose();
    await directory.delete(recursive: true);
  });

  test('defaults opt out at 20:00 and round-trip strict settings', () {
    final defaults = service.settings;
    expect(defaults.enabled, isFalse);
    expect(defaults.hour, 20);
    expect(defaults.minute, 0);
    expect(DailyReminderSettings.decode(enabled.encode()).enabled, isTrue);
    expect(nextDailyReminder(tz.TZDateTime.now(tz.UTC), defaults), isNull);
    for (final invalid in [
      'null',
      '[]',
      '{}',
      '{"enabled":1,"hour":20,"minute":0}',
      '{"enabled":true,"hour":24,"minute":0}',
      '{"enabled":true,"hour":20,"minute":-1}',
    ]) {
      expect(
        () => DailyReminderSettings.decode(invalid),
        throwsFormatException,
      );
    }
  });

  test('before, at, after time and calendar rollovers', () {
    for (final sample in [
      (
        tz.TZDateTime.utc(2026, 9, 28, 19, 59),
        tz.TZDateTime.utc(2026, 9, 28, 20),
      ),
      (tz.TZDateTime.utc(2026, 9, 28, 20), tz.TZDateTime.utc(2026, 9, 29, 20)),
      (tz.TZDateTime.utc(2026, 12, 31, 21), tz.TZDateTime.utc(2027, 1, 1, 20)),
      (tz.TZDateTime.utc(2028, 2, 28, 21), tz.TZDateTime.utc(2028, 2, 29, 20)),
    ]) {
      expect(nextDailyReminder(sample.$1, enabled), sample.$2);
    }
    expect(
      nextDailyReminder(
        tz.TZDateTime.utc(2026, 9, 28, 23, 59),
        const DailyReminderSettings(enabled: true, hour: 0),
      ),
      tz.TZDateTime.utc(2026, 9, 29),
    );
  });

  test('DST preserves 20:00 across 23-hour and 25-hour days', () {
    final zone = tz.getLocation('America/New_York');
    for (final sample in [(3, 7, 23), (10, 31, 25)]) {
      final now = tz.TZDateTime(zone, 2026, sample.$1, sample.$2, 20);
      final next = nextDailyReminder(now, enabled)!;
      expect(next.hour, 20);
      expect(next.difference(now).inHours, sample.$3);
    }
  });

  test(
    'startup never requests permission; off cancels only feature reminder',
    () async {
      expect(await service.refresh(), isTrue);
      expect(backend.permissionRequests, 0);
      expect(backend.pending, isNull);
      expect(backend.cancellations, 1);
    },
  );

  test('nonexistent DST time does not change the repeating wall time', () {
    final zone = tz.getLocation('America/New_York');
    const early = DailyReminderSettings(enabled: true, hour: 2, minute: 30);
    expect(
      nextDailyReminder(tz.TZDateTime(zone, 2026, 3, 8, 1), early),
      tz.TZDateTime(zone, 2026, 3, 9, 2, 30),
    );
    expect(
      nextDailyReminder(tz.TZDateTime(zone, 2026, 3, 7, 23), early),
      tz.TZDateTime(zone, 2026, 3, 9, 2, 30),
    );
  });

  test('enable, change time, restart, disable persist and schedule', () async {
    expect(await service.update(enabled), isTrue);
    expect(backend.permissionRequests, 1);
    expect(backend.pending, tz.TZDateTime.utc(2026, 9, 28, 20));
    const changed = DailyReminderSettings(enabled: true, hour: 21, minute: 15);
    expect(await service.update(changed), isTrue);
    expect(backend.permissionRequests, 1);
    service.dispose();
    service = DailyReminderService(
      prefs,
      backend: backend,
      analytics: analytics,
    );
    expect(await service.refresh(), isTrue);
    expect(service.settings.encode(), changed.encode());
    expect(backend.permissionRequests, 1);
    expect(
      await service.update(const DailyReminderSettings(hour: 21, minute: 15)),
      isTrue,
    );
    expect(backend.pending, isNull);
    expect(
      DailyReminderSettings.decode(
        prefs.getString(DailyReminderService.settingsKey)!,
      ).enabled,
      isFalse,
    );
  });

  test(
    'time persists while disabled without prompting or scheduling',
    () async {
      expect(
        await service.update(const DailyReminderSettings(hour: 8, minute: 30)),
        isTrue,
      );
      expect(backend.permissionRequests, 0);
      expect(backend.pending, isNull);
      expect(service.settings.hour, 8);
      expect(
        prefs.getString(DailyReminderService.settingsKey),
        contains('"minute":30'),
      );
    },
  );

  test(
    'permission rejection keeps switch off, preserves time, and can retry',
    () async {
      await service.update(const DailyReminderSettings(hour: 9));
      backend.granted = false;
      expect(
        await service.update(
          const DailyReminderSettings(enabled: true, hour: 9),
        ),
        isFalse,
      );
      expect(service.settings.enabled, isFalse);
      expect(service.settings.hour, 9);
      expect(service.error, reminderPermissionGuidance);
      expect(backend.pending, isNull);
      expect(
        prefs.getString(DailyReminderService.settingsKey),
        contains('"enabled":false'),
      );
      backend.granted = true;
      expect(await service.retry(), isTrue);
      expect(service.settings.enabled, isTrue);
      expect(service.error, isNull);
    },
  );

  test('resume detects permission revocation without prompting', () async {
    await service.update(enabled);
    backend.granted = false;
    expect(await service.refresh(), isTrue);
    expect(service.settings.enabled, isFalse);
    expect(service.error, reminderPermissionGuidance);
    expect(backend.pending, isNull);
    expect(backend.permissionRequests, 1);
  });

  test('resume reschedules using changed device timezone', () async {
    await service.update(enabled);
    backend.location = tz.getLocation('Asia/Shanghai');
    await service.refresh();
    expect(backend.pending, tz.TZDateTime(backend.location, 2026, 9, 29, 20));
    expect(backend.initializations, 1);
    expect(backend.permissionRequests, 1);
  });

  test('failed scheduling never persists enabled and exposes retry', () async {
    backend.failSchedule = true;
    expect(await service.update(enabled), isFalse);
    expect(service.settings.enabled, isFalse);
    expect(prefs.getString(DailyReminderService.settingsKey), isNull);
    expect(backend.pending, isNull);
    expect(service.error, isNotNull);
    backend.failSchedule = false;
    expect(await service.retry(), isTrue);
  });

  test(
    'unknown timezone fails explicitly rather than scheduling in UTC',
    () async {
      backend.failTimezone = true;
      expect(await service.update(enabled), isFalse);
      expect(service.settings.enabled, isFalse);
      expect(backend.pending, isNull);
      expect(service.error, isNotNull);
    },
  );

  test(
    'failed first save restores cache and cancels new notification',
    () async {
      store.failKey = 'flutter.${DailyReminderService.settingsKey}';
      expect(await service.update(enabled), isFalse);
      expect(service.settings.enabled, isFalse);
      expect(prefs.getString(DailyReminderService.settingsKey), isNull);
      expect(backend.pending, isNull);
      expect(service.error, isNotNull);
    },
  );

  test('failed cancellation does not claim reminder was disabled', () async {
    await service.update(enabled);
    backend.failCancel = true;
    expect(await service.update(const DailyReminderSettings()), isFalse);
    expect(service.settings.enabled, isTrue);
    expect(backend.pending, isNotNull);
    expect(prefs.getString(DailyReminderService.settingsKey), enabled.encode());
  });

  test('failed time save restores previous preference and schedule', () async {
    await service.update(enabled);
    final before = backend.pending;
    store.failKey = 'flutter.${DailyReminderService.settingsKey}';
    expect(
      await service.update(
        const DailyReminderSettings(enabled: true, hour: 22),
      ),
      isFalse,
    );
    expect(service.settings.encode(), enabled.encode());
    expect(prefs.getString(DailyReminderService.settingsKey), enabled.encode());
    expect(backend.pending, before);
    expect(service.error, isNotNull);
  });

  test(
    'permission revoked during time edit rolls back enabled state',
    () async {
      await service.update(enabled);
      backend.granted = false;
      expect(
        await service.update(
          const DailyReminderSettings(enabled: true, hour: 22),
        ),
        isFalse,
      );
      expect(service.settings.enabled, isFalse);
      expect(service.settings.hour, 20);
      expect(backend.pending, isNull);
      expect(service.error, reminderPermissionGuidance);
    },
  );

  test('operations serialize during permission prompt', () async {
    backend.permissionGate = Completer<void>();
    final first = service.update(enabled);
    final second = service.update(const DailyReminderSettings());
    await Future<void>.delayed(Duration.zero);
    expect(service.busy, isTrue);
    expect(backend.permissionRequests, 1);
    backend.permissionGate!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(service.busy, isFalse);
    expect(service.settings.enabled, isFalse);
    expect(backend.pending, isNull);
  });

  test('unsupported platforms do not call notification plugin', () async {
    backend.supported = false;
    expect(await service.refresh(), isTrue);
    expect(backend.initializations, 0);
    expect(await service.update(enabled), isFalse);
    expect(backend.permissionRequests, 0);
    expect(service.settings.enabled, isFalse);
  });

  test('corrupt preferences fail visibly without overwriting data', () async {
    await prefs.setString(DailyReminderService.settingsKey, 'bad');
    expect(await service.refresh(), isFalse);
    expect(service.error, isNotNull);
    expect(prefs.getString(DailyReminderService.settingsKey), 'bad');
  });

  test(
    'cold and warm payloads are consumed once; unknown payloads ignored',
    () async {
      backend.launchPayload = dailyReminderPayload;
      await service.refresh();
      expect(service.takePendingOpen(), isTrue);
      expect(service.takePendingOpen(), isFalse);
      backend.onTap!('unknown');
      expect(service.takePendingOpen(), isFalse);
      backend.onTap!(dailyReminderPayload);
      expect(service.takePendingOpen(), isTrue);
      await service.refresh();
      expect(service.takePendingOpen(), isFalse);
    },
  );

  test(
    'only successful toggle changes produce allowlisted analytics',
    () async {
      backend.granted = false;
      await service.update(enabled);
      backend.granted = true;
      await service.update(enabled);
      await service.update(
        const DailyReminderSettings(enabled: true, hour: 21),
      );
      await service.update(const DailyReminderSettings(hour: 21));
      final events = File('${directory.path}/pending_events.jsonl')
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map)
          .where((event) => event['name'] == 'daily_reminder_toggle')
          .toList();
      expect(events, hasLength(2));
      expect(events.map((event) => event['params']['on']), [1, 0]);
      expect(events.first['params'].containsKey('hour'), isFalse);
    },
  );
}
