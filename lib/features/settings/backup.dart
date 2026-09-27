import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/app_logger.dart';
import '../library/records_repository.dart';
import 'backup_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.prefs,
    this.analytics,
    this.service,
    this.pickFile,
    this.shareFile,
  });

  final SharedPreferences prefs;
  final Analytics? analytics;
  final BackupService? service;
  final Future<File?> Function()? pickFile;
  final Future<ShareResult> Function(File, Rect)? shareFile;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;
  Analytics get _analytics => widget.analytics ?? Analytics.instance;

  Future<BackupService> _service() async =>
      widget.service ??
      BackupService(
        widget.prefs,
        (await RecordsRepository.open()).dir,
        await BackupCatalog.load(),
      );

  Future<void> _run(
    String event,
    Future<({bool ok, String message})?> Function() operation,
  ) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await operation();
      _analytics.event(event, {'ok': result?.ok ?? false});
      if (mounted) setState(() => _message = result?.message ?? '已取消，数据未更改。');
    } catch (error, stack) {
      logE('backup', 'Backup operation failed: $error\n$stack');
      _analytics.event(event, {'ok': false});
      if (mounted) {
        final detail =
            error is FormatException &&
                RegExp(r'[\u4e00-\u9fff]').hasMatch(error.message)
            ? error.message
            : error is StateError &&
                  RegExp(r'[\u4e00-\u9fff]').hasMatch(error.message)
            ? error.message
            : '文件损坏、内容无效或无法读写。请检查文件与可用空间后重试。';
        setState(() => _message = '备份操作失败：$detail\n请保留原备份文件。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({bool ok, String message})?> _export(Rect origin) async {
    final service = await _service();
    final bytes = await service.exportBytes();
    final work = await (await getTemporaryDirectory()).createTemp(
      'purechess-backup-',
    );
    try {
      final file = await File(
        '${work.path}${Platform.pathSeparator}'
        'purechess-${DateTime.now().millisecondsSinceEpoch}.zip',
      ).writeAsBytes(bytes, flush: true);
      final result =
          await (widget.shareFile?.call(file, origin) ??
              SharePlus.instance.share(
                ShareParams(
                  files: [XFile(file.path, mimeType: 'application/zip')],
                  subject: '纯弈国际象棋备份',
                  sharePositionOrigin: origin,
                ),
              ));
      if (result.status == ShareResultStatus.dismissed) {
        return (ok: false, message: '已取消分享。');
      }
      return (ok: true, message: '备份已交给分享面板，请确认已保存到你选择的位置。');
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<File?> _pickFile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: false,
    );
    if (selection == null) return null;
    final path = selection.files.single.path;
    if (path == null) throw const FormatException('无法读取所选文件，请先保存到本机');
    return File(path);
  }

  Future<({bool ok, String message})?> _import() async {
    final file = await (widget.pickFile?.call() ?? _pickFile());
    if (file == null) return null;
    final service = await _service();
    final data = await service.read(file);
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('确认合并恢复？'),
        scrollable: true,
        content: Text(
          '备份时间：${data.createdAt.toLocal()}\n\n'
          '${data.recordCount} 盘棋谱\n'
          '教程已完成 ${data.tutorialCompleted} 关\n'
          '谜题已完成 ${data.puzzleCompleted} 题\n'
          '${data.dailyCount} 天每日题记录\n'
          '${data.preferences.length} 项进度与设置\n\n'
          '棋谱按 ID 去重，同 ID 保留本地版本。教程取较大进度，'
          '谜题完成记录合并，不倒退；不同名局保留本地书签。\n'
          '备份中的 AI 难度设置会覆盖本地值。匿名统计和隐私选择保持不变。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('合并并恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    await service.restore(data);
    return (ok: true, message: '数据已恢复。棋谱、学习进度与设置已更新。');
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '保留每一盘，也保留每一步进步',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text('我的棋谱 · 教程与谜题进度 · 错题本\n每日题 · 名局书签 · AI 难度设置'),
          const SizedBox(height: 16),
          const Text(
            '备份是未加密的 ZIP 文件，可能含棋谱中的姓名和评注，只分享给可信任的人。'
            '不包含内置题库、诊断日志或隐私选择。',
          ),
          const SizedBox(height: 24),
          Builder(
            builder: (context) => FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      final box = context.findRenderObject()! as RenderBox;
                      final origin = box.localToGlobal(Offset.zero) & box.size;
                      _run('backup_export', () => _export(origin));
                    },
              icon: const Icon(Icons.ios_share),
              label: const Text('导出并分享备份'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run('backup_import', _import),
            icon: const Icon(Icons.restore),
            label: const Text('选择备份并恢复'),
          ),
          const SizedBox(height: 16),
          const Text('先校验，再确认；棋谱合并，进度不倒退。'),
          if (_busy) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
            const Text('正在处理，请勿关闭应用'),
          ],
          if (_message != null) ...[
            const SizedBox(height: 24),
            Semantics(liveRegion: true, child: Text(_message!)),
          ],
        ],
      ),
    ),
  );
}
