import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/notifications.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'requestNotificationsPermission':
        case 'requestPermissions':
        case 'areNotificationsEnabled':
          return true;
        case 'checkPermissions':
          return {'isEnabled': true};
        case 'getNotificationAppLaunchDetails':
          return {
            'notificationLaunchedApp': true,
            'notificationResponse': {
              'notificationResponseType': 0,
              'payload': dailyReminderPayload,
              'id': dailyReminderId,
            },
          };
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(
      timezoneChannel,
      (_) async => 'Asia/Shanghai',
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform initializes without prompt, schedules repeating local time and cancels own ID',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.android) {
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        } else {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        }
        final backend = LocalReminderBackend(
          plugin: FlutterLocalNotificationsPlugin(),
        );
        expect(backend.supported, isTrue);
        expect(await backend.initialize((_) {}), dailyReminderPayload);
        expect(calls.where((c) => c.method.startsWith('request')), isEmpty);
        if (platform == TargetPlatform.iOS) {
          final init =
              calls.firstWhere((c) => c.method == 'initialize').arguments
                  as Map;
          expect(init['requestAlertPermission'], isFalse);
          expect(init['requestBadgePermission'], isFalse);
          expect(init['requestSoundPermission'], isFalse);
        }
        expect(await backend.requestPermission(), isTrue);
        expect(await backend.hasPermission(), isTrue);
        final zone = await backend.localTimezone();
        expect(zone.name, 'Asia/Shanghai');
        await backend.schedule(tz.TZDateTime(zone, 2026, 9, 28, 20));
        final args =
            calls.firstWhere((c) => c.method == 'zonedSchedule').arguments
                as Map;
        expect(args['id'], dailyReminderId);
        expect(args['payload'], dailyReminderPayload);
        expect(args['timeZoneName'], 'Asia/Shanghai');
        expect(args['scheduledDateTime'], '2026-09-28T20:00:00');
        expect(args['matchDateTimeComponents'], DateTimeComponents.time.index);
        expect(args['body'], '今天的战术题还等着你 ♟️');
        if (platform == TargetPlatform.android) {
          expect(
            args['platformSpecifics']['scheduleMode'],
            AndroidScheduleMode.inexactAllowWhileIdle.name,
          );
          expect(args['platformSpecifics']['icon'], 'ic_stat_chess');
        }
        await backend.cancel();
        expect(calls.last.method, 'cancel');
        expect(
          platform == TargetPlatform.android
              ? calls.last.arguments['id']
              : calls.last.arguments,
          dailyReminderId,
        );
      },
    );
  }
}
