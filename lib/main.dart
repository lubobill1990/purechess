import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/notifications.dart';
import 'app/sound.dart';
import 'app/telemetry/analytics.dart';
import 'app/telemetry/app_logger.dart';
import 'app/telemetry/crash_guard.dart';
import 'features/settings/privacy.dart';

void main() {
  runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installCrashGuard();
    await AppLogger.instance.init();
    final prefs = await SharedPreferences.getInstance();
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (error, stack) {
      reportHandledError('package_info', error, stack);
    }
    await Analytics.instance.init(prefs, appVersion: version);
    logI('app', 'starting purechess $version');
    runApp(MyApp(prefs: prefs));
  });
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.prefs,
    this.analytics,
    this.reminderBackend,
  });

  final SharedPreferences prefs;
  final Analytics? analytics;
  final ReminderBackend? reminderBackend;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final DailyReminderService _reminders;
  bool _navigationReady = false;
  bool _dailyOpen = false;
  Analytics get _analytics => widget.analytics ?? Analytics.instance;

  @override
  void initState() {
    super.initState();
    _reminders = DailyReminderService(
      widget.prefs,
      analytics: _analytics,
      backend: widget.reminderBackend,
    )..addListener(_handleReminder);
    unawaited(_reminders.refresh());
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.prefs.getBool(Analytics.privacyAcceptedKey) != true) {
        await showDialog<void>(
          context: _navigatorKey.currentContext!,
          barrierDismissible: false,
          builder: (_) =>
              PrivacyNoticeDialog(prefs: widget.prefs, analytics: _analytics),
        );
      }
      if (!mounted) return;
      _navigationReady = true;
      _handleReminder();
    });
  }

  void _handleReminder() {
    if (!mounted || !_navigationReady || !_reminders.takePendingOpen()) return;
    if (_dailyOpen) return;
    _dailyOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _navigatorKey.currentState!.pushNamed(AppRouter.daily);
      _dailyOpen = false;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reminders.refresh());
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.resumed) {
      unawaited(_analytics.flushNow());
      unawaited(AppLogger.instance.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminders.removeListener(_handleReminder);
    _reminders.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: '纯弈国象',
      theme: quietControlsTheme(
        ThemeData(
          colorScheme: .fromSeed(seedColor: const Color(0xFF233648)),
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        ),
      ),
      routes: AppRouter.routes(
        prefs: widget.prefs,
        analytics: _analytics,
        reminders: _reminders,
      ),
    );
  }
}
