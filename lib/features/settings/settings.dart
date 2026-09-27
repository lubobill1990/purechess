import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/analytics.dart';
import 'ai_status_tile.dart';
import 'backup.dart';
import 'privacy.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.prefs,
    required this.analytics,
  });

  final SharedPreferences prefs;
  final Analytics analytics;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saving = false;

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
          AiStatusTile(analytics: widget.analytics, prefs: widget.prefs),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份与恢复'),
            subtitle: const Text('导出棋谱与学习进度，或合并恢复备份'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BackupScreen(
                  prefs: widget.prefs,
                  analytics: widget.analytics,
                ),
              ),
            ),
          ),
          SwitchListTile(
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
