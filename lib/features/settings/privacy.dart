import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/analytics.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Text('纯弈国象隐私说明（占位稿）'),
          SizedBox(height: 16),
          Text(
            '匿名使用统计用于改进国际象棋对弈、战术练习及 AI 功能，'
            '包括功能使用次数、耗时、错误类别、应用版本和系统类型。'
            '启用后通过 Google Analytics 发送；当前统计服务尚待维护者配置。',
          ),
          SizedBox(height: 16),
          Text(
            '首次确认前仅在本地暂存，不会发送。选择“同意并继续”后才允许发送；'
            '选择“关闭统计并继续”或在设置中关闭统计，会停止发送并清除待发队列。'
            '已经发送的数据无法通过此开关撤回。关闭统计不影响任何功能。',
          ),
          SizedBox(height: 16),
          Text(
            '不上传棋谱、FEN 局面、走子、错误原文、堆栈或诊断日志。'
            '不采集姓名、联系方式、广告标识符或持久设备标识。'
            '每次启动生成新的随机会话标识，不用于跨次启动识别。'
            '网络服务方仍可能处理连接所需的 IP 地址等网络信息。',
          ),
          SizedBox(height: 16),
          Text(
            '诊断日志及崩溃阶段哨兵仅保存在本机，关闭统计后仍可用于本地排错。'
            '它们可能包含问题详情或文件路径，不会自动上传。',
          ),
          SizedBox(height: 16),
          // TODO: Maintainer: publish the policy and contact/retention details.
          Text(
            '正式发布前待补充：政策生效日期、隐私联系邮箱、数据保留期限、'
            '第三方处理及适用地区的跨境传输说明、正式政策链接。',
          ),
        ],
      ),
    );
  }
}

class PrivacyNoticeDialog extends StatefulWidget {
  const PrivacyNoticeDialog({
    super.key,
    required this.prefs,
    required this.analytics,
  });

  final SharedPreferences prefs;
  final Analytics analytics;

  @override
  State<PrivacyNoticeDialog> createState() => _PrivacyNoticeDialogState();
}

class _PrivacyNoticeDialogState extends State<PrivacyNoticeDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _accept(bool enabled) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.analytics.savePrivacyChoice(enabled, widget.prefs);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // The service logs the failure and keeps the consent gate closed.
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '隐私选择保存失败，请重试。确认前不会发送统计。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('隐私告知'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '匿名使用统计用于改进国际象棋功能与了解崩溃情况。'
              '确认前仅在本地暂存，不会发送；不上传棋局内容或个人身份信息。'
              '你可以现在关闭，也可以随时在设置中关闭，不影响任何功能。',
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    ),
              child: const Text('阅读隐私政策'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _accept(false),
            child: const Text('关闭统计并继续'),
          ),
          TextButton(
            onPressed: _saving ? null : () => _accept(true),
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
  }
}
