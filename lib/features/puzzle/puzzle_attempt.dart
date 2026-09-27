import '../../core/board.dart';
import '../../core/move.dart';
import '../../core/puzzle.dart';
import 'puzzle_catalog.dart';

/// Feature policy around the exact-mainline core session.
class PuzzleAttempt {
  PuzzleAttempt(this.problem) : _session = PuzzleSession(problem);

  final PuzzleProblem problem;
  final PuzzleSession _session;
  Board? _alternativeMate;
  int hintLevel = 0;
  int attempts = 1;
  final Stopwatch elapsed = Stopwatch()..start();

  Board get board => _alternativeMate?.copy() ?? _session.board;
  Color get playerColor => _session.playerColor;
  PuzzleStatus get status =>
      _alternativeMate == null ? _session.status : PuzzleStatus.solved;
  int? get hintSquare => hintLevel == 2 ? _session.hintSquare() : null;
  String get idea => puzzleThemes.entries
      .firstWhere((entry) => problem.themes.contains(entry.key))
      .value
      .hint;

  void revealHint() {
    if (status != PuzzleStatus.playing) {
      throw StateError('Attempt has ended');
    }
    if (hintLevel < 2) hintLevel++;
  }

  void play(Move move) {
    if (status != PuzzleStatus.playing) {
      throw StateError('Attempt has ended');
    }
    // Lichess explicitly allows alternative mating moves in mate-in-one.
    if (problem.themes.contains('mateIn1')) {
      final candidate = _session.board..play(move);
      if (candidate.status == GameStatus.checkmate) {
        _alternativeMate = candidate;
      }
    }
    if (_alternativeMate == null) _session.playUserMove(move);
    hintLevel = 0;
    if (status != PuzzleStatus.playing) elapsed.stop();
  }

  void retry() {
    _session.reset();
    _alternativeMate = null;
    hintLevel = 0;
    attempts++;
    elapsed
      ..reset()
      ..start();
  }
}
