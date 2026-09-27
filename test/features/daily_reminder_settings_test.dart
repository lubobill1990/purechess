import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/notifications.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/features/settings/daily_reminder_settings.dart';
import 'package:purechess/features/tutorial/tutorial_level.dart';
import 'package:purechess/features/tutorial/tutorial_screen.dart';
import 'package:purechess/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_reminder_backend.dart';

void main() {
  late SharedPreferences prefs;
  late FakeReminderBackend backend;

  Future<void> settleDaily(WidgetTester tester) async {
    // Notification navigation is deferred until the next frame.
    await tester.pump();
    await tester.pump();
    await tester.runAsync(TutorialCatalog.load);
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await TutorialCatalog.load();
    SharedPreferences.setMockInitialValues({
      Analytics.privacyAcceptedKey: true,
    });
    prefs = await SharedPreferences.getInstance();
    backend = FakeReminderBackend();
  });

  testWidgets('default 20:00, rejection rollback and visible guidance', (
    tester,
  ) async {
    backend.granted = false;
    backend.permissionGate = Completer<void>();
    final service = DailyReminderService(prefs, backend: backend);
    addTearDown(service.dispose);
    await service.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DailyReminderTiles(service: service)),
      ),
    );
    final toggle = find.byKey(const ValueKey('daily-reminder-toggle'));
    expect(find.text('20:00'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    backend.permissionGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text(reminderPermissionGuidance), findsOneWidget);
    expect(prefs.getString(DailyReminderService.settingsKey), isNull);
    backend.granted = true;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text(reminderPermissionGuidance), findsNothing);
  });

  testWidgets('time picker saves custom time while reminder stays off', (
    tester,
  ) async {
    final service = DailyReminderService(prefs, backend: backend);
    addTearDown(service.dispose);
    await service.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DailyReminderTiles(service: service)),
      ),
    );
    await tester.tap(find.text('提醒时间'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialTime,
      const TimeOfDay(hour: 20, minute: 0),
    );
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '08');
    await tester.enterText(find.byType(TextField).at(1), '35');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('08:35'), findsOneWidget);
    expect(service.settings.enabled, isFalse);
    expect(service.settings.hour, 8);
    expect(service.settings.minute, 35);
    expect(backend.permissionRequests, 0);
    expect(
      prefs.getString(DailyReminderService.settingsKey),
      service.settings.encode(),
    );
  });

  testWidgets('cancelling time selection changes nothing', (tester) async {
    final service = DailyReminderService(prefs, backend: backend);
    addTearDown(service.dispose);
    await service.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DailyReminderTiles(service: service)),
      ),
    );
    await tester.tap(find.text('提醒时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('20:00'), findsOneWidget);
    expect(prefs.getString(DailyReminderService.settingsKey), isNull);
  });

  testWidgets(
    'cold notification opens actual daily screen and retains home back stack',
    (tester) async {
      backend.launchPayload = dailyReminderPayload;
      await tester.pumpWidget(MyApp(prefs: prefs, reminderBackend: backend));
      await settleDaily(tester);
      expect(find.byType(TutorialDailyScreen), findsOneWidget);
      expect(find.text('每日战术题 · 入门练习'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('设置'), findsOneWidget);
      expect(backend.permissionRequests, 0);
    },
  );

  testWidgets('warm taps ignore unknown payload and deduplicate daily route', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(prefs: prefs, reminderBackend: backend));
    await tester.pumpAndSettle();
    backend.onTap!('unknown');
    await tester.pumpAndSettle();
    expect(find.byType(TutorialDailyScreen), findsNothing);
    backend.onTap!(dailyReminderPayload);
    backend.onTap!(dailyReminderPayload);
    await settleDaily(tester);
    expect(find.byType(TutorialDailyScreen), findsOneWidget);
    backend.onTap!(dailyReminderPayload);
    await settleDaily(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TutorialDailyScreen), findsNothing);
    backend.onTap!(dailyReminderPayload);
    await settleDaily(tester);
    expect(find.byType(TutorialDailyScreen), findsOneWidget);
  });

  testWidgets('cold notification waits for first-launch privacy choice', (
    tester,
  ) async {
    await prefs.remove(Analytics.privacyAcceptedKey);
    backend.launchPayload = dailyReminderPayload;
    await tester.pumpWidget(MyApp(prefs: prefs, reminderBackend: backend));
    await tester.pumpAndSettle();
    expect(find.text('隐私告知'), findsOneWidget);
    expect(find.byType(TutorialDailyScreen), findsNothing);
    // Simulate the persisted privacy choice and dialog completion without
    // initializing the unrelated telemetry storage in this routing test.
    await prefs.setBool(Analytics.privacyAcceptedKey, true);
    final context = tester.element(find.text('隐私告知'));
    Navigator.of(context).pop();
    await settleDaily(tester);
    expect(find.byType(TutorialDailyScreen), findsOneWidget);
  });

  testWidgets('unsupported platform disables switch and time picker', (
    tester,
  ) async {
    backend.supported = false;
    final service = DailyReminderService(prefs, backend: backend);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DailyReminderTiles(service: service)),
      ),
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(find.text('当前平台暂不支持本地提醒'), findsOneWidget);
    await tester.tap(find.text('提醒时间'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
  });
}
