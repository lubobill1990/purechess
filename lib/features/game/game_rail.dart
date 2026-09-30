import 'package:flutter/material.dart';

import '../../widgets/board/board_panel.dart';

/// Shared, fixed-height navigation within the game panel, not an app bar.
class GameRail extends StatelessWidget {
  const GameRail({
    super.key,
    required this.title,
    required this.onLeave,
    required this.onFlip,
    required this.onNewGame,
    required this.finished,
  });

  final String title;
  final VoidCallback onLeave;
  final VoidCallback? onFlip;
  final VoidCallback? onNewGame;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final compact = IconButton.styleFrom(
      fixedSize: const Size.square(44),
      minimumSize: const Size.square(44),
      maximumSize: const Size.square(44),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      iconSize: 20,
    );
    return BoardRail(
      height: 44,
      child: Row(
        children: [
          // BackButton retains the platform's localized navigation semantics.
          BackButton(onPressed: onLeave, style: compact),
          Expanded(
            child: Tooltip(
              message: title,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          IconButton(
            tooltip: '翻转棋盘',
            style: compact,
            onPressed: onFlip,
            icon: const Icon(Icons.flip_camera_android_outlined),
          ),
          IconButton(
            tooltip: finished ? '再来一局' : '新对局',
            style: compact,
            onPressed: onNewGame,
            icon: Icon(finished ? Icons.replay : Icons.add),
          ),
        ],
      ),
    );
  }
}
