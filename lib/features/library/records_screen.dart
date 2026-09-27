import 'package:flutter/material.dart';

import '../../app/telemetry/crash_guard.dart';
import '../../core/pgn.dart';
import 'records_repository.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({
    super.key,
    this.openRepository = RecordsRepository.open,
  });

  final Future<RecordsRepository> Function() openRepository;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  List<RecordFileInfo>? _records;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _records = null;
      _error = null;
    });
    try {
      final repository = await widget.openRepository();
      final records = await repository.list();
      if (mounted) setState(() => _records = records);
    } catch (error, stack) {
      reportHandledError('list_pgn', error, stack);
      if (mounted) setState(() => _error = '棋谱库读取失败，请重试');
    }
  }

  Future<void> _read(RecordFileInfo file) async {
    try {
      final repository = await widget.openRepository();
      final record = await repository.read(file.path);
      final text = Pgn.generate(record);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(file.name)),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText(text),
            ),
          ),
        ),
      );
    } catch (error, stack) {
      reportHandledError('read_pgn', error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('棋谱打开失败，文件可能损坏或已被移除')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('我的棋谱'),
      actions: [
        IconButton(
          tooltip: '刷新棋谱库',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          )
        : _records == null
        ? const Center(child: CircularProgressIndicator())
        : _records!.isEmpty
        ? const Center(
            child: Text(
              '还没有棋谱\n对弈后点击「保存棋谱」，在这里查看。',
              textAlign: TextAlign.center,
            ),
          )
        : ListView.builder(
            itemCount: _records!.length,
            itemBuilder: (context, index) {
              final record = _records![index];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(record.name),
                subtitle: Text(
                  record.modified.toLocal().toString().split('.').first,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _read(record),
              );
            },
          ),
  );
}
