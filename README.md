# purechess

An international-chess learning app. The M1 rules core is implemented in pure
Dart, with no Flutter imports or third-party chess dependencies.

## Local two-player chess (M2a)

The home screen opens **双人对弈**, **我的棋谱**, and the existing privacy settings.
The slate-blue board supports tap-to-select/tap-to-move and direct dragging,
legal destinations, last-move and check highlights, coordinates, and a flipped
view. Promotion always asks for queen/rook/bishop/knight; cancel leaves the
position unchanged. SVG pieces are bundled for offline use; see
[asset credits and licensing](docs/CREDITS.md).

Black's controls stay at the top, rotated 180 degrees toward the opposite seat;
white's controls stay below. Flipping changes the board view, not ownership of
the controls. Only the active player can resign or offer a draw. Resignation
requires confirmation; a draw offer pauses moves until the other player's bar
accepts or declines. Both sides can undo one half-move, including after a
finished game; undo removes that continuation from the saved main line.

`lib/features/game/game_session.dart` is UI-independent and uses the existing
core for all move validation. Local play **automatically adjudicates** threefold
repetition and the 50-move rule, in addition to mate, stalemate and insufficient
material. This is an explicit local-mode policy, not a change to the core's
claimable-draw behavior. Mate/stalemate retain priority. Resignation and agreed
draws also set the PGN result. Status and save feedback share a fixed-height
72-pixel area so they never push the board.

**保存棋谱** explicitly saves a snapshot (unfinished games have result `*`) to
`<application documents>/purechess/records/*.pgn`. The repository follows the
pureweiqi local-files pattern, without adding a state-management dependency:
`open`, `list`, `read`, `save`. Saves use sanitized names, collision suffixes and
flushed temporary files followed by rename; existing records are not overwritten.
I/O failures remain visible and retryable. The initial library lists saved PGNs
and opens selectable PGN text; graphical replay belongs to a later milestone.
Leaving/restarting an unsaved game asks for confirmation. There is no implicit
autosave or crash-resume in this milestone.

Named routes live in `lib/app/router.dart`: `/`, `/game`, `/records`, `/settings`.
Game start/end use the existing allowlisted analytics parameters; no moves,
FEN, PGN or file paths are sent to analytics.

## Rules core

| File | Responsibility |
| --- | --- |
| `lib/core/move.dart` | Colors, pieces, 0x88 coordinates, UCI moves |
| `lib/core/board.dart` | Legal moves, attacks, castling, en passant, promotion, SAN, undo, outcomes, Zobrist repetition, perft |
| `lib/core/fen.dart` | Six-field FEN parsing and generation |
| `lib/core/game_tree.dart` | Validated variation tree and replay/editing cursor |
| `lib/core/pgn.dart` | PGN collections, tags, comments, NAGs, recursive variations and results |
| `lib/core/puzzle.dart` | Validated FEN/UCI solutions, hints, automatic replies and attempt state |

```dart
import 'package:purechess/core/board.dart';
import 'package:purechess/core/game_tree.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/pgn.dart';

void main() {
  final board = Board();
  final move = Move.fromUci('e2e4');
  assert(board.san(move) == 'e4');
  board.play(move);
  board.playSan('e5');
  board.undo();

  final record = Pgn.parse('1.e4 (1.d4 d5) e5 *');
  final cursor = GameCursor(record);
  cursor.forward(variation: 1);
  assert(cursor.current.move!.uci == 'd2d4');
  final exported = Pgn.generate(record);
  assert(Pgn.parse(exported).root.children.length == 2);
}
```

Squares are mailbox integers (`a1 = 0`, `h1 = 7`, `a8 = 112`); use
`parseSquare`/`squareName` rather than assuming a contiguous 0..63 index.
`Board` is mutable, `copy()` preserves undo/repetition history, and
`position.squares` is an immutable snapshot. Tree and puzzle board accessors
return isolated positions. Illegal moves throw `IllegalMoveException`;
malformed FEN, SAN and PGN throw `FormatException`.

FEN validation is structural, not a proof that the position is reachable.
Castling flags never override king/rook placement, attack or path checks.
FEN retains the specified en-passant target even when uncapturable, whereas
the 64-bit Zobrist repetition key includes it only if a **legal** capture exists.
Importing FEN cannot recover repetition history; tree replay and board copies do.
BigInt keys preserve all 64 bits on native Dart and Dart web.

`status` prioritizes mate/stalemate, then insufficient material, then claimable
50-move/threefold draws. The latter are exposed for the application to claim;
they do not prevent analysis/replay moves. Two knights are not automatically
insufficient material: inability to force mate is not the same as impossibility
of any legal mating sequence. `perft` ignores draw claims.

PGN export preserves tags and annotation content while normalizing whitespace,
move numbers, zero-spelled castling and symbolic NAGs. The first child is the
main line. Node `comments` follow a move; `startingComments` precede its SAN
(after the move number), including when a variation is promoted. Missing final
results on fragments become `*`; mismatched header/movetext results and illegal
branches are rejected. Brace and semicolon comments are accepted. Authored
multiline comments containing `}` cannot be represented in standard PGN and
are rejected rather than silently altered.

Puzzle FENs normally start on the solver's turn. `PuzzleProblem.fromLichess`
applies the CSV line's first, opponent setup move before starting the session.
Solutions are exact UCI main lines, including the promotion choice; alternate
engine-equivalent moves are not implicitly accepted. Wrong legal moves fail an
attempt without changing the board; illegal moves throw without consuming it.

## Validation (PowerShell)

```powershell
$env:NO_PROXY = 'localhost,127.0.0.1'
flutter pub get
flutter analyze
flutter test
dart run tool\perft.dart
```

M2a-only tests: `flutter test test\widgets test\features test\widget_test.dart`.
These cover both input modes/orientations, cancelled drags and promotions, all
four promotions, special moves, turn guards, terminal outcomes, undo, persistence
and save errors, navigation, and phone/landscape/tablet layout bounds.

The standalone Dart benchmark checks all six standard
[Chess Programming Wiki perft positions](https://www.chessprogramming.org/Perft_Results):
startpos/position 3 through depth 5, KiwiPete/positions 4-6 through depth 4.
Every depth also has an exact `expect` assertion in `test/core/perft_test.dart`.
The remaining core tests cover special moves, outcomes, SAN ambiguity, FEN/PGN
round trips, variation editing, puzzles and deterministic make/undo invariants.
