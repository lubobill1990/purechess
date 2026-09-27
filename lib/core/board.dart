import 'fen.dart';
import 'move.dart';

enum GameStatus {
  playing,
  checkmate,
  stalemate,
  insufficientMaterial,
  fiftyMoveDraw,
  threefoldRepetition,
}

/// Mutable orthodox-chess position. Public moves are validated; speculative
/// generation/perft uses reversible private moves and never touches history.
class Board {
  final List<int> _squares;
  Color _turn;
  int _rights;
  int? _ep;
  int _halfmove;
  int _fullmove;
  final List<int> _kings;
  final List<_Undo> _history = [];
  final List<BigInt> _keys = [];
  final Map<BigInt, int> _repetitions = {};

  factory Board() => Board.fromFen(Fen.initial);

  factory Board.fromFen(String fen) => Board._(Fen.parse(fen));

  Board._(FenPosition position)
    : _squares = List.of(position.squares),
      _turn = position.turn,
      _rights = position.castlingRights,
      _ep = position.enPassant,
      _halfmove = position.halfmoveClock,
      _fullmove = position.fullmoveNumber,
      _kings = [position.squares.indexOf(6), position.squares.indexOf(-6)] {
    final key = zobristHash;
    _keys.add(key);
    _repetitions[key] = 1;
  }

  Color get turn => _turn;
  int get castlingRights => _rights;
  int? get enPassant => _ep;
  int get halfmoveClock => _halfmove;
  int get fullmoveNumber => _fullmove;
  int get plyCount => _history.length;
  Move? get lastMove => _history.isEmpty ? null : _history.last.move;

  FenPosition get position =>
      FenPosition(_squares, _turn, _rights, _ep, _halfmove, _fullmove);

  String toFen() => Fen.generate(position);

  Board copy() {
    final result = Board._(position);
    result._history.addAll(_history);
    result._keys
      ..clear()
      ..addAll(_keys);
    result._repetitions
      ..clear()
      ..addAll(_repetitions);
    return result;
  }

  Piece? pieceAt(int square) {
    if (!isSquare(square)) {
      throw ArgumentError.value(square, 'square', 'Not a board square');
    }
    return Piece.fromCode(_squares[square]);
  }

  bool isAttacked(int square, Color by) {
    if (!isSquare(square)) {
      throw ArgumentError.value(square, 'square', 'Not a board square');
    }
    return _attacked(square, by.sign);
  }

  static const _knight = [-33, -31, -18, -14, 14, 18, 31, 33];
  static const _bishop = [-17, -15, 15, 17];
  static const _rook = [-16, -1, 1, 16];
  static const _king = [-17, -16, -15, -1, 1, 15, 16, 17];
  static const _promotions = [
    PieceType.queen,
    PieceType.rook,
    PieceType.bishop,
    PieceType.knight,
  ];

  bool _attacked(int square, int by) {
    for (final offset in [15 * by, 17 * by]) {
      final from = square - offset;
      if ((from & 0x88) == 0 && _squares[from] == by) return true;
    }
    for (final offset in _knight) {
      final from = square + offset;
      if ((from & 0x88) == 0 && _squares[from] == by * 2) return true;
    }
    for (final offset in _king) {
      var from = square + offset;
      var distance = 1;
      while ((from & 0x88) == 0) {
        final piece = _squares[from];
        if (piece != 0) {
          if (piece * by > 0) {
            final type = piece.abs();
            final diagonal = offset.abs() == 15 || offset.abs() == 17;
            if (type == 5 ||
                (type == 6 && distance == 1) ||
                (diagonal ? type == 3 : type == 4)) {
              return true;
            }
          }
          break;
        }
        from += offset;
        distance++;
      }
    }
    return false;
  }

  bool get inCheck => _attacked(_kings[_turn.index], -_turn.sign);

  List<Move> _pseudoMoves() {
    final moves = <Move>[];
    final sign = _turn.sign;
    for (var from = 0; from < 128; from++) {
      if ((from & 0x88) != 0) {
        from += 7;
        continue;
      }
      final piece = _squares[from];
      if (piece * sign <= 0) continue;
      final type = piece.abs();
      if (type == 1) {
        final step = 16 * sign;
        final one = from + step;
        if ((one & 0x88) == 0 && _squares[one] == 0) {
          _addPawn(moves, from, one);
          final two = one + step;
          if ((from >> 4) == (sign == 1 ? 1 : 6) && _squares[two] == 0) {
            moves.add(Move(from, two));
          }
        }
        for (final to in [from + step - 1, from + step + 1]) {
          if ((to & 0x88) != 0) continue;
          final target = _squares[to];
          if ((target * sign < 0 && target.abs() != 6) ||
              (to == _ep && target == 0 && _squares[to - step] == -sign)) {
            _addPawn(moves, from, to);
          }
        }
        continue;
      }
      final offsets = switch (type) {
        2 => _knight,
        3 => _bishop,
        4 => _rook,
        _ => _king,
      };
      for (final offset in offsets) {
        var to = from + offset;
        while ((to & 0x88) == 0) {
          final target = _squares[to];
          if (target * sign > 0 || target.abs() == 6) break;
          moves.add(Move(from, to));
          if (target != 0 || type == 2 || type == 6) break;
          to += offset;
        }
      }
    }
    final base = sign == 1 ? 0 : 112;
    final shift = sign == 1 ? 0 : 2;
    if (_squares[base + 4] == sign * 6 && !_attacked(base + 4, -sign)) {
      if ((_rights & (1 << shift)) != 0 &&
          _squares[base + 7] == sign * 4 &&
          _squares[base + 5] == 0 &&
          _squares[base + 6] == 0 &&
          !_attacked(base + 5, -sign) &&
          !_attacked(base + 6, -sign)) {
        moves.add(Move(base + 4, base + 6));
      }
      if ((_rights & (2 << shift)) != 0 &&
          _squares[base] == sign * 4 &&
          _squares[base + 1] == 0 &&
          _squares[base + 2] == 0 &&
          _squares[base + 3] == 0 &&
          !_attacked(base + 3, -sign) &&
          !_attacked(base + 2, -sign)) {
        moves.add(Move(base + 4, base + 2));
      }
    }
    return moves;
  }

  void _addPawn(List<Move> moves, int from, int to) {
    if ((to >> 4) == 0 || (to >> 4) == 7) {
      for (final promotion in _promotions) {
        moves.add(Move(from, to, promotion: promotion));
      }
    } else {
      moves.add(Move(from, to));
    }
  }

  List<Move> legalMoves() {
    final result = <Move>[];
    final color = _turn;
    for (final move in _pseudoMoves()) {
      final undo = _make(move);
      if (!_attacked(_kings[color.index], -color.sign)) result.add(move);
      _unmake(undo);
    }
    return result;
  }

  bool isLegal(Move move) => legalMoves().contains(move);

  void play(Move move) {
    if (!isLegal(move)) {
      throw IllegalMoveException('Illegal move $move in ${toFen()}');
    }
    _history.add(_make(move));
    final key = zobristHash;
    _keys.add(key);
    _repetitions.update(key, (count) => count + 1, ifAbsent: () => 1);
  }

  Move playUci(String text) {
    final move = Move.fromUci(text);
    play(move);
    return move;
  }

  Move playSan(String text) {
    final move = parseSan(text);
    play(move);
    return move;
  }

  Move undo() {
    if (_history.isEmpty) throw StateError('No move to undo');
    final key = _keys.removeLast();
    final count = _repetitions[key]!;
    if (count == 1) {
      _repetitions.remove(key);
    } else {
      _repetitions[key] = count - 1;
    }
    final previous = _history.removeLast();
    _unmake(previous);
    return previous.move;
  }

  _Undo _make(Move move) {
    final piece = _squares[move.from];
    final pawn = piece.abs() == 1;
    final king = piece.abs() == 6;
    final captureSquare = pawn && move.to == _ep && _squares[move.to] == 0
        ? move.to - 16 * _turn.sign
        : move.to;
    final captured = _squares[captureSquare];
    final castle = king && (move.to - move.from).abs() == 2;
    final rookFrom = castle
        ? (move.to > move.from ? move.from + 3 : move.from - 4)
        : -1;
    final rookTo = castle ? (move.from + move.to) ~/ 2 : -1;
    final undo = _Undo(
      move,
      piece,
      captureSquare,
      captured,
      rookFrom,
      rookTo,
      _rights,
      _ep,
      _halfmove,
      _fullmove,
      _kings[_turn.index],
    );
    _squares[move.from] = 0;
    _squares[captureSquare] = 0;
    _squares[move.to] = move.promotion == null
        ? piece
        : (move.promotion!.index + 1) * _turn.sign;
    if (castle) {
      _squares[rookTo] = _squares[rookFrom];
      _squares[rookFrom] = 0;
    }
    if (king) {
      _kings[_turn.index] = move.to;
      _rights &= _turn == Color.white ? 12 : 3;
    }
    // Visiting a rook's home square also revokes rights when it is captured.
    for (final square in [move.from, move.to]) {
      _rights &= switch (square) {
        7 => 14,
        0 => 13,
        119 => 11,
        112 => 7,
        _ => 15,
      };
    }
    _ep = pawn && (move.to - move.from).abs() == 32
        ? (move.from + move.to) ~/ 2
        : null;
    _halfmove = pawn || captured != 0 ? 0 : _halfmove + 1;
    if (_turn == Color.black) _fullmove++;
    _turn = _turn.opponent;
    return undo;
  }

  void _unmake(_Undo undo) {
    _turn = _turn.opponent;
    _squares[undo.move.from] = undo.piece;
    _squares[undo.move.to] = 0;
    _squares[undo.captureSquare] = undo.captured;
    if (undo.rookFrom >= 0) {
      _squares[undo.rookFrom] = _squares[undo.rookTo];
      _squares[undo.rookTo] = 0;
    }
    _rights = undo.rights;
    _ep = undo.ep;
    _halfmove = undo.halfmove;
    _fullmove = undo.fullmove;
    _kings[_turn.index] = undo.kingSquare;
  }

  /// Counts legal leaf nodes, deliberately ignoring draw claims.
  int perft(int depth) {
    if (depth < 0) throw ArgumentError.value(depth, 'depth', 'Must be >= 0');
    return _perft(depth);
  }

  int _perft(int depth) {
    if (depth == 0) return 1;
    var nodes = 0;
    final color = _turn;
    for (final move in _pseudoMoves()) {
      final undo = _make(move);
      if (!_attacked(_kings[color.index], -color.sign)) {
        nodes += depth == 1 ? 1 : _perft(depth - 1);
      }
      _unmake(undo);
    }
    return nodes;
  }

  String san(Move move) {
    final legal = legalMoves();
    if (!legal.contains(move)) {
      throw IllegalMoveException('Cannot format illegal move $move');
    }
    return _san(move, legal);
  }

  String _san(Move move, List<Move> legal) {
    final type = _squares[move.from].abs();
    final capture = _squares[move.to] != 0 || (type == 1 && move.to == _ep);
    var text = '';
    if (type == 6 && (move.to - move.from).abs() == 2) {
      text = move.to > move.from ? 'O-O' : 'O-O-O';
    } else {
      if (type != 1) {
        text = 'PNBRQK'[type - 1];
        final others = legal.where(
          (other) =>
              other.from != move.from &&
              other.to == move.to &&
              _squares[other.from].abs() == type,
        );
        if (others.isNotEmpty) {
          if (others.every((other) => (other.from & 7) != (move.from & 7))) {
            text += squareName(move.from)[0];
          } else if (others.every(
            (other) => (other.from >> 4) != (move.from >> 4),
          )) {
            text += squareName(move.from)[1];
          } else {
            text += squareName(move.from);
          }
        }
      } else if (capture) {
        text += squareName(move.from)[0];
      }
      if (capture) text += 'x';
      text += squareName(move.to);
      if (move.promotion != null) text += '=${move.promotion!.letter}';
    }
    final undo = _make(move);
    if (inCheck) text += legalMoves().isEmpty ? '#' : '+';
    _unmake(undo);
    return text;
  }

  /// Accepts canonical SAN, zero-spelled castling, optional check suffixes and
  /// trailing annotation glyphs. Ambiguous or incorrect captures are rejected.
  Move parseSan(String text) {
    var normalized = text.trim().replaceAll('0', 'O');
    normalized = normalized.replaceFirst(RegExp(r'[!?]+$'), '');
    final suffix = RegExp(r'[+#]$').firstMatch(normalized)?.group(0);
    final body = normalized.replaceFirst(RegExp(r'[+#]$'), '');
    final legal = legalMoves();
    final matches = <Move>[];
    for (final move in legal) {
      final candidate = _san(move, legal);
      if (candidate.replaceFirst(RegExp(r'[+#]$'), '') == body &&
          (suffix == null || candidate.endsWith(suffix))) {
        matches.add(move);
      }
    }
    if (matches.length != 1) {
      throw FormatException('Illegal or ambiguous SAN: $text', text);
    }
    return matches.single;
  }

  /// Stable 64-bit Zobrist key (BigInt also preserves all bits on Dart web).
  /// FIDE repetition compares EP only when a *legal* EP capture exists.
  BigInt get zobristHash {
    var key = BigInt.zero;
    for (var square = 0; square < 128; square++) {
      if ((square & 0x88) != 0) {
        square += 7;
        continue;
      }
      final code = _squares[square];
      if (code == 0) continue;
      final piece = code > 0 ? code - 1 : 6 - code - 1;
      key ^= _zobrist[piece * 64 + (square >> 4) * 8 + (square & 7)];
    }
    if (_turn == Color.black) key ^= _zobrist[768];
    for (var bit = 0; bit < 4; bit++) {
      if ((_rights & (1 << bit)) != 0) key ^= _zobrist[769 + bit];
    }
    if (_ep != null && _hasLegalEnPassant()) {
      key ^= _zobrist[773 + (_ep! & 7)];
    }
    return key;
  }

  bool _hasLegalEnPassant() {
    final target = _ep!;
    final color = _turn;
    final step = 16 * color.sign;
    if (_squares[target] != 0 || _squares[target - step] != -color.sign) {
      return false;
    }
    for (final from in [target - step - 1, target - step + 1]) {
      if ((from & 0x88) != 0 || _squares[from] != color.sign) continue;
      final undo = _make(Move(from, target));
      final legal = !_attacked(_kings[color.index], -color.sign);
      _unmake(undo);
      if (legal) return true;
    }
    return false;
  }

  int get repetitionCount => _repetitions[_keys.last]!;
  bool get isThreefoldRepetition => repetitionCount >= 3;
  bool get isFiftyMoveDraw => _halfmove >= 100;

  bool get isInsufficientMaterial {
    var knights = 0;
    final bishops = <int>[];
    for (var square = 0; square < 128; square++) {
      if ((square & 0x88) != 0) {
        square += 7;
        continue;
      }
      switch (_squares[square].abs()) {
        case 1:
        case 4:
        case 5:
          return false;
        case 2:
          knights++;
        case 3:
          bishops.add(((square >> 4) + (square & 7)) & 1);
      }
    }
    if (bishops.isEmpty) return knights <= 1;
    return knights == 0 && bishops.every((color) => color == bishops.first);
  }

  /// Claimable 50-move/threefold draws are surfaced to the application; play()
  /// remains available for analysis and PGN replay after a claim is available.
  GameStatus get status {
    if (legalMoves().isEmpty) {
      return inCheck ? GameStatus.checkmate : GameStatus.stalemate;
    }
    if (isInsufficientMaterial) return GameStatus.insufficientMaterial;
    if (isFiftyMoveDraw) return GameStatus.fiftyMoveDraw;
    if (isThreefoldRepetition) return GameStatus.threefoldRepetition;
    return GameStatus.playing;
  }

  Color? get winner => status == GameStatus.checkmate ? _turn.opponent : null;
}

class _Undo {
  final Move move;
  final int piece;
  final int captureSquare;
  final int captured;
  final int rookFrom;
  final int rookTo;
  final int rights;
  final int? ep;
  final int halfmove;
  final int fullmove;
  final int kingSquare;

  const _Undo(
    this.move,
    this.piece,
    this.captureSquare,
    this.captured,
    this.rookFrom,
    this.rookTo,
    this.rights,
    this.ep,
    this.halfmove,
    this.fullmove,
    this.kingSquare,
  );
}

final List<BigInt> _zobrist = () {
  final mask = (BigInt.one << 64) - BigInt.one;
  var seed = BigInt.parse('9e3779b97f4a7c15', radix: 16);
  return List<BigInt>.generate(781, (_) {
    seed ^= (seed << 13) & mask;
    seed ^= seed >> 7;
    seed ^= (seed << 17) & mask;
    return seed;
  }, growable: false);
}();
