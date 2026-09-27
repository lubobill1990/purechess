import 'move.dart';

/// FEN describes a position, not its repetition history. Castling rights and
/// en-passant targets are retained even when no corresponding move is legal.
class Fen {
  static const initial =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  static FenPosition parse(String text) {
    final fields = text.trim().split(RegExp(r'\s+'));
    if (fields.length != 6) {
      throw FormatException('FEN requires six fields', text);
    }
    final ranks = fields[0].split('/');
    if (ranks.length != 8) {
      throw FormatException('FEN requires eight ranks', text);
    }
    final squares = List<int>.filled(128, 0);
    var whiteKings = 0;
    var blackKings = 0;
    for (var rank = 0; rank < 8; rank++) {
      var file = 0;
      var previousDigit = false;
      for (final symbol in ranks[rank].split('')) {
        final empty = int.tryParse(symbol);
        if (empty != null) {
          if (empty < 1 || empty > 8 || previousDigit) {
            throw FormatException('Invalid FEN empty squares', text);
          }
          file += empty;
          previousDigit = true;
        } else {
          final type = 'PNBRQK'.indexOf(symbol.toUpperCase());
          if (type < 0 || file >= 8) {
            throw FormatException('Invalid FEN piece or rank width', text);
          }
          final code = (type + 1) * (symbol == symbol.toUpperCase() ? 1 : -1);
          squares[(7 - rank) * 16 + file++] = code;
          if (code == 6) whiteKings++;
          if (code == -6) blackKings++;
          if (type == 0 && (rank == 0 || rank == 7)) {
            throw FormatException('Pawn on promotion rank', text);
          }
          previousDigit = false;
        }
      }
      if (file != 8) {
        throw FormatException('Invalid FEN rank width', text);
      }
    }
    if (whiteKings != 1 || blackKings != 1) {
      throw FormatException('FEN requires one king of each color', text);
    }
    if (fields[1] != 'w' && fields[1] != 'b') {
      throw FormatException('Invalid FEN active color', text);
    }
    final side = fields[1] == 'w' ? Color.white : Color.black;
    var rights = 0;
    if (fields[2] != '-') {
      if (!RegExp(r'^K?Q?k?q?$').hasMatch(fields[2]) || fields[2].isEmpty) {
        throw FormatException('Invalid FEN castling rights', text);
      }
      for (var i = 0; i < 4; i++) {
        if (fields[2].contains('KQkq'[i])) rights |= 1 << i;
      }
    }
    int? ep;
    if (fields[3] != '-') {
      ep = parseSquare(fields[3]);
      if ((ep >> 4) != (side == Color.white ? 5 : 2) || squares[ep] != 0) {
        throw FormatException('Invalid FEN en-passant target', text);
      }
    }
    if (!RegExp(r'^\d+$').hasMatch(fields[4]) ||
        !RegExp(r'^\d+$').hasMatch(fields[5])) {
      throw FormatException('Invalid FEN move counters', text);
    }
    final halfmove = int.tryParse(fields[4]);
    final fullmove = int.tryParse(fields[5]);
    if (halfmove == null || fullmove == null || fullmove < 1) {
      throw FormatException('Invalid FEN move counters', text);
    }
    return FenPosition(squares, side, rights, ep, halfmove, fullmove);
  }

  static String generate(FenPosition position) {
    final ranks = <String>[];
    for (var rank = 7; rank >= 0; rank--) {
      final row = StringBuffer();
      var empty = 0;
      for (var file = 0; file < 8; file++) {
        final code = position.squares[rank * 16 + file];
        if (code == 0) {
          empty++;
        } else {
          if (empty > 0) row.write(empty);
          empty = 0;
          final letter = 'PNBRQK'[code.abs() - 1];
          row.write(code > 0 ? letter : letter.toLowerCase());
        }
      }
      if (empty > 0) row.write(empty);
      ranks.add(row.toString());
    }
    var rights = '';
    for (var i = 0; i < 4; i++) {
      if ((position.castlingRights & (1 << i)) != 0) rights += 'KQkq'[i];
    }
    return '${ranks.join('/')} '
        '${position.turn == Color.white ? 'w' : 'b'} '
        '${rights.isEmpty ? '-' : rights} '
        '${position.enPassant == null ? '-' : squareName(position.enPassant!)} '
        '${position.halfmoveClock} ${position.fullmoveNumber}';
  }
}

class FenPosition {
  final List<int> squares;
  final Color turn;
  final int castlingRights;
  final int? enPassant;
  final int halfmoveClock;
  final int fullmoveNumber;

  FenPosition(
    List<int> squares,
    this.turn,
    this.castlingRights,
    this.enPassant,
    this.halfmoveClock,
    this.fullmoveNumber,
  ) : squares = List.unmodifiable(squares);
}
