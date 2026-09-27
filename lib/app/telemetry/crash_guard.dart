/// Flutter/platform/zone crash reporting, ported from pureweiqi.
/// Error messages and stacks are local-only; telemetry contains categories.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'analytics.dart';
import 'app_logger.dart';

void installCrashGuard() {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    _report('flutter_error', details.exception, details.stack);
    previousFlutterHandler?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _report('uncaught_error', error, stack);
    return true;
  };
}

R? runGuarded<R>(R Function() body) => runZonedGuarded(body, (error, stack) {
  _report('zone_error', error, stack);
});

void _report(String kind, Object error, StackTrace? stack) {
  logE('crash', '$kind: $error\n${stack ?? ''}');
  Analytics.instance.event('app_error', {'error_kind': kind});
  unawaited(Analytics.instance.flushNow());
  unawaited(AppLogger.instance.flush());
}

void reportHandledError(String where, Object error, [StackTrace? stack]) {
  logW('crash', 'handled error in $where');
  _report('handled_error', error, stack);
}
