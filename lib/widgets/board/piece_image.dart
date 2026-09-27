import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/move.dart' as chess;

String pieceName(chess.PieceType type) => switch (type) {
  chess.PieceType.pawn => '兵',
  chess.PieceType.knight => '马',
  chess.PieceType.bishop => '象',
  chess.PieceType.rook => '车',
  chess.PieceType.queen => '后',
  chess.PieceType.king => '王',
};

String colorName(chess.Color color) => color == chess.Color.white ? '白方' : '黑方';

class PieceImage extends StatelessWidget {
  const PieceImage({super.key, required this.piece});

  final chess.Piece piece;

  @override
  Widget build(BuildContext context) {
    final side = piece.color == chess.Color.white ? 'w' : 'b';
    return SvgPicture.asset(
      'assets/pieces/$side${piece.type.letter}.svg',
      excludeFromSemantics: true,
    );
  }
}
