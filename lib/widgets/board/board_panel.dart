import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chess_board.dart';

Color boardTableColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF0F0C08)
    : const Color(0xFF4A3826);

AppBar boardAppBar(BuildContext context, String title) {
  final theme = Theme.of(context);
  return AppBar(
    foregroundColor: BoardPainter.ivory,
    titleTextStyle:
        (theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge)
            ?.copyWith(color: BoardPainter.ivory),
    title: Text(title),
  );
}

/// A bounded board on a walnut table. Only reading-page notes may scroll;
/// the board itself never participates in a scrollable.
class BoardPanel extends StatelessWidget {
  const BoardPanel({
    super.key,
    required this.board,
    this.above = const SizedBox.shrink(),
    this.below = const SizedBox.shrink(),
    this.controls = const SizedBox.shrink(),
    this.minimumSidebarWidth = 240,
    this.navigationBuilder,
    this.sideLeft,
    this.sideRight,
  });

  static const margin = 10.0;
  static const rim = 3.0;
  static const navigationWidth = 54.0;
  static const _radius = 14.0;

  final Widget board;
  final Widget above;
  final Widget below;
  final Widget controls;
  final double minimumSidebarWidth;
  final Widget Function(bool landscape)? navigationBuilder;

  /// Face-to-face landscape: when both are given, the board is horizontally
  /// centered between two equal-width player panes (one per player sitting
  /// left and right of the device) and [above]/[below]/[controls] are unused
  /// in that orientation. Portrait keeps the regular stacked layout.
  final Widget? sideLeft;
  final Widget? sideRight;

  Widget _frame(BuildContext context, Widget child) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(rim),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFFB69A68) : const Color(0xFFE8CD95),
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .7 : .38),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius - rim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: boardTableColor(context),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final height = constraints.maxHeight - margin * 2;
        final width = constraints.maxWidth - margin * 2;
        final navigation = navigationBuilder?.call(landscape);
        final sidebar = BoardRail(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [above, below],
          ),
        );
        final theme = Theme.of(context);
        final actions = Theme(
          data: theme.copyWith(
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: boardActionStyle(theme.colorScheme.onSurface),
            ),
          ),
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(11),
            clipBehavior: Clip.antiAlias,
            child: controls,
          ),
        );
        if (landscape && sideLeft != null && sideRight != null) {
          // Symmetric face-to-face layout: the board sits exactly in the
          // middle; navigation floats top-left so it costs no layout width.
          const minSidePane = 120.0;
          final size = math.min(
            height,
            math.max(0.0, width - minSidePane * 2 - margin * 2),
          );
          // The navigation pill owns the physical top-left corner; the right
          // pane gets the same top inset so both player panes stay level.
          final navigationInset = navigation == null ? 0.0 : 44.0 + margin;
          // Pane content lays out at a fixed design width and scales down as
          // a whole when the pane is shorter/narrower (tiny landscape, huge
          // text): no scrolling, no overflow, actions stay tappable.
          Widget pane(Widget side, {Widget? top}) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (navigationInset > 0)
                SizedBox(
                  height: navigationInset,
                  child: top == null
                      ? null
                      : Align(alignment: Alignment.topLeft, child: top),
                ),
              Flexible(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _frame(
                    context,
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(width: 220, child: side),
                    ),
                  ),
                ),
              ),
            ],
          );
          return Padding(
            padding: const EdgeInsets.all(margin),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: pane(sideLeft!, top: navigation)),
                const SizedBox(width: margin),
                Center(
                  child: SizedBox.square(
                    dimension: size,
                    child: _frame(context, board),
                  ),
                ),
                const SizedBox(width: margin),
                Expanded(child: pane(sideRight!)),
              ],
            ),
          );
        }
        if (landscape) {
          final navigationSpace = navigation == null ? 0.0 : navigationWidth;
          final size = math.min(
            height,
            math.max(
              0.0,
              width - navigationSpace - minimumSidebarWidth - margin,
            ),
          );
          return Padding(
            padding: const EdgeInsets.all(margin),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (navigation != null)
                  SizedBox(
                    width: navigationWidth,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: navigation,
                    ),
                  ),
                SizedBox.square(dimension: size, child: _frame(context, board)),
                const SizedBox(width: margin),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _frame(context, sidebar),
                      const SizedBox(height: margin),
                      Flexible(child: actions),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: _frame(
                  context,
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?navigation,
                      above,
                      Flexible(
                        child: Center(
                          heightFactor: 1,
                          child: AspectRatio(aspectRatio: 1, child: board),
                        ),
                      ),
                      below,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: margin),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * .3),
                child: actions,
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// A flush wood rail, without margins between it and the board.
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
    return Material(
      color: emphasized
          ? (dark ? BoardPainter.nightDarkSquare : BoardPainter.darkSquare)
          : (dark ? BoardPainter.nightLightSquare : BoardPainter.lightSquare),
      child: Theme(
        data: theme.copyWith(
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: foreground,
              enableFeedback: false,
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              foregroundColor: foreground,
              enableFeedback: false,
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: boardActionStyle(foreground),
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

ButtonStyle boardActionStyle(Color foreground) =>
    OutlinedButton.styleFrom(
      enableFeedback: false,
      foregroundColor: foreground,
      disabledForegroundColor: foreground.withValues(alpha: .32),
      minimumSize: const Size(40, 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ).copyWith(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? BorderSide.none
            : BorderSide(color: foreground.withValues(alpha: .55)),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? Colors.transparent
            : foreground.withValues(alpha: .07),
      ),
    );
