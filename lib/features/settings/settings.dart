import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/notifications.dart';
import '../../app/sound.dart';
import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import 'ai_status_tile.dart';
import 'daily_reminder_settings.dart';
import 'privacy.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.prefs,
    required this.analytics,
    this.reminders,
  });

  final SharedPreferences prefs;
  final Analytics analytics;
  final DailyReminderService? reminders;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saving = false;
  bool _savingSound = false;
  late final DailyReminderService _reminders;

  @override
  void initState() {
    super.initState();
    _reminders =
        widget.reminders ??
        DailyReminderService(widget.prefs, analytics: widget.analytics);
    if (widget.reminders == null) unawaited(_reminders.refresh());
  }

  @override
  void dispose() {
    if (widget.reminders == null) _reminders.dispose();
    super.dispose();
  }

  Future<void> _setSoundEnabled(bool value) async {
    setState(() => _savingSound = true);
    if (!value) SoundService.stopAll();
    try {
      if (!await widget.prefs.setBool(SoundService.enabledKey, value)) {
        throw StateError('Sound preference write failed');
      }
    } catch (error, stack) {
      reportHandledError('sound_settings', error, stack);
      try {
        await widget.prefs.reload();
      } catch (error, stack) {
        reportHandledError('sound_settings_reload', error, stack);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('音效设置保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _savingSound = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _saving = true);
    try {
      await widget.analytics.setEnabled(value, widget.prefs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('统计设置保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('音效'),
            subtitle: const Text('落子、吃子、将军与完成提示音'),
            value: widget.prefs.getBool(SoundService.enabledKey) ?? true,
            onChanged: _savingSound ? null : _setSoundEnabled,
          ),
          AiStatusTile(analytics: widget.analytics, prefs: widget.prefs),
          DailyReminderTiles(service: _reminders),
          SwitchListTile(
            key: const ValueKey('analytics-toggle'),
            title: const Text('匿名使用统计'),
            subtitle: const Text('匿名使用与崩溃类别；不含棋局内容，可随时关闭'),
            value: widget.analytics.enabled,
            onChanged: _saving ? null : _setEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私政策'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrivacyPolicyScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
