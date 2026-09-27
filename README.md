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

## AI / Stockfish (M2b)

`StockfishService` uses the pinned `stockfish` 1.8.1 package on Android/iOS and
a shell-free Stockfish subprocess on Windows/Linux/macOS. The pure Dart UCI
parser/command builders live in `lib/engine/uci_protocol.dart`. Package
evaluation, caveats and licensing are recorded in `docs/CHESS_PLAN.md` and
`docs/CREDITS.md`.

```dart
final ai = StockfishService(prefs: prefs);
try {
  final result = await ai.analyzePosition(Fen.initial, difficulty: 5);
  // Exactly one of result.cp / result.mate is non-null.
  // Both are relative to the side to move; mate is signed moves, not cp.
  final moves = result.bestLine; // Immutable, legal UCI principal variation.
  final playedMove = result.bestMove; // May differ from PV[0] at low strength.
} on StockfishException catch (error) {
  // Display error.message; error.cause is diagnostic/local-only.
} finally {
  await ai.dispose();
}
```

`analyzePosition` starts the engine if necessary. `depth: n` replaces the
difficulty's default movetime. One service owns one engine: concurrent starts
share a future, concurrent searches are rejected, and `stop()` cancels pending
work before another session may begin. A timeout destroys the old session so
late bestmoves cannot satisfy a later request. An unconfirmed native shutdown
blocks restart. Invalid positions/options, malformed replies, missing scores,
illegal PVs, EOF and transport errors throw `StockfishException`; they are never
converted to a successful zero evaluation. Mate/stalemate with no legal move
return an empty line, null bestMove, and mate 0/cp 0 respectively.

Observe `service.status` (`ValueListenable<StockfishStatus>`) for lifecycle
changes and persistent `error.message`. Settings now exposes **AI 状态 / 检查 AI**
and displays startup/search failures and unexpected idle exits. It creates its
service lazily and does not load the native engine until the button is pressed.
M3 game integration should own a shared service and await disposal when done;
mobile packages support only one native instance.

The startup and search critical sections write crash phases and clear them on
normal completion/failure. `engine_start` only reports `success` and
`duration_ms`; no FEN, moves, native paths or error text are uploaded.

### Desktop setup and real-engine smoke

Download an official binary for the host CPU and place it at
`engine_assets\stockfish.exe` (Windows) or `engine_assets/stockfish` (Linux/macOS).
Alternatively pass an absolute path to `ProcessStockfishTransport(executablePath: ...)`
via `transportFactory`, or build with `--dart-define=STOCKFISH_EXECUTABLE=<absolute path>`.
The default locator searches `engine_assets` beside/above the app executable
and under the current directory. The child uses its own executable directory;
the app never changes its global working directory or silently downloads code.
On Unix ensure the binary is executable. Desktop packaging must supply the
binary and GPL notices; mobile release builds need the package's build-time
NNUE downloads and platform verification. Web is not supported by this transport.

```powershell
$env:NO_PROXY = 'localhost,127.0.0.1'
$env:STOCKFISH_EXECUTABLE = (Resolve-Path engine_assets\stockfish.exe).Path
flutter test test\engine\stockfish_native_test.dart --reporter expanded
Remove-Item Env:\STOCKFISH_EXECUTABLE
```

The opt-in smoke checks all ten levels, legal moves/PVs, a mate-in-one score,
and stop/restart with a second handshake. Without that environment variable it
is explicitly skipped; ordinary tests inject fake transports/native clients.

## 备份与恢复

设置 → **备份与恢复** 可将本地 PGN 棋谱、教程/谜题完成记录、错题本、
每日题、名局阅读书签和 AI 推荐难度导出为一个 ZIP，通过系统分享面板保存。
备份不加密，可能包含棋谱中的姓名与评注；不含内置题库、诊断日志、
匿名统计开关或隐私同意。分享面板返回不等于云端保存完成，请确认目标位置。

导入先完整校验，再显示棋谱数量、教程/谜题进度与每日记录预览，确认后合并：
教程取较大值；谜题/每日完成 ID 取并集；错题取并集并移除已完成题；
同一名局书签取较大步数，不同名局保留本地书签；备份中的 AI 难度覆盖本地值。
同一天题目清单不一致时明确拒绝整个导入，不丢弃任何完成记录。
棋谱按 PGN `Id` 去重，同 ID 保留本地版本；文件同名但 ID 不同则另存。
新棋谱保存时生成稳定 ID，旧版本无 ID 的棋谱以 `legacy:<原文件名>` 标识，
导入后写入 PGN，即使因同名重命名也可重复导入而不复制。

格式 v1：`manifest.json` 包含 `format: "purechess-backup"`、整数 `version: 1`、
UTC `createdAt`、白名单 `preferences` 与 `records: [{id, file}]`；
棋谱位于 `records/*.pgn`。拒绝非法 PGN、未知版本/进度、缺失或未登记文件、
重复 ID/路径、链接、加密 ZIP、不安全路径和 CRC 错误。
限制：ZIP 64 MiB、单文件解压 8 MiB、总解压 128 MiB、最多 10,000 个条目。
解压使用限流输出，伪造 ZIP 大小也不能绕过限制。

恢复先在应用沙盒内暂存全部内容，再发布文件和设置。写入失败回滚；
未提交的事务保留磁盘日志，下次启动在加载应用状态前回滚；
棋谱保存与恢复在同一 isolate 内串行。`backup_export` / `backup_import`
只记录 `ok`（取消为 false），不发送备份内容。iOS 已有相册、相机、
使用期间定位三项 purpose strings，供文件选择组件的可选能力使用。

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
