/// Coordinates use a 0x88 mailbox: a1 = 0, h1 = 7, a8 = 112.
library;

enum Color {
  white,
  black;

  Color get opponent => this == white ? black : white;
  int get sign => this == white ? 1 : -1;
}

enum PieceType {
  pawn,
  knight,
  bishop,
  rook,
  queen,
  king;

  String get letter => 'PNBRQK'[index];
}

class Piece {
  final Color color;
  final PieceType type;

  const Piece(this.color, this.type);

  int get code => color.sign * (type.index + 1);

  static Piece? fromCode(int code) => code == 0
      ? null
      : Piece(
          code > 0 ? Color.white : Color.black,
          PieceType.values[code.abs() - 1],
        );

  @override
  bool operator ==(Object other) =>
      other is Piece && color == other.color && type == other.type;

  @override
  int get hashCode => Object.hash(color, type);
}

bool isSquare(int square) =>
    square >= 0 && square < 128 && (square & 0x88) == 0;

int parseSquare(String text) {
  if (!RegExp(r'^[a-h][1-8]$').hasMatch(text)) {
    throw FormatException('Invalid square: $text');
  }
  return (text.codeUnitAt(1) - 49) * 16 + text.codeUnitAt(0) - 97;
}

String squareName(int square) {
  if (!isSquare(square)) {
    throw ArgumentError.value(square, 'square', 'Not a board square');
  }
  return '${String.fromCharCode(97 + (square & 7))}${(square >> 4) + 1}';
}

class Move {
  final int from;
  final int to;
  final PieceType? promotion;

  const Move(this.from, this.to, {this.promotion});

  factory Move.fromUci(String text) {
    if (!RegExp(r'^[a-h][1-8][a-h][1-8][nbrq]?$').hasMatch(text)) {
      throw FormatException('Invalid UCI move: $text');
    }
    return Move(
      parseSquare(text.substring(0, 2)),
      parseSquare(text.substring(2, 4)),
      promotion: text.length == 5
          ? PieceType.values.firstWhere(
              (type) => type.letter.toLowerCase() == text[4],
            )
          : null,
    );
  }

  String get uci =>
      '${squareName(from)}${squareName(to)}'
      '${promotion?.letter.toLowerCase() ?? ''}';

  @override
  String toString() => uci;

  @override
  bool operator ==(Object other) =>
      other is Move &&
      from == other.from &&
      to == other.to &&
      promotion == other.promotion;

  @override
  int get hashCode => Object.hash(from, to, promotion);
}

class IllegalMoveException implements Exception {
  final String message;
  const IllegalMoveException(this.message);

  @override
  String toString() => 'IllegalMoveException: $message';
}
