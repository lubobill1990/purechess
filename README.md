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
Leaving/restarting an unsaved game asks for confirmation. Autosave and resume
are now available for both local and AI games (see below); they are separate
from explicitly saving a PGN to the records library.

Named routes live in `lib/app/router.dart`: `/`, `/game`, `/records`, `/settings`.
Game start/end use the existing allowlisted analytics parameters; no moves,
FEN, PGN or file paths are sent to analytics.

## 对局连续性（M5a + M5b）

新对局表单使用 `newGame.color` / `newGame.level` 记住执子颜色和手动难度。
尚未手动选择难度时，每次进入跟随自适应推荐；手动选档后保持用户选择，
“推荐第 N 档”仍独立更新。偏好读取失败使用默认值，写入失败显示提示，
两者均记录 handled error，不阻塞开局。

AI 和双人对弈共用一个 `game.unfinished` 存盘槽（JSON v1）：保存 PGN、
对局模式、AI 颜色/难度、开始时间、已用提示次数及双人待回应的提和状态。
开始新局会替换原断点；每步落子、悔棋、提示/提和状态变更以及
`paused` / `hidden` / `detached` 和页面销毁时保存。写入串行执行，
避免较早的异步保存覆盖后来的清盘。此断点不纳入 ZIP 备份。

首页检测有效存盘后显示 **继续对局**（未完成教程也可访问）。
首页次级入口 **人机对弈** 始终可新建 AI 局，不再从双人确认弹窗叠加开局。
离开未保存的对局可选 **稍后继续** 或 **放弃并离开**；终局、认输、
同意和棋和主动放弃清除断点。双人局终局后悔棋会重新生成未完成断点。
恢复重放完整 PGN 主线，保留悔棋和重复局面判定；轮到 AI 时从恢复的
当前局面自动续走。损坏、非法或版本不符的断点记录 handled error 后
静默丢弃，不弹错误对话框；存储写入失败也记录 handled error。
离开 AI 对局时先冻结会话、完成存盘并等待 AI 关闭，再返回首页，
避免立即续弈时新旧 AI 实例重叠；退出期间迟到的结果不会改写断点。
系统强杀前未完成的偏好写入不能保证落盘，通常可恢复到最近一次成功保存。

终局 **再来一局** 直接开局：AI 沿用本局执子颜色和难度（不采用新推荐、
不回表单），双人继续双人模式。结果区高度保持不变。
成功恢复仅发送 `game_resume`，字段限于 `mode` / `difficulty` /
`move_count`，不重复发送 `game_start`，不发送 PGN、局面或提示内容。

## Daily tactics reminders

Settings include **每日战术题提醒** (off by default) and a 24-hour time picker
(default **20:00**). `dailyReminderSettings` stores enabled/hour/minute together
in SharedPreferences. Only enabling requests notification authorization; denial
leaves the switch off and shows system-settings guidance. Scheduling/storage
failures are visible and retryable. Startup/resume restore scheduling and check
revoked permissions without prompting.

The injectable `ReminderBackend` uses the same dependency constraints as
pureweiqi (`flutter_local_notifications: ^22.3.1`, `timezone: ^0.11.0`).
`flutter_timezone` supplies the device's IANA zone rather than assuming UTC.
One repeating calendar notification (ID 7300) stays below iOS's pending limit;
calendar arithmetic handles DST, and resume refreshes the zone after travel.
Android uses inexact idle-safe scheduling (delivery may be delayed by the OS),
without exact-alarm access, with reboot/update receivers and a retained
monochrome notification icon. iOS uses `UNUserNotificationCenter` authorization
and the AppDelegate delegate; local notifications need **no** invented
Info.plist notification-purpose key, background mode, or push entitlement.
Existing photo/camera/location purpose strings remain intact for release safety.

Taps, including cold launch, open the existing `/puzzles/daily` daily tactics
screen; first-launch privacy consent remains in front. Successful enabled-state
changes emit allowlisted `daily_reminder_toggle` with `on`, respecting the
existing statistics opt-out. Desktop/web explicitly show reminders as unsupported.

Before release, verify permission denial/re-enable, notification taps with the
app terminated, and reboot delivery on Android 13+ and an iOS device/TestFlight.
Windows unit/widget tests do not substitute for signed mobile-device validation.
Local verification (2026-09-28): `flutter analyze` reports zero issues;
`NO_PROXY=localhost,127.0.0.1` + `flutter test` passes 1861 tests, with one existing
opt-in native-engine test skipped. Thirty new tests cover calendar/DST scheduling,
permissions, persistence/rollback, notification adapters, UI and cold/warm routing.
The additional Android debug-build attempt is blocked before app compilation by
the existing `stockfish` 1.8.1 Gradle script's removed `jcenter()` call; it is not
an Android build pass. iOS signing/device delivery remains unverified on Windows.

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
flutter test --exclude-tags golden
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

## Golden 截图回归（Windows）

沿用 pureweiqi 的文件级 `@Tags(['golden'])`、`dart_test.yaml` tag 声明、
固定画布、显式字体加载和 Windows 基线目录。测试位于
`test\goldens\screens_golden_test.dart`，覆盖首页（学习中／已毕业）、新对局
表单、AI／双人中局、谜题做题、教程列表、设置页；浅色与深色各一套，
另覆盖首页续弈入口及 AI／双人终局“再来一局”，浅深色共
**22 张 PNG**，提交在 `test\goldens\windows\`。

固定 1024×1366 逻辑像素、DPR 1、字号缩放 1、Windows 目标平台、日期、
本地进度和推荐难度；禁用动画与统计，使用内存偏好设置、棋谱库和 AI 替身。
对局从固定 FEN 执行两步固定着法，覆盖中局棋子与最后一步高亮；谜题固定为
仓库题库中的 `0030b`，并断言完整 FEN。截图前预加载全部 SVG 棋子，且检查
页面已就绪、主题、关键文案、按钮状态及局面，不把加载中／错误页当作基线。
遥测仅使用测试创建并清理的临时目录，不访问用户数据，不启动真实引擎。

### 字体与平台边界

仓库原先没有中文字体，pureweiqi 的文楷子集仅覆盖少量标题字，因此测试内置
完整 **Noto Sans SC**（`test\goldens\fonts\NotoSansSC.ttf`），不新增应用
依赖或打包资产。来源为 [Google Fonts / Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)，
按 SIL Open Font License 1.1 再分发，原版权声明与完整许可见同目录 `OFL.txt`。
字体原文件未修改，SHA-256：
`a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`。

测试加载 Material Icons、Windows Georgia／Consolas，并显式添加中文回退。
首页局部主题会覆盖外层回退，因此仅在测试中将 Noto Sans SC 同时注册为
`Segoe UI` 和 `Songti SC`，避免 Ahem／缺字方框；不更改业务 UI 的字体设置。
浅色复用 `MyApp` 的配色参数，深色由相同种子色构造；首页仍使用自身的明暗
主题。除首页外，当前应用尚未接入系统深色主题，这里的深色是测试注入，
不代表新增了产品主题切换功能。这些是 widget 回归基线，不替代真机验收。

基线生成环境：**Windows 11（10.0.26200）、Flutter 3.47.2 / Dart 3.13.2**。
系统字体和渲染器版本会影响逐像素比较。不要在 macOS／Linux 上覆盖 Windows
基线；测试会明确报错，而不是静默跳过。默认 Ubuntu CI 执行
`flutter test --exclude-tags golden`；golden 比较在相同 Windows 环境本地执行。
不增加像素容差，也不自动更新基线掩盖差异。

### 本地比较与更新

```powershell
flutter pub get
$env:NO_PROXY = 'localhost,127.0.0.1'
flutter test --tags golden                         # 与已提交基线比较
flutter test --tags golden --update-goldens         # 仅在确认 UI 变更后更新
flutter test --tags golden                         # 再次比较，确认稳定
flutter analyze
flutter test --exclude-tags golden                 # 常规测试，与默认 CI 一致
flutter test                                      # Windows 全量，包含 golden
```

提交前逐张检查 PNG，测试代码与对应基线一起提交。失败差异图位于
`test\goldens\failures\`，已通过该目录的 `.gitignore` 排除；先检查真实 UI、
字体或 Flutter 版本变化，再决定是否更新，不能只因测试失败就重录。
