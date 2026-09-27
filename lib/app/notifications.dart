import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'telemetry/analytics.dart';
import 'telemetry/app_logger.dart';

const dailyReminderPayload = 'daily_tactics';
const dailyReminderId = 7300;
const reminderPermissionGuidance = '通知权限未开启，请在系统设置中允许「纯弈国际象棋」发送通知，然后重新开启提醒。';

class DailyReminderSettings {
  const DailyReminderSettings({
    this.enabled = false,
    this.hour = 20,
    this.minute = 0,
  }) : assert(hour >= 0 && hour < 24),
       assert(minute >= 0 && minute < 60);

  final bool enabled;
  final int hour;
  final int minute;

  factory DailyReminderSettings.decode(String value) {
    final json = jsonDecode(value);
    if (json is! Map ||
        json['enabled'] is! bool ||
        json['hour'] is! int ||
        json['minute'] is! int) {
      throw const FormatException('提醒设置无效');
    }
    final hour = json['hour'] as int;
    final minute = json['minute'] as int;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException('提醒时间无效');
    }
    return DailyReminderSettings(
      enabled: json['enabled'] as bool,
      hour: hour,
      minute: minute,
    );
  }

  String encode() =>
      jsonEncode({'enabled': enabled, 'hour': hour, 'minute': minute});
}

tz.TZDateTime? nextDailyReminder(
  tz.TZDateTime now,
  DailyReminderSettings settings,
) {
  if (!settings.enabled) return null;
  tz.TZDateTime atDay(int day) => tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    day,
    settings.hour,
    settings.minute,
  );
  // Calendar arithmetic preserves wall-clock time over daylight-saving changes.
  // Skip a nonexistent local time rather than permanently shifting the repeat.
  for (var day = now.day; day <= now.day + 2; day++) {
    final next = atDay(day);
    if (next.isAfter(now) &&
        next.hour == settings.hour &&
        next.minute == settings.minute) {
      return next;
    }
  }
  throw StateError('无法计算提醒时间');
}

abstract class ReminderBackend {
  bool get supported;
  Future<String?> initialize(ValueChanged<String?> onTap);
  Future<bool> requestPermission();
  Future<bool> hasPermission();
  Future<tz.Location> localTimezone();
  Future<void> schedule(tz.TZDateTime time);
  Future<void> cancel();
}

class LocalReminderBackend implements ReminderBackend {
  LocalReminderBackend({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<String?> initialize(ValueChanged<String?> onTap) async {
    tzdata.initializeTimeZones();
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_chess'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    if (initialized != true) throw StateError('本地提醒初始化失败');
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true
        ? launch?.notificationResponse?.payload
        : null;
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()!
              .requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()!
            .requestPermissions(alert: true, badge: false, sound: true) ??
        false;
  }

  @override
  Future<bool> hasPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()!
              .areNotificationsEnabled() ??
          false;
    }
    final permissions = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()!
        .checkPermissions();
    return permissions?.isEnabled == true;
  }

  @override
  Future<tz.Location> localTimezone() async =>
      tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier);

  @override
  Future<void> cancel() => _plugin.cancel(id: dailyReminderId);

  @override
  Future<void> schedule(tz.TZDateTime time) => _plugin.zonedSchedule(
    id: dailyReminderId,
    title: '纯弈国际象棋 · 每日战术题',
    body: '今天的战术题还等着你 ♟️',
    scheduledDate: time,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_tactics',
        '每日战术题提醒',
        channelDescription: '每天在设定时间提醒你练习战术题',
        icon: 'ic_stat_chess',
      ),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
    payload: dailyReminderPayload,
  );
}

class DailyReminderService extends ChangeNotifier {
  DailyReminderService(
    this._prefs, {
    ReminderBackend? backend,
    Analytics? analytics,
    DateTime Function()? now,
  }) : _backend = backend ?? LocalReminderBackend(),
       _analytics = analytics ?? Analytics.instance,
       _now = now ?? DateTime.now;

  static const settingsKey = 'dailyReminderSettings';
  final SharedPreferences _prefs;
  final ReminderBackend _backend;
  final Analytics _analytics;
  final DateTime Function() _now;
  Future<void> _tail = Future.value();
  bool _loaded = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _pendingOpen = false;
  int _operations = 0;
  DailyReminderSettings _settings = const DailyReminderSettings();
  DailyReminderSettings? _retrySettings;
  String? error;

  DailyReminderSettings get settings => _settings;
  bool get supported => _backend.supported;
  bool get busy => _operations != 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onTap(String? payload) {
    if (_disposed || payload != dailyReminderPayload) return;
    _pendingOpen = true;
    _notify();
  }

  bool takePendingOpen() {
    final pending = _pendingOpen;
    _pendingOpen = false;
    return pending;
  }

  Future<bool> _run(Future<void> Function() action) {
    _operations++;
    _notify();
    final result = _tail.then((_) async {
      try {
        await action();
        return true;
      } catch (cause, stack) {
        error ??= '提醒未更新，请重试。';
        logE('notifications', '$error $cause\n$stack');
        return false;
      } finally {
        _operations--;
        _notify();
      }
    });
    _tail = result.then((_) {});
    return result;
  }

  Future<void> _initialize() async {
    if (!_loaded) {
      final saved = _prefs.getString(settingsKey);
      _settings = saved == null
          ? const DailyReminderSettings()
          : DailyReminderSettings.decode(saved);
      _loaded = true;
    }
    if (!_initialized && supported) {
      final payload = await _backend.initialize(_onTap);
      _initialized = true;
      _onTap(payload);
    }
  }

  Future<void> _schedule(DailyReminderSettings value) async {
    if (!value.enabled) {
      await _backend.cancel();
      return;
    }
    final location = await _backend.localTimezone();
    await _backend.schedule(
      nextDailyReminder(tz.TZDateTime.from(_now(), location), value)!,
    );
  }

  Future<void> _save(DailyReminderSettings value) async {
    if (!await _prefs.setString(settingsKey, value.encode())) {
      throw StateError('提醒设置保存失败');
    }
  }

  Future<void> _commit(DailyReminderSettings value) async {
    final previous = settings;
    final saved = _prefs.getString(settingsKey);
    var writing = false;
    try {
      await _schedule(value);
      writing = true;
      await _save(value);
    } catch (_) {
      // SharedPreferences mutates its cache even if the native write fails.
      try {
        if (writing) {
          final restored = saved == null
              ? await _prefs.remove(settingsKey)
              : await _prefs.setString(settingsKey, saved);
          if (!restored) throw StateError('提醒设置恢复失败');
        }
      } finally {
        await _schedule(previous);
      }
      rethrow;
    }
    _settings = value;
    if (previous.enabled != value.enabled) {
      _analytics.event('daily_reminder_toggle', {'on': value.enabled});
    }
  }

  Future<bool> refresh() => _run(() async {
    await _initialize();
    if (!supported) {
      logI('notifications', 'Local reminders unavailable on this platform');
      return;
    }
    if (settings.enabled && !await _backend.hasPermission()) {
      await _commit(
        DailyReminderSettings(hour: settings.hour, minute: settings.minute),
      );
      error = reminderPermissionGuidance;
      _retrySettings = null;
      return;
    }
    await _schedule(settings);
  });

  Future<bool> update(DailyReminderSettings value) => _run(() async {
    error = null;
    _retrySettings = value;
    await _initialize();
    if (!supported) throw UnsupportedError('当前平台暂不支持本地提醒');
    if (value.enabled) {
      final granted = settings.enabled
          ? await _backend.hasPermission()
          : await _backend.requestPermission();
      if (!granted) {
        if (settings.enabled) {
          await _commit(
            DailyReminderSettings(hour: settings.hour, minute: settings.minute),
          );
        }
        error = reminderPermissionGuidance;
        throw StateError('通知权限被拒绝');
      }
    }
    await _commit(value);
    _retrySettings = null;
  });

  Future<bool> retry() {
    final value = _retrySettings;
    error = null;
    return value == null ? refresh() : update(value);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
