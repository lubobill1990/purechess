import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chess_board.dart';

/// Keeps the board square and nearly flush with the short edge, framed as
/// one physical panel: rails and board share a rounded, hairline-bordered
/// surface with a breathing margin so the wood never touches the screen edge.
class BoardPanel extends StatelessWidget {
  const BoardPanel({
    super.key,
    required this.board,
    this.above = const SizedBox.shrink(),
    this.below = const SizedBox.shrink(),
    this.controls = const SizedBox.shrink(),
    this.scrollController,
  });

  /// Breathing room between the panel and the screen/pane edges.
  static const margin = 10.0;
  static const _radius = 14.0;

  final Widget board;
  final Widget above;
  final Widget below;
  final Widget controls;
  final ScrollController? scrollController;

  Widget _frame(BuildContext context, double size) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: (dark ? BoardPainter.ivory : BoardPainter.ink)
              .withValues(alpha: .25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .5 : .18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: SizedBox.square(dimension: size, child: board),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight;
      if (landscape) {
        final size = constraints.maxHeight - margin * 2;
        return Padding(
          padding: const EdgeInsets.all(margin),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _frame(context, size),
              const SizedBox(width: margin + 2),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(
                      240,
                      constraints.maxWidth - size - margin * 3 - 2,
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Status rails grouped into a card that speaks the
                          // same rounded/hairline language as the board frame.
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(_radius),
                              border: Border.all(
                                color:
                                    (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? BoardPainter.ivory
                                            : BoardPainter.ink)
                                        .withValues(alpha: .25),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(_radius),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [above, below],
                              ),
                            ),
                          ),
                          const SizedBox(height: margin),
                          controls,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      final size = constraints.maxWidth - margin * 2;
      return SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(margin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(
                  color:
                      (Theme.of(context).brightness == Brightness.dark
                              ? BoardPainter.ivory
                              : BoardPainter.ink)
                          .withValues(alpha: .25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha:
                          Theme.of(context).brightness == Brightness.dark
                              ? .5
                              : .18,
                    ),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    above,
                    SizedBox.square(dimension: size, child: board),
                    below,
                  ],
                ),
              ),
            ),
            const SizedBox(height: margin),
            controls,
          ],
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
