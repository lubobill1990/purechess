import 'board.dart';
import 'move.dart';

/// The FEN is the solver's first position, and the UCI line starts with the
/// solver's move. For Lichess CSV input use [PuzzleProblem.fromLichess], which
/// applies the CSV's initial opponent move before constructing the problem.
class PuzzleProblem {
  final String id;
  final String title;
  final String fen;
  final List<Move> line;
  final List<String> themes;
  final int? rating;

  PuzzleProblem({
    required this.id,
    this.title = '',
    required this.fen,
    required List<Move> line,
    List<String> themes = const [],
    this.rating,
  }) : line = List.unmodifiable(line),
       themes = List.unmodifiable(themes) {
    if (line.isEmpty) throw ArgumentError('Puzzle solution must not be empty');
    final board = Board.fromFen(fen);
    for (final move in line) {
      board.play(move);
    }
  }

  factory PuzzleProblem.fromLichess({
    required String id,
    required String fen,
    required String moves,
    String title = '',
    List<String> themes = const [],
    int? rating,
  }) {
    final line = moves.trim().split(RegExp(r'\s+')).map(Move.fromUci).toList();
    if (line.length < 2) {
      throw ArgumentError('Lichess line requires a setup move and a solution');
    }
    final board = Board.fromFen(fen)..play(line.first);
    return PuzzleProblem(
      id: id,
      title: title,
      fen: board.toFen(),
      line: line.sublist(1),
      themes: themes,
      rating: rating,
    );
  }

  Color get playerColor => Board.fromFen(fen).turn;
}

enum PuzzleStatus { playing, solved, failed }

/// A single attempt, mirroring pureweiqi's TsumegoSession. Wrong legal moves
/// mark failure without changing the board. Illegal moves throw and do not
/// consume an attempt. Exact main-line matching is intentional (not an engine).
class PuzzleSession {
  final PuzzleProblem problem;
  late Board _board;
  var _index = 0;
  PuzzleStatus _status = PuzzleStatus.playing;
  Move? _offLineMove;

  PuzzleSession(this.problem) {
    _board = Board.fromFen(problem.fen);
  }

  Board get board => _board.copy();
  Color get playerColor => problem.playerColor;
  PuzzleStatus get status => _status;
  Move? get offLineMove => _offLineMove;
  int get completedPlies => _index;

  Move? hint() => _status == PuzzleStatus.playing ? problem.line[_index] : null;
  int? hintSquare() => hint()?.from;

  /// Returns the automatic opponent reply for animation, if any.
  Move? playUserMove(Move move) {
    if (_status != PuzzleStatus.playing) {
      throw StateError('Puzzle attempt has already ended');
    }
    if (!_board.isLegal(move)) {
      throw IllegalMoveException('Illegal puzzle move: $move');
    }
    if (move != problem.line[_index]) {
      _offLineMove = move;
      _status = PuzzleStatus.failed;
      return null;
    }
    _board.play(move);
    _index++;
    Move? reply;
    if (_index < problem.line.length) {
      reply = problem.line[_index++];
      _board.play(reply);
    }
    if (_index == problem.line.length) _status = PuzzleStatus.solved;
    return reply;
  }

  void reset() {
    _board = Board.fromFen(problem.fen);
    _index = 0;
    _status = PuzzleStatus.playing;
    _offLineMove = null;
  }
}
