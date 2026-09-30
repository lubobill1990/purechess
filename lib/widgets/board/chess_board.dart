import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/board.dart';
import '../../core/move.dart' as chess;
import 'piece_image.dart';

/// A controlled board: only the parent commits a move to the rules engine.
class ChessBoard extends StatefulWidget {
  const ChessBoard({
    super.key,
    required this.board,
    required this.onMove,
    this.flipped = false,
    this.enabled = true,
    this.fingerOffset = true,
    this.flipFingerOffset = false,
  });

  final Board board;
  final ValueChanged<chess.Move> onMove;
  final bool flipped;
  final bool enabled;

  /// Lift touch previews 1.5 cells; ease back at the near edge to keep it reachable.
  final bool fingerOffset;

  /// The opposite seat aims below the finger, independent of board orientation.
  final bool flipFingerOffset;

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  int? _selected;
  int? _pointer;
  int? _pressedSquare;
  Offset? _pointerDown;
  int? _aim;
  bool _touch = false;
  bool _dragging = false;
  bool _promoting = false;
  int _generation = 0;
  double? _size;
  late String _fen;

  @override
  void initState() {
    super.initState();
    _fen = widget.board.toFen();
  }

  @override
  void didUpdateWidget(ChessBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fen = widget.board.toFen();
    if (_fen != fen ||
        oldWidget.flipped != widget.flipped ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.fingerOffset != widget.fingerOffset ||
        oldWidget.flipFingerOffset != widget.flipFingerOffset) {
      _generation++;
      _selected = null;
      _clearPointer();
    }
    _fen = fen;
  }

  bool get _interactive => widget.enabled && !_promoting;

  int? _squareAt(Offset point, double size) {
    if (point.dx < 0 || point.dy < 0 || point.dx >= size || point.dy >= size) {
      return null;
    }
    return _square(
      (point.dy * 8 / size).floor(),
      (point.dx * 8 / size).floor(),
    );
  }

  int _square(int row, int column) =>
      widget.flipped ? row * 16 + 7 - column : (7 - row) * 16 + column;

  bool _ownPiece(int square) =>
      widget.board.pieceAt(square)?.color == widget.board.turn;

  void _tap(int square) {
    if (!_interactive) return;
    if (_selected != null && _selected != square) {
      final moves = _movesTo(_selected!, square);
      if (moves.isNotEmpty) {
        _submit(moves);
        return;
      }
    }
    setState(() {
      _selected = _selected == square || !_ownPiece(square) ? null : square;
    });
  }

  List<chess.Move> _movesTo(int from, int to) => widget.board
      .legalMoves()
      .where((move) => move.from == from && move.to == to)
      .toList();

  Future<void> _submit(List<chess.Move> moves) async {
    final generation = _generation;
    var move = moves.first;
    if (move.promotion != null) {
      setState(() => _promoting = true);
      final promotion = await showDialog<chess.PieceType>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择升变棋子'),
          children: [
            for (final candidate in moves)
              SimpleDialogOption(
                key: ValueKey('promotion-${candidate.promotion!.name}'),
                onPressed: () => Navigator.pop(context, candidate.promotion),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: PieceImage(
                        piece: chess.Piece(
                          widget.board.turn,
                          candidate.promotion!,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(pieceName(candidate.promotion!)),
                  ],
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _promoting = false);
      if (promotion == null) return;
      move = moves.firstWhere((move) => move.promotion == promotion);
    }
    if (!mounted || generation != _generation || !widget.enabled) return;
    setState(() => _selected = null);
    widget.onMove(move);
  }

  void _clearPointer() {
    _pointer = null;
    _pressedSquare = null;
    _pointerDown = null;
    _aim = null;
    _dragging = false;
  }

  void _updateAim(Offset local, double size) {
    final lift = _touch && widget.fingerOffset
        ? math.min(
            size / 8 * 1.5,
            widget.flipFingerOffset ? local.dy : size - local.dy,
          )
        : 0.0;
    // Leaving the physical board cancels even if the lifted aim is still inside.
    _aim = _squareAt(local, size) == null
        ? null
        : _squareAt(
            local - Offset(0, lift * (widget.flipFingerOffset ? -1 : 1)),
            size,
          );
  }

  void _down(PointerDownEvent event, double size) {
    if (!_interactive || _pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    setState(() {
      _pointer = event.pointer;
      _touch = event.kind == PointerDeviceKind.touch;
      _pointerDown = event.localPosition;
      _pressedSquare = _squareAt(event.localPosition, size);
      if (_touch && _pressedSquare != null && _ownPiece(_pressedSquare!)) {
        _selected = _pressedSquare;
      }
      _updateAim(event.localPosition, size);
    });
  }

  void _move(PointerMoveEvent event, double size) {
    if (event.pointer != _pointer || !_interactive) return;
    setState(() {
      if ((event.localPosition - _pointerDown!).distance > kTouchSlop) {
        _dragging = true;
        if (!_touch && _pressedSquare != null && _ownPiece(_pressedSquare!)) {
          _selected = _pressedSquare;
        }
      }
      _updateAim(event.localPosition, size);
    });
  }

  void _up(PointerUpEvent event, double size) {
    if (event.pointer != _pointer || !_interactive) return;
    _updateAim(event.localPosition, size);
    final from = _selected;
    final to = _aim;
    final click = !_touch && !_dragging;
    setState(() {
      _clearPointer();
      if (!click) _selected = null;
    });
    if (click) {
      if (to != null) _tap(to);
      return;
    }
    if (from == null || to == null) return;
    final moves = _movesTo(from, to);
    if (moves.isNotEmpty) _submit(moves);
  }

  void _cancel() => setState(() {
    if (_pointer != null && _touch) _selected = null;
    _clearPointer();
  });

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final targets = _selected == null
        ? <int>{}
        : board
              .legalMoves()
              .where((move) => move.from == _selected)
              .map((move) => move.to)
              .toSet();
    int? checkedKing;
    if (board.inCheck) {
      for (var row = 0; row < 8; row++) {
        for (var col = 0; col < 8; col++) {
          final square = row * 16 + col;
          if (board.pieceAt(square) ==
              chess.Piece(board.turn, chess.PieceType.king)) {
            checkedKing = square;
          }
        }
      }
    }
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          if (_size != null && _size != size) {
            _generation++;
            _selected = null;
            _clearPointer();
          }
          _size = size;
          final cell = size / 8;
          final aimRow = _aim == null
              ? 0
              : widget.flipped
              ? _aim! >> 4
              : 7 - (_aim! >> 4);
          final aimCol = _aim == null
              ? 0
              : widget.flipped
              ? 7 - (_aim! & 7)
              : _aim! & 7;
          return MouseRegion(
            onHover: (event) {
              if (!_interactive || _pointer != null) return;
              setState(() {
                _touch = false;
                _updateAim(event.localPosition, size);
              });
            },
            onExit: (_) {
              if (_pointer == null) _cancel();
            },
            child: Listener(
              onPointerDown: (event) => _down(event, size),
              onPointerMove: (event) => _move(event, size),
              onPointerUp: (event) => _up(event, size),
              onPointerCancel: (event) {
                if (event.pointer == _pointer) _cancel();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Claim board drags before a surrounding page can scroll.
                onPanStart: _interactive ? (_) {} : null,
                child: CustomPaint(
                  painter: BoardPainter(
                    dark: Theme.of(context).brightness == Brightness.dark,
                    flipped: widget.flipped,
                    selected: _selected,
                    targets: targets,
                    lastMove: board.lastMove,
                    checkedKing: checkedKing,
                    aim: _aim,
                    aimLegal: targets.contains(_aim),
                  ),
                  child: Stack(
                    children: [
                      for (var row = 0; row < 8; row++)
                        for (var col = 0; col < 8; col++)
                          Positioned(
                            left: col * cell,
                            top: row * cell,
                            width: cell,
                            height: cell,
                            child: _cell(
                              _square(row, col),
                              cell,
                              targets,
                              checkedKing,
                            ),
                          ),
                      if (_aim != null &&
                          _selected != null &&
                          _pointer != null &&
                          (_touch || _dragging))
                        Positioned(
                          left: aimCol * cell,
                          top: aimRow * cell,
                          width: cell,
                          height: cell,
                          child: IgnorePointer(
                            child: Opacity(
                              key: const ValueKey('board-aim-ghost'),
                              opacity: .65,
                              child: PieceImage(
                                piece: board.pieceAt(_selected!)!,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cell(int square, double size, Set<int> targets, int? checkedKing) {
    final piece = widget.board.pieceAt(square);
    final name = chess.squareName(square);
    return Semantics(
      key: ValueKey('square-$name'),
      button: widget.enabled,
      selected: square == _selected,
      label:
          '$name ${piece == null ? '空格' : '${colorName(piece.color)}${pieceName(piece.type)}'}'
          '${targets.contains(square) ? ' 合法着点' : ''}'
          '${checkedKing == square ? ' 将军' : ''}',
      onTap: _interactive ? () => _tap(square) : null,
      child: ColoredBox(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(size * .09),
          child: piece == null
              ? const SizedBox.expand()
              : PieceImage(piece: piece),
        ),
      ),
    );
  }
}

class BoardPainter extends CustomPainter {
  const BoardPainter({
    required this.flipped,
    required this.selected,
    required this.targets,
    required this.lastMove,
    required this.checkedKing,
    this.dark = false,
    this.aim,
    this.aimLegal = false,
  });

  static const lightSquare = Color(0xFFE8D5AD);
  static const darkSquare = Color(0xFF88613D);
  static const nightLightSquare = Color(0xFFBCA27C);
  static const nightDarkSquare = Color(0xFF67492E);
  static const ink = Color(0xFF352412);
  static const ivory = Color(0xFFFFEDC7);
  static const lastMoveTint = Color(0x66EBC05F);
  static const checkTint = Color(0xDDCE5964);
  final bool dark;
  final bool flipped;
  final int? selected;
  final Set<int> targets;
  final chess.Move? lastMove;
  final int? checkedKing;
  final int? aim;
  final bool aimLegal;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final paint = Paint();
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        final square = flipped ? row * 16 + 7 - col : (7 - row) * 16 + col;
        final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
        final light = (row + col).isEven;
        canvas.drawRect(
          rect,
          paint
            ..color = light
                ? (dark ? nightLightSquare : lightSquare)
                : (dark ? nightDarkSquare : darkSquare),
        );
        if (lastMove?.from == square || lastMove?.to == square) {
          canvas.drawRect(rect, paint..color = lastMoveTint);
        }
        if (checkedKing == square) {
          canvas.drawRect(rect, paint..color = checkTint);
        }
        if (selected == square) {
          canvas.drawRect(
            rect.deflate(2),
            Paint()
              ..color = light ? ink : ivory
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
        }
        if (targets.contains(square)) {
          canvas.drawCircle(
            rect.center,
            cell * .14,
            paint..color = light ? ink : ivory,
          );
          canvas.drawCircle(
            rect.center,
            cell * .43,
            Paint()
              ..color = light ? ink : ivory
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
        if (aim == square) {
          canvas.drawRect(
            rect.deflate(3),
            Paint()
              ..color = aimLegal ? ivory : checkTint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5,
          );
          canvas.drawRect(
            rect.deflate(6),
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
        final name = chess.squareName(square);
        if (col == 0) {
          _label(
            canvas,
            name[1],
            rect.topLeft + const Offset(3, 1),
            cell,
            light,
          );
        }
        if (row == 7) {
          _label(
            canvas,
            name[0],
            Offset(rect.right - cell * .19, rect.bottom - cell * .23),
            cell,
            light,
          );
        }
      }
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset offset,
    double cell,
    bool light,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: cell * .19,
          fontWeight: FontWeight.w600,
          color: light ? ink : ivory,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) => true;
}

/// A two-tone outline remains visible over both wood squares and pieces.
ShapeDecoration boardHintDecoration({bool circle = false}) {
  OutlinedBorder border(Color color, double width) => circle
      ? CircleBorder(
          side: BorderSide(color: color, width: width),
        )
      : RoundedRectangleBorder(
          side: BorderSide(color: color, width: width),
        );
  return ShapeDecoration(
    shape: border(BoardPainter.ink, 1.5) + border(BoardPainter.ivory, 3),
  );
}
