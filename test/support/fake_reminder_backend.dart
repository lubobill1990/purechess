import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:purechess/app/notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class FakeReminderBackend implements ReminderBackend {
  @override
  bool supported = true;
  bool granted = true;
  bool failSchedule = false;
  bool failCancel = false;
  bool failTimezone = false;
  int initializations = 0;
  int permissionRequests = 0;
  int cancellations = 0;
  String? launchPayload;
  ValueChanged<String?>? onTap;
  Completer<void>? permissionGate;
  tz.Location location = tz.UTC;
  tz.TZDateTime? pending;

  @override
  Future<String?> initialize(ValueChanged<String?> onTap) async {
    initializations++;
    this.onTap = onTap;
    return launchPayload;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    await permissionGate?.future;
    return granted;
  }

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<tz.Location> localTimezone() async {
    if (failTimezone) throw StateError('timezone unavailable');
    return location;
  }

  @override
  Future<void> schedule(tz.TZDateTime time) async {
    if (failSchedule) throw StateError('schedule failed');
    pending = time;
  }

  @override
  Future<void> cancel() async {
    if (failCancel) throw StateError('cancel failed');
    cancellations++;
    pending = null;
  }
}
