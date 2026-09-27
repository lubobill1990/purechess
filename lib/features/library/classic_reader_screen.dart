import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/crash_guard.dart';
import '../../widgets/board/chess_board.dart';
import '../home/study_theme.dart';
import 'classic_library.dart';

class ClassicReaderScreen extends StatefulWidget {
  const ClassicReaderScreen({
    super.key,
    required this.game,
    required this.prefs,
    this.initialPly = 0,
  });

  final ClassicGame game;
  final SharedPreferences prefs;
  final int initialPly;

  @override
  State<ClassicReaderScreen> createState() => _ClassicReaderScreenState();
}

class _ClassicReaderScreenState extends State<ClassicReaderScreen> {
  late int _ply;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ply = widget.initialPly.clamp(0, widget.game.plies);
    unawaited(_save());
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ReadingProgress.save(widget.prefs, widget.game, _ply);
    } catch (error, stack) {
      reportHandledError('library_progress', error, stack);
      if (mounted) setState(() => _error = '阅读进度保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _go(int ply) {
    if (_saving || ply < 0 || ply > widget.game.plies || ply == _ply) return;
    setState(() => _ply = ply);
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) => StudyTheme(
    child: Builder(
      builder: (context) {
        final game = widget.game;
        final node = game.line[_ply];
        final theme = Theme.of(context);
        final annotation = node.comments.join('\n\n');
        final move = _ply == 0
            ? '开局前'
            : '${(_ply + 1) ~/ 2}${_ply.isOdd ? '.' : '...'} '
                  '${game.record.boardAt(game.line[_ply - 1]).san(node.move!)}';
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _go(_ply - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _go(_ply + 1),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(title: Text(game.title)),
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 800;
                    final board = ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ChessBoard(
                          board: game.record.boardAt(node),
                          enabled: false,
                          onMove: (_) {},
                        ),
                      ),
                    );
                    final notes = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${game.year} · ${game.topic}',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(game.players, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 24),
                        Text(move, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            annotation.isEmpty
                                ? (_ply == game.plies
                                      ? '棋谱到此结束。试着回看关键转折，找出子力如何配合。'
                                      : '观察刚才的一步：它改变了哪些格子的控制？')
                                : annotation,
                            key: const ValueKey('reader-comment'),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 22,
                              height: 1.65,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                        if (_ply == game.plies) ...[
                          const SizedBox(height: 20),
                          Text(
                            '全局读完 · ${game.record.result}',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                        const SizedBox(height: 24),
                        SelectableText(
                          '棋谱来源：${game.record.tags['Source']}\n中文简注：纯弈国象原创',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    );
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: board),
                                    const SizedBox(width: 32),
                                    Expanded(child: notes),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(child: board),
                                    const SizedBox(height: 24),
                                    notes,
                                  ],
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null)
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            TextButton(
                              onPressed: _saving ? null : _save,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      Text(
                        '$_ply / ${game.plies} 半回合',
                        key: const ValueKey('reader-progress'),
                      ),
                      Slider(
                        value: _ply.toDouble(),
                        max: game.plies.toDouble(),
                        divisions: game.plies,
                        semanticFormatterCallback: (value) =>
                            '第 ${value.round()} 半回合',
                        onChanged: _saving
                            ? null
                            : (value) => _go(value.round()),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _saving || _ply == 0
                                ? null
                                : () => _go(_ply - 1),
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('上一步'),
                          ),
                          FilledButton.icon(
                            onPressed: _saving || _ply == game.plies
                                ? null
                                : () => _go(_ply + 1),
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('下一步'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
