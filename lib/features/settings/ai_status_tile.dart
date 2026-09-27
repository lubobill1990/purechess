import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/analytics.dart';
import '../../app/telemetry/app_logger.dart';
import '../../core/fen.dart';
import '../../engine/stockfish_service.dart';

/// A real UI consumer of lifecycle and error notifications, until M3 game UI.
class AiStatusTile extends StatefulWidget {
  const AiStatusTile({
    super.key,
    required this.analytics,
    required this.prefs,
    this.service,
  });
  final Analytics analytics;
  final SharedPreferences prefs;
  final StockfishService? service;

  @override
  State<AiStatusTile> createState() => _AiStatusTileState();
}

class _AiStatusTileState extends State<AiStatusTile> {
  late final StockfishService _service =
      widget.service ??
      StockfishService(analytics: widget.analytics, prefs: widget.prefs);
  String? _error;
  bool _checking = false;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await _service.analyzePosition(Fen.initial, difficulty: 1);
    } on StockfishException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    if (widget.service == null) {
      unawaited(
        _service.dispose().catchError((Object error) {
          logE('engine', 'AI settings cleanup failed: $error');
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _service.status,
    builder: (context, _) {
      final status = _service.status.value;
      final message =
          status.error?.message ??
          _error ??
          switch (status.state) {
            StockfishState.stopped => 'AI 尚未启动',
            StockfishState.starting => 'AI 正在启动…',
            StockfishState.analyzing => 'AI 正在思考…',
            StockfishState.ready => 'AI 已就绪',
            StockfishState.stopping => 'AI 正在停止…',
            StockfishState.failed => 'AI 不可用，请重试',
            StockfishState.disposed => 'AI 已关闭',
          };
      return ListTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: const Text('AI 状态'),
        subtitle: SizedBox(
          height: 60,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ),
        trailing: TextButton(
          onPressed: _checking ? null : _check,
          child: const Text('检查 AI'),
        ),
      );
    },
  );
}
