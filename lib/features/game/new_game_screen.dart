import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/crash_guard.dart';
import '../../core/move.dart' as chess;
import 'ai_difficulty.dart';
import 'ai_game_screen.dart';

class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key, this.prefs, this.analytics});

  final SharedPreferences? prefs;
  final Analytics? analytics;

  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  AiDifficulty? _rating;
  chess.Color _color = chess.Color.white;
  int _level = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rating = AiDifficulty(
        widget.prefs ?? await SharedPreferences.getInstance(),
      );
      final level = rating.recommended;
      if (mounted) {
        setState(() {
          _rating = rating;
          _level = level;
        });
      }
    } catch (error, stack) {
      reportHandledError('game_preferences', error, stack);
      if (mounted) setState(() => _error = '无法读取推荐难度，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新对局')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '与 AI 对弈',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text('从适合自己的难度开始，每局结束后再进一步。'),
                const SizedBox(height: 28),
                Text('我执', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SegmentedButton<chess.Color>(
                  segments: const [
                    ButtonSegment(
                      value: chess.Color.white,
                      label: Text('白棋 · 先走'),
                    ),
                    ButtonSegment(
                      value: chess.Color.black,
                      label: Text('黑棋 · 后走'),
                    ),
                  ],
                  selected: {_color},
                  onSelectionChanged: (value) =>
                      setState(() => _color = value.single),
                ),
                const SizedBox(height: 28),
                Text(
                  '难度 · $_level / 10',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Slider(
                  key: const ValueKey('difficulty-slider'),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  value: _level.toDouble(),
                  label: '第 $_level 档',
                  onChanged: _rating == null
                      ? null
                      : (value) => setState(() => _level = value.round()),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('1 · 初次尝试'), Text('10 · 全力挑战')],
                ),
                const SizedBox(height: 16),
                if (_rating != null)
                  Text('推荐第 ${_rating!.recommended} 档 · 首次从第 1 档开始'),
                const Text('胜局升一档，负局降一档，和棋保持本档。只影响下一局推荐，随时可以自己选择。'),
                const SizedBox(height: 16),
                const Text('提示不会代你落子；悔棋撤回你和 AI 各一步。终局后可一键复盘。'),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          key: const ValueKey('start-ai-game'),
          onPressed: _rating == null
              ? null
              : () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AiGameScreen(
                      config: AiGameConfig(
                        humanColor: _color,
                        difficulty: _level,
                      ),
                      rating: _rating!,
                      analytics: widget.analytics,
                    ),
                  ),
                ),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('开始对弈'),
          ),
        ),
      ),
    );
  }
}
