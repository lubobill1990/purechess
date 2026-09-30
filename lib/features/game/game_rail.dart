import 'package:flutter/material.dart';

import '../../widgets/board/board_panel.dart';
import '../../widgets/board/chess_board.dart';

/// Shared, fixed-height navigation within the game panel, not an app bar.
class GameRail extends StatelessWidget {
  const GameRail({
    super.key,
    required this.title,
    required this.onLeave,
    required this.onFlip,
    required this.onNewGame,
    required this.finished,
    required this.landscape,
    this.actions = const [],
  });

  final String title;
  final VoidCallback onLeave;
  final VoidCallback? onFlip;
  final VoidCallback? onNewGame;
  final bool finished;
  final bool landscape;
  final List<PopupMenuEntry<VoidCallback>> actions;

  @override
  Widget build(BuildContext context) {
    if (landscape) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: const CircleBorder(),
          elevation: 4,
          child: PopupMenuButton<VoidCallback>(
            key: const ValueKey('game-landscape-menu'),
            tooltip: '对局菜单',
            enableFeedback: false,
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              GameMenuItem(enabled: false, child: Text(title)),
              GameMenuItem(value: onLeave, child: const Text('返回')),
              GameMenuItem(
                value: onFlip,
                enabled: onFlip != null,
                child: const Text('翻转棋盘'),
              ),
              GameMenuItem(
                value: onNewGame,
                enabled: onNewGame != null,
                child: Text(finished ? '再来一局' : '新对局'),
              ),
              ...actions,
            ],
          ),
        ),
      );
    }

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
          if (actions.isNotEmpty)
            PopupMenuButton<VoidCallback>(
              tooltip: '更多操作',
              enableFeedback: false,
              iconColor: BoardPainter.ink,
              onSelected: (action) => action(),
              itemBuilder: (_) => actions,
            ),
        ],
      ),
    );
  }
}

/// Fixed touch targets; only the label scales down in narrow player rails.
class GameActionChip extends StatelessWidget {
  const GameActionChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// PopupMenuItem's internal InkWell otherwise bypasses the sound preference.
class GameMenuItem extends PopupMenuItem<VoidCallback> {
  const GameMenuItem({
    super.key,
    super.value,
    super.enabled,
    required super.child,
  });

  @override
  PopupMenuItemState<VoidCallback, GameMenuItem> createState() =>
      _GameMenuItemState();
}

class _GameMenuItemState
    extends PopupMenuItemState<VoidCallback, GameMenuItem> {
  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      enableFeedback: false,
      alignment: Alignment.centerLeft,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      shape: const RoundedRectangleBorder(),
    ),
    onPressed: widget.enabled ? handleTap : null,
    child: widget.child!,
  );
}
