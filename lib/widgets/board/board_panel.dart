import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chess_board.dart';

/// Keeps the board square and flush with the available short edge.
class BoardPanel extends StatelessWidget {
  const BoardPanel({
    super.key,
    required this.board,
    this.above = const SizedBox.shrink(),
    this.below = const SizedBox.shrink(),
    this.controls = const SizedBox.shrink(),
    this.scrollController,
  });

  final Widget board;
  final Widget above;
  final Widget below;
  final Widget controls;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight;
      final size = landscape ? constraints.maxHeight : constraints.maxWidth;
      final surface = SizedBox.square(dimension: size, child: board);
      if (landscape) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            surface,
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(240, constraints.maxWidth - size),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [above, below, controls],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return SingleChildScrollView(
        controller: scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [above, surface, below, controls],
        ),
      );
    },
  );
}

/// A flush wood rail, without margins or rounded corners between it and the board.
class BoardRail extends StatelessWidget {
  const BoardRail({
    super.key,
    required this.child,
    this.height,
    this.emphasized = false,
  });

  final Widget child;
  final double? height;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = emphasized ? BoardPainter.ivory : BoardPainter.ink;
    final theme = Theme.of(context);
    return ColoredBox(
      color: emphasized
          ? (dark ? BoardPainter.nightDarkSquare : BoardPainter.darkSquare)
          : (dark ? BoardPainter.nightLightSquare : BoardPainter.lightSquare),
      child: Theme(
        data: theme.copyWith(
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: foreground,
              disabledForegroundColor: foreground.withValues(alpha: .5),
            ).merge(theme.textButtonTheme.style),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              foregroundColor: foreground,
              disabledForegroundColor: foreground.withValues(alpha: .5),
            ).merge(theme.iconButtonTheme.style),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: foreground,
              disabledForegroundColor: foreground.withValues(alpha: .5),
              side: BorderSide(color: foreground.withValues(alpha: .5)),
            ).merge(theme.outlinedButtonTheme.style),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: SizedBox(width: double.infinity, height: height, child: child),
        ),
      ),
    );
  }
}
