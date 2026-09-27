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
  });

  final Board board;
  final ValueChanged<chess.Move> onMove;
  final bool flipped;
  final bool enabled;

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  int? _selected;
  int? _dragFrom;
  Offset? _pointerDown;
  Offset? _dragPosition;
  bool _promoting = false;
  int _generation = 0;
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
        oldWidget.enabled != widget.enabled) {
      _generation++;
      _selected = null;
      _dragFrom = null;
      _dragPosition = null;
      _pointerDown = null;
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

  void _endDrag(double size) {
    final from = _dragFrom;
    final to = _dragPosition == null ? null : _squareAt(_dragPosition!, size);
    setState(() {
      _dragFrom = null;
      _dragPosition = null;
      _pointerDown = null;
    });
    if (!_interactive || from == null || to == null) return;
    final moves = _movesTo(from, to);
    if (moves.isNotEmpty) _submit(moves);
  }

  void _cancelDrag() => setState(() {
    _dragFrom = null;
    _dragPosition = null;
    _pointerDown = null;
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
          final cell = size / 8;
          return Listener(
            // A cancelled, accepted pan can dispatch onPanEnd instead of
            // onPanCancel. Clear its move before the recognizer handles it.
            onPointerCancel: (_) => _cancelDrag(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final square = _squareAt(details.localPosition, size);
                if (square != null) _tap(square);
              },
              onPanDown: (details) => _pointerDown = details.localPosition,
              onPanStart: (details) {
                if (!_interactive) return;
                final square = _squareAt(
                  _pointerDown ?? details.localPosition,
                  size,
                );
                if (square == null || !_ownPiece(square)) return;
                setState(() {
                  _selected = square;
                  _dragFrom = square;
                  _dragPosition = details.localPosition;
                });
              },
              onPanUpdate: (details) {
                if (_dragFrom != null) {
                  setState(() => _dragPosition = details.localPosition);
                }
              },
              onPanEnd: (_) => _endDrag(size),
              onPanCancel: _cancelDrag,
              child: CustomPaint(
                painter: BoardPainter(
                  flipped: widget.flipped,
                  selected: _selected,
                  targets: targets,
                  lastMove: board.lastMove,
                  checkedKing: checkedKing,
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
                    if (_dragFrom != null && _dragPosition != null)
                      Positioned(
                        left: _dragPosition!.dx - cell / 2,
                        top: _dragPosition!.dy - cell / 2,
                        width: cell,
                        height: cell,
                        child: IgnorePointer(
                          child: PieceImage(piece: board.pieceAt(_dragFrom!)!),
                        ),
                      ),
                  ],
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
          child: piece == null || square == _dragFrom
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
  });

  static const lightSquare = Color(0xFFE5EAF0);
  static const darkSquare = Color(0xFF72869B);
  static const ink = Color(0xFF233648);
  final bool flipped;
  final int? selected;
  final Set<int> targets;
  final chess.Move? lastMove;
  final int? checkedKing;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final paint = Paint();
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        final square = flipped ? row * 16 + 7 - col : (7 - row) * 16 + col;
        final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
        final light = (row + col).isEven;
        canvas.drawRect(rect, paint..color = light ? lightSquare : darkSquare);
        if (lastMove?.from == square || lastMove?.to == square) {
          canvas.drawRect(rect, paint..color = const Color(0x80E7BC54));
        }
        if (checkedKing == square) {
          canvas.drawRect(rect, paint..color = const Color(0xDDCE5964));
        }
        if (selected == square) {
          canvas.drawRect(
            rect.deflate(2),
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
        }
        if (targets.contains(square)) {
          canvas.drawCircle(
            rect.center,
            cell * .14,
            paint..color = const Color(0xA0233648),
          );
          canvas.drawCircle(
            rect.center,
            cell * .43,
            Paint()
              ..color = const Color(0xA0233648)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
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
          color: light ? ink : Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) => true;
}
