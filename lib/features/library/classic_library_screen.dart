import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/crash_guard.dart';
import '../home/study_theme.dart';
import 'classic_library.dart';
import 'classic_reader_screen.dart';

class ClassicLibraryScreen extends StatefulWidget {
  const ClassicLibraryScreen({
    super.key,
    required this.prefs,
    this.resume = false,
    this.load = ClassicLibrary.load,
  });

  final SharedPreferences prefs;
  final bool resume;
  final Future<List<ClassicGame>> Function() load;

  @override
  State<ClassicLibraryScreen> createState() => _ClassicLibraryScreenState();
}

class _ClassicLibraryScreenState extends State<ClassicLibraryScreen> {
  List<ClassicGame>? _games;
  String? _error;
  String? _notice;
  ClassicGame? _resume;
  int _initialPly = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final games = await widget.load();
      if (games.isEmpty) throw const FormatException('Empty classic library');
      final progress = ReadingProgress.read(widget.prefs);
      if (!mounted) return;
      setState(() {
        _games = games;
        _notice = progress.error;
        if (widget.resume && progress.error == null) {
          final matches = games.where((game) => game.id == progress.id);
          if (progress.id == null) {
            _resume = games.first;
          } else if (matches.isNotEmpty &&
              progress.ply <= matches.first.plies) {
            _resume = matches.first;
            _initialPly = progress.ply;
          } else {
            _notice = '上次阅读的位置已失效，请重新选择名局。';
          }
        }
      });
    } catch (error, stack) {
      reportHandledError('classic_library', error, stack);
      if (mounted) setState(() => _error = '名局库读取失败，请重试。');
    }
  }

  Future<void> _open(ClassicGame game) async {
    final progress = ReadingProgress.read(widget.prefs);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ClassicReaderScreen(
          game: game,
          prefs: widget.prefs,
          initialPly: progress.id == game.id && progress.ply <= game.plies
              ? progress.ply
              : 0,
        ),
      ),
    );
    if (mounted) setState(() => _notice = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_resume != null) {
      return ClassicReaderScreen(
        game: _resume!,
        prefs: widget.prefs,
        initialPly: _initialPly,
      );
    }
    final progress = ReadingProgress.read(widget.prefs);
    return StudyTheme(
      child: Scaffold(
        appBar: AppBar(title: const Text('名局库')),
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
            : _games == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        '${_games!.length} 盘名局 · 1900 年以前\n不急着猜下一步，先读懂棋子的配合。',
                        style: const TextStyle(fontSize: 20, height: 1.6),
                      ),
                      if (_notice != null) Text(_notice!),
                      const SizedBox(height: 24),
                      for (final game in _games!) ...[
                        Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(game.title),
                            subtitle: Text(
                              '${game.year} · ${game.topic}\n${game.players}'
                              '${progress.id == game.id ? '\n继续阅读 · ${progress.ply} / ${game.plies} 半回合' : ''}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(game),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
