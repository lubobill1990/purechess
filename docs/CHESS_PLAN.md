# 纯弈国象（purechess）项目计划

> 方法论完全继承 pureweiqi（F:\weiqi）：spec 先行、纯 Dart core 全测试、
> copilot CLI (gpt-6-astra) 执行 + 维护者独立验收、git worktree 并行批次、
> GA4 遥测+崩溃哨兵、GitHub Actions 云签名 TestFlight。
> 全局约定：`flutter analyze` 零 issue；`flutter test` 全绿（测试前必须设
> NO_PROXY=localhost,127.0.0.1，本机代理会挡 flutter_tester）；新逻辑必须带
> 测试；UI 文案不出现引擎/模型技术名（统一「AI」）；埋点
> `Analytics.instance.event`；commit 不 push、不触发 workflow（发版归维护者）。

## 产品定位

零基础 → 俱乐部棋手的单机国际象棋学习伴侣。iPad/iPhone 优先，全平台。
主线（吸收 pureweiqi 二期结论，第一版就带学习动线）：
互动教程 → 每日战术题 → 分级 AI 对弈 → 终局一键复盘。

## 相对围棋的技术红利（决策已定，不再讨论）

- **AI = Stockfish**：官方开源（GPL——注意：整 app 采用 GPLv3 兼容策略或
  进程隔离；先按「引擎二进制随包 + UCI 通信」实现，上架前复核许可披露，
  docs/CREDITS.md 记录）。优先用 pub.dev `stockfish` 系列包（执行时评估
  最新维护版，如 stockfish_chess_engine 等）；不可用则回退：官方源码 +
  FFI/isolate 集成（照 pureweiqi 的 katago_ffi.cpp 模式）。
- **难度**：UCI `UCI_LimitStrength`+`UCI_Elo`（约1320-3190）映射 10 档，
  低档位辅以 `Skill Level`。无需用户下载模型：NNUE 在构建期获取并随包；
  新版含大/小网，包体不能假定只有几 MB，发布前按平台实测。
- **格式**：FEN（局面）+ PGN（对局/变化树），全部自研解析往返。
- **战术题**：Lichess puzzle 数据库（CC0）。抽取子集（≥1000 题）按主题
  （fork/pin/skewer/mateIn1/mateIn2/背排杀…）与难度（rating 段）分级打包。
- **名局库**：公版棋谱（Morphy/Anderssen/Capablanca 等 1900 前）PGN。

## 代码结构（镜像 pureweiqi）

```
lib/core/       纯 Dart：board.dart(0x88或8x8 mailbox 走子生成/合法性/
                将军检测/易位/吃过路兵/升变/三次重复/50步/长将规则不需)、
                game_tree.dart(PGN 同构变化树)、fen.dart、pgn.dart、
                puzzle.dart(FEN+主线着法判定，对应 TsumegoSession)
lib/engine/     uci_protocol.dart、stockfish_service.dart(生命周期/难度/
                analyzePosition 返回 eval+bestline，对应 katago_service)
lib/features/   game/(对弈+提示+复盘) puzzle/(战术题+错题本+每日)
                tutorial/(教程) library/(名局+我的棋谱 PGN) home/ settings/
lib/app/        telemetry/(从 F:\weiqi\lib\app\telemetry 移植三件套，
                MEASUREMENT_ID 常量占位待新 GA 属性) router
widgets/board/  棋盘组件：自绘 8x8、拖拽走子+点击走子双模式、合法着点
                提示、将军高亮、升变选择弹窗、棋子 SVG/PNG 素材
                （公版素材如 cburnett SVG——CC-BY-SA，记录 CREDITS）
```

## 里程碑与批次（worktree 并行规则同 pureweiqi 二期）

### 批 1（并行）
- **M1 core 规则引擎**［已完成；主树 main］（其他一切的地基）
  - 走子生成含全部特例；Zobrist 局面哈希（三次重复）；终局判定
    （将杀/逼和/不足子力/50步/三次重复）。
  - FEN 解析/生成往返；PGN 解析（标签对/着法 SAN/注释/变化/结果）与
    生成往返；SAN 与坐标互转（歧义消解）。
  - **硬验收 perft**（不过全部作废）：startpos d1-d5
    (20/400/8902/197281/4865609)；KiwiPete
    r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -
    d1-d4 (48/2039/97862/4085603)；及 CPW 标准 position 3-6 至少 d4。
    另：SAN 歧义、升变四子、易位被将/穿将非法、吃过路兵暴露将非法等
    专项测试。测试目标 ≥120 项。
  - 实现：`lib/core/{board,move,game_tree,fen,pgn,puzzle}.dart`，0x88
    棋盘；core 无 Flutter / 第三方棋规依赖。接口及行为约定见 README。
  - 验收入口：`flutter test test\core`；六组标准 perft 共 26 个深度逐项
    `expect` 精确相等（position 3 同样覆盖到 d5）；`dart run tool\perft.dart`
    可独立于 Flutter 运行并输出逐深度耗时。
  - PGN 保留标签、注释、NAG、嵌套变化与结果，导出规范化空白/着数；
    变化提升后仍保留前置注释。FEN 只保存局面，不虚构重复历史。
  - Zobrist 使用跨平台精确的 64 位 BigInt；仅有**合法**吃过路兵时将
    目标列计入重复哈希。50 步/三次重复作为可申和状态暴露，不阻止分析
    继续走子；将杀/逼和优先。不足子力不等同于“无法强制将杀”。
  - PuzzleSession：FEN + UCI 主线、提示、自动应着、正误/重试；
    `fromLichess` 单独处理 CSV 第一手是对手铺垫着的约定。
  - 本机验收（2026-09-28）：`flutter analyze` 零 issue；
    `flutter test` 310/310 通过（core 309 + 原有 widget 1）。
    独立 Dart perft 26/26 精确相等，全部深度合计 1.152 秒；
    startpos d5 329ms、KiwiPete d4 277ms、position 3 d5 60ms、
    position 4/5/6 d4 分别 30/145/232ms（计时受机器/JIT 状态影响）。
- **M4a 遥测移植**［worktree task/telemetry］：从 F:\weiqi 移植
  analytics/app_logger/crash_guard（可直接读 F:\weiqi 源码），事件名改
  chess 语境（game_start/puzzle_result/engine_start/abnormal_exit 等），
  MEASUREMENT_ID/API_SECRET 用常量占位+TODO 注释。main.dart 接线。
  隐私同意弹窗直接带上（吸收 pureweiqi A1 经验）。
  - **已实现**：`lib/app/telemetry/` 三件套、GA4 MP 每批最多 25 条、
    最多 100 条 JSONL 待发队列（同步 flush 临时文件后原子替换，发送确认前
    保留在磁盘）、失败保留补发、Dart/native phase 哨兵及崩溃分类上报。
  - 首启确认前仅本地暂存，不启用网络或发送定时器；可选择关闭统计并继续。
    关闭会取消请求并清空待发队列；设置提供开关与隐私政策占位页。日志与
    哨兵保留在本机，不随统计上传。客户端随机标识每次启动重建，不持久化。
  - `main.dart` 已接 `runGuarded`、logger/analytics 初始化、版本号及生命周期
    flush（含恢复时重试）；Android INTERNET 与 macOS 出站网络权限已补齐。
    当前计数器骨架保留，新增设置入口。
  - **维护者待办**：在 `analytics.dart` 回填独立 chess GA4 Property 的
    MEASUREMENT_ID/API_SECRET；占位值存在时，即使用户同意也不会发网络请求。
    正式发布前补齐政策联系方式、生效日期、保留期限及第三方处理说明。
  - 事件白名单：`app_open`、`game_start`、`game_end`、`puzzle_result`、
    `engine_start`、`app_error`、`abnormal_exit`。后续功能调用
    `Analytics.instance.event`，参数需在 `_eventParams` 中显式声明；禁止
    PGN/FEN/着法、错误原文、堆栈及路径。`game_start` 允许 mode/difficulty/
    player_color，`puzzle_result` 允许 correct/attempts/duration_ms/rating；
    AI 启动前 `setPhase('chess_engine_start')`，成功后 `clearPhase(prefs: prefs)`。
    原生侧可向 `nativeBreadcrumbPath` 写入并 fsync 阶段面包屑；非正常退出
    仅上报哨兵是否存在与连续次数，不上传阶段文本。
  - 验证覆盖队列落盘往返、请求失败/发送中退出统计、隐私持久化失败、
    哨兵恢复、日志轮转及首启/设置 UI；验收命令：
    `$env:NO_PROXY='localhost,127.0.0.1'; flutter pub get; flutter analyze; flutter test`。
    本批验收：analyze 零 issue，28 项测试全绿（遥测 17、日志/崩溃 4、
    隐私与设置 widget 7）。

### 批 2（M1 合并后并行）
- **M2a 棋盘组件+双人对弈**［已完成；task/board］：棋盘 widget（拖/点双模式、
  合法点提示、最后一手/将军高亮、翻转视角、升变弹窗）；双人对弈
  （面对面布局吸收 pureweiqi 经验：顶部操作条旋转 180°）；终局判定展示；
  PGN 保存到本地棋谱库。
  - `lib/widgets/board/`：自绘 8×8 棋格及坐标，点击/拖拽共用 core 合法着，
    高亮选中、合法目标、最后一手与被将王；翻转后坐标/交互同步。升变四选一，
    取消升变或取消/越界拖拽不落子；父局面更新会使旧选择及待提交升变失效。
  - 固定上方黑方操作条旋转 180°、下方白方操作条；本方回合才可认输/提和。
    认输二次确认；提和暂停走棋，由对侧操作条同意或拒绝。双侧可悔一半回合，
    终局也可悔棋并恢复对弈；被悔掉的续着不作为变化保存在 PGN。
  - 双人模式自动裁定将杀/逼和/不足子力/三次重复/50 步，另支持认输和
    协议和棋；三次重复/50 步自动判和是本模式策略，不改 core 的可申和语义。
    结果与保存反馈共用固定 72px 区域，不推动棋盘。
  - `RecordsRepository` 参照 pureweiqi 文件库模式，保存到绝对沙盒路径
    `<app documents>/purechess/records/*.pgn`。保存含标签、SAN、结果与终局
    说明；非初始局面带 FEN/SetUp。文件名清理、重名后缀、串行保存、临时文件
    flush 后 rename；失败 UI 可见且可重试。显式保存快照，不自动覆盖历史文件。
  - 临时首页及命名路由 `/game`、`/records`、`/settings` 已接入；棋谱库可
    列表查看并打开可复制 PGN 文本，图形复盘留待后续里程碑。未保存离开/重开
    需确认。本批不含自动保存/闪退恢复；保留现有隐私告知、设置和遥测生命周期。
  - cburnett 12 个 SVG 从 Lichess 固定 revision 下载并逐个核对 Git blob hash。
    `docs/CREDITS.md` 区分原作 CC-BY-SA 3.0 多重许可与实际 Lichess 文件的
    GPLv2+ 声明，附完整 GPLv2 文本；不将其误标为公共领域。
  - 本机验收（2026-09-28）：`flutter analyze` 零 issue；
    先设 `NO_PROXY=localhost,127.0.0.1`，`flutter test` **408/408 通过**。
    新增 71 项：棋盘 20、对局状态 18、对弈 UI 18、PGN 文件库 12、棋谱 UI 3；
    原有 337 项（core 309、遥测/日志 21、隐私/导航 widget 7）全绿。
    覆盖双朝向拖点、四种升变/取消、易位/吃过路兵/吃子、棋盘像素高亮、
    全部终局、回合权限、悔棋、重名/并发保存与失败重试、离开确认，
    320×568 / 390×844 / 844×390 / 1024×1366 布局及结果区高度不变。
- **M2b Stockfish 集成**［task/engine］：评估并接入 stockfish 包或 FFI；
- **M2b Stockfish 集成**［已实现；task/engine］：评估并接入 stockfish 包或 FFI；
  StockfishService（启动/UCI 握手/难度设置/go movetime 或 depth/
  bestmove 解析/eval 解析）；错误透传与崩溃哨兵接线（吸收 pureweiqi：
  引擎故障必须 UI 可见，绝不无声吞掉）。10 档难度常量表。
  - **选型实证（2026-09-28）**：

    | pub.dev 包 | 最新版本 / 发布时间（UTC） | 声明的平台 | 结论 |
    | --- | --- | --- | --- |
    | [stockfish](https://pub.dev/packages/stockfish) | 1.8.1 / 2026-02-03 05:58 | Android、iOS | 选用并精确锁版。虽然 pubspec 写 SDK `>=2.17.0 <3.0.0`，实际 Dart 3.13.2 的 `flutter pub get` 成功；不能只看上界误判不兼容。桌面没有实现，采用独立 UCI 子进程。 |
    | [stockfish_chess_engine](https://pub.dev/packages/stockfish_chess_engine) | 0.8.2 / 2025-02-20 17:58 | Android、iOS、Linux、macOS、Windows | 未选用。Dart 3 解析及 Windows Debug 原生构建通过，但绝对路径网络配置后首次搜索让 flutter_tester 直接退出（code 1）。源码 `src/Stockfish/src/engine.cpp` 的桌面 `EvalFile` 回调误调 `load_small_network`，随后大网 `verify` 失败会 `exit(EXIT_FAILURE)`。两个下载网络 SHA-256 均与名称匹配，非空文件/下载损坏问题。没有修改 pub cache 或用切换应用全局 CWD 的方式绕过。 |

    发布时间以 pub.dev API 的 `latest.published` 为准：
    <https://pub.dev/api/packages/stockfish>、
    <https://pub.dev/api/packages/stockfish_chess_engine>。
    **最终组合不是“两个包都不可用”**：移动端用维护版包，桌面因平台缺口/
    已证实的包缺陷使用官方子进程。GPLv3 与发行义务见 `docs/CREDITS.md`。
  - **实现**：`lib/engine/uci_protocol.dart` 为纯 Dart 命令/握手/
    id/option/info/cp/mate/bound/PV/bestmove 解析；`stockfish_transport.dart`
    为可注入传输协议与桌面 Process 实现；`mobile_stockfish_transport.dart`
    包装 Android/iOS 包，监听 ready/error/disposed 与 stdout。包的 ready
    仅代表 worker 启动，服务还必须等待 `uciok` 与 `readyok`。
  - **生命周期**：stopped → starting → ready ↔ analyzing；另有
    stopping/failed/disposed。并发启动共用 Future，重叠搜索显式拒绝，
    stop/dispose 取消等待并完成清理；超时销毁当前会话防止晚到的 bestmove
    串入下一次分析。移动端没有强杀 API，无法确认停止时禁止不安全重启。
    桌面优先 stop/quit，超时只杀自己启动的子进程并等待退出。
  - **错误/遥测**：Future 抛 `StockfishException`，`status` 提供可监听的
    状态和 `error.message`，`lastError` 保留 UI 可展示信息；底层 cause
    仅在本地日志。设置页新增「AI 状态/检查 AI」，启动、分析失败与空闲时
    异常退出均实际显示，不只是留一个未来 UI 接口；所有用户文案统一 AI。
    `chess_engine_start` / `chess_engine_analyze` 哨兵在危险阶段前落盘，
    正常返回/可处理失败后清除；启动成功清零 crashStreak。
    `engine_start` 只发送白名单 `success`、`duration_ms`。
  - **难度常量**：

    | 档 | Skill Level | UCI_LimitStrength | UCI_Elo | movetime(ms) |
    | --- | --- | --- | --- | --- |
    | 1 / 2 / 3 / 4 / 5 | 0 / 2 / 4 / 6 / 8 | false | 不使用 | 100 / 150 / 250 / 400 / 600 |
    | 6 / 7 / 8 / 9 / 10 | 20 | true | 1600 / 1900 / 2200 / 2500 / 2800 | 800 / 1000 / 1200 / 1600 / 2000 |

    每次搜索重设模式，避免从高档切低档仍被 Elo 限制；握手校验实际引擎
    支持的选项范围，不能静默 clamp。档位是产品参数，不保证人的实际 Elo。
  - **分析契约**：`analyzePosition(fen, difficulty: 5, depth: n)` 自动启动，
    depth 指定时替代 movetime。返回不可变 `bestLine`（合法 UCI 主变化）、
    `bestMove`、`depth`、`score` 和互斥 `cp`/`mate`；评分从 FEN **行棋方**
    视角，mate 为有符号的将杀步数，不强转 cp。只采用 MultiPV=1 的完整
    exact 分数/PV，忽略界限分数与局部更新；低强度 bestMove 可能不同于
    最强 PV 首手，两者分别暴露。终局无着返回 null bestMove、空 PV，
    将杀 mate=0、逼和 cp=0；其他缺分/缺着/非法 PV 都明确报错。
    入参复用 core FEN 并额外拒绝非行棋方被将、不可能子数、无王车的易位
    权及无双步兵的吃过路兵目标，避免把已知不安全局面送进原生层。
  - **桌面资产**：探测可执行文件旁及父目录、当前目录的
    `engine_assets/stockfish[.exe]`；支持构建期
    `--dart-define=STOCKFISH_EXECUTABLE=<绝对路径>` 或注入传输路径。
    子进程以自身目录工作，不开 shell、不修改应用 CWD、不静默联网下载。
    `engine_assets/` 整体忽略，桌面分发时另行打包正确 CPU 二进制与许可。
  - **真实冒烟**：官方 Stockfish 19（sf_19，2026-09-05 发布）
    Windows x86-64 universal；下载归档 SHA-256 已对照官方 release digest
    验证，记录在 CREDITS。本机 10/10 档返回 cp 和合法 bestmove/PV，
    初始一轮深度为 13–22；另通过 mate-in-one（mate=1）、停止后重启
    与第二次握手/搜索，总计约 13 秒。评分/深度受硬件与随机降强影响。
    复现命令见 README；默认单测显式跳过 opt-in 真实引擎用例。
    **移动端真机/签名构建、Linux/macOS 真机未在 Windows 上验证**；
    Android/iOS 已接包并以 fake native client 验证 adapter；上架前必须
    在平台流水线/真机验证 FFI 加载、NNUE 构建下载及 GPL 发行方案。
  - **本机验收**：`flutter analyze` 零 issue；
    `flutter test test\engine --coverage` 109 项通过、1 项 opt-in 冒烟跳过；
    `uci_protocol.dart` 行覆盖 **95/95（100%）**；
    `flutter test` 全量 **446 项通过、1 项 opt-in 跳过**；
    单独启用真实引擎冒烟 **1/1 通过**（包含十档搜索、mate、重启）；
    `flutter build windows --debug` 通过。所有 Flutter 测试均设置
    `NO_PROXY=localhost,127.0.0.1`。
- **M2c CI+发版管线**［task/ci，我=维护者自做或 copilot］：ci.yml
  （ubuntu test + macos iOS no-codesign）与 testflight.yml（云签名四件套
  secrets 同 pureweiqi，bundle com.weavejam.purechess，
  ITSAppUsesNonExemptEncryption=false，隐私 purpose strings 预防性照抄）。

### 批 3（批 2 合并后并行）
- **M3a 对弈整合**［task/game］：人机对弈（执子/难度推荐+自适应/提示按钮/
  悔棋/认输/新对局表单 CTA 固定底部——pureweiqi UX 结论直接照抄）；
  终局一键复盘（逐手 eval 曲线 + 3 大恶手，Stockfish eval 比 KataGo 还
  标准：centipawn 损失）。
- **M3b 战术题系统**［task/puzzle］：puzzle 引擎（FEN+着法序列，对方
  自动应着，主题/难度分级、错题本、每日 10 题、两级提示）；
  Lichess CSV 抽取脚本（scripts/，CC0 来源写 CREDITS）≥1000 题分装。
- **M3c 互动教程**［task/tutorial］：15-20 关：棋盘与兵/各子走法（6 关）→
  吃子→将军→应将三法→将杀概念→mateIn1 实战→易位→升变→吃过路兵→
  逼和陷阱→毕业局（AI 最低档让后）。关卡数据格式复用 puzzle 引擎+讲解
  文案；线性解锁；毕业引导每日战术题。
- **M3d 首页学习动线+名局库**［task/home］：镜像 pureweiqi P0-2；
  公版名局 20+ 局带简注，阅读模式。
  - **已实现**：未毕业显示「继续教程第 N 关」主卡；毕业后展示每日题、
    新/继续对局（推荐难度）、读名局/继续看的名局三卡；双人对弈、
    我的棋谱、名局库保留为次级入口。页面内使用深海蓝/银白的完整
    明暗阅读主题，跟随系统，不改其他并行分支页面的全局主题。
  - **并行集成边界**：只读 `tutorial_progress` 与本地日历日
    `daily_YYYYMMDD`，绝不创建、修补或覆盖这两个功能的进度。
    原计划仅指定键名，未定义值类型：本分支的展示适配器接受完成数量
    `int`，或 JSON 字符串 `{"completed": n, "total": m}`（也接受 JSON 整数）。
    整数简版默认教程 18 关、每日 10 题；不同教程总数应由 JSON `total`
    明确提供。缺键显示尚无记录，损坏/越界显示错误而不伪造毕业。
    路由返回、应用恢复前台及跨本地午夜刷新展示。
  - **路由接线点**：`AppRouter.routes` 可注入 `tutorialBuilder`、
    `dailyBuilder`、`aiGameBuilder`；默认明确显示「正在准备中」，不是
    模拟教程/每日题/AI。路由为 `/tutorial`、`/puzzles/daily`、`/game/new`；
    原 `/game` 仍是双人对弈。对局分支通过 `recommendedDifficulty`
    （1–10）与 `canResumeGame` 提供首页摘要；点击携带
    `{"difficulty": n, "resume": bool}`，教程点击携带 1-based `lesson`。
    未显式注入难度时，只读 task/game 已提交的
    `chess.ai.recommendedLevel`（与 `AiDifficulty.preferenceKey` 相同），
    对局返回后重新读取；缺失时推荐入门第 1 档，损坏时明确提示，不覆盖原值。
    不虚构可恢复对局。`/game/new` 与该分支的 `AppRouter.newGame` 对齐。
  - **名局阅读**：`/library` 目录、`/library/reading` 续读（无书签时
    从歌剧院局开始）；`assets/library/classics.pgn` 共 21 局，
    1183 个半回合、每局 5 条原创中文简注。含歌剧院/不朽/常青局及
    卡帕布兰卡 1893 年接受让后的早期对局（保留特殊 FEN）。
    来源、事实性公版依据、历史收尾分歧与 7 处 SAN 将杀符规范化见 CREDITS。
  - 大字注释、禁用走子的棋盘、上/下一步、方向键、滑动进度、结尾提示；
    手机纵向/平板横向布局。单键 `library_reading` 保存
    `{"id":"稳定 PGN Id","ply":非负半回合位置}`，每次进入或走步写入，
    写入串行化且失败可见/可重试；坏书签或失效位置回到目录并提示。
    资产加载失败显示重试，不以空目录冒充成功。
  - **验收（2026-09-28）**：新增 79 项测试；21 局逐着 core 合法性、
    SAN 往返、PGN 注释往返、全部撤回恢复初始 FEN，7 个将杀收尾规范化。
    覆盖只读进度、毕业切换、午夜刷新、路由占位/注入、书签续读与写入失败、
    明暗两主题下 320×568 / 390×844 / 844×390 / 1024×1366
    和 2 倍字号。`flutter analyze` 零 issue；
    `NO_PROXY=localhost,127.0.0.1` 下 `flutter test` **596 通过、1 个
    opt-in 原生 AI 冒烟跳过**，未 push、未触发 workflow。

### 批 4（收尾）
- 音效/庆祝、golden 测试、每日推送、备份导入导出（全部照抄 pureweiqi
  二期对应实现思路）；GA 新属性创建与 ID 回填（维护者做）；ASC 建
  App 记录（维护者做）；TestFlight build 1。
- **音效与庆祝**［已实现；task/sound］：
  - `app/sound.dart` 使用 `SystemSound.click` 的不同节奏区分落子、吃子、
    将军、将杀、获胜、答对、答错及一般终局；不新增插件或音频资产。
    系统音色、音量和可听性遵循设备系统设置；不支持的宿主记录本地日志，
    不影响走棋。尚未进行 Android/iOS 真机听感验收。
  - 设置页「音效」默认开，`soundEnabled` 保存到 SharedPreferences；
    关闭立即取消待播放节奏，后台、离开当前路由、销毁页面也停止后续短音。
    主主题、阅读主题及独立 InkWell/ExpansionTile 关闭 Material 自带点击音，
    避免 Android 按钮绕过静音开关。设置写入失败显示提示并重读真实存储。
  - `app/play_feedback.dart` 比较同一对局的棋盘快照；支持同帧人类走棋与
    AI 应着、吃过路兵和升变，不把易位误判为吃子。提示、翻转、悔棋、
    初始加载和保存重试不重复出声；终局提示优先于最后一步普通落子提示。
  - 面对面获胜、人机玩家获胜、战术题解完、每日题集完成、教程过关/毕业
    显示 3 秒缩放奖杯徽章；谜题与教程等待进度保存成功才庆祝。
    AI 获胜或和棋不显示玩家胜利庆祝；毕业局结束庆祝的是教程完成。
    每次完成只展示一次，重新打开已结束对局不重播，静音不隐藏庆祝。
    徽章为不拦截操作的叠层，不占据布局空间；原结果区高度不变，
    支持系统减少动画与大字号。
  - 徽章实际展示后发送 `celebrate_shown`，只允许 `source` / `result`，
    沿用原匿名统计开关、隐私门禁、落盘补发；不发送 FEN、着法、题号或文案。
    接线包含现有 `TutorialDailyScreen` 入门每日题，不改变既有每日路由。
  - 自动测试覆盖各音型节奏、静音/重启/后台/页面销毁、系统音效异常、
    真正页面操作与静音导航、胜负/和棋/解题/毕业条件、保存失败重试、
    庆祝去重、遥测字段白名单及棋盘几何位置保持。
  - 本机验收：`flutter analyze` 零 issue；
    `NO_PROXY=localhost,127.0.0.1` 下 `flutter test` 全量 **1851 通过、
    1 项既有 opt-in 原生 AI 冒烟跳过**。

### 批 5（第三期：连续性与奖章，用户 2026-09-28 需求，三 app 同构）
- **M5a+M5b 连续性（task/continuity，一路执行——同在 game feature，拆开必冲突）**：
  1. 新对局表单持久化：记住上次执子颜色与用户手动选择的难度档
     （键 `newGame.color` / `newGame.level`），下次进入恢复；自适应
     「推荐第 N 档」照旧显示，用户没手动改过则跟随推荐。
  2. 断点续弈：对局进行中（AI 局）在每步落子后与 app 退后台/销毁时
     自动存盘到 prefs（PGN + AiGameConfig + 已用提示等会话元数据；
     `GameSession.snapshot()` 的 PGN round-trip 已可用）。终局/认输清除
     存盘。启动时检测存盘 → main.dart 把 `canResumeGame` 接通（现为
     恒 false 的 M3d stub），首页「继续对局」直接恢复 AiGameScreen；
     Stockfish 无状态，走 FEN/着法重建即可。存盘损坏时静默丢弃并
     reportHandledError，不得阻塞开局。
- **M5c 打卡奖章（task/badges，等围棋通用设计文档到齐后启动）**：
  本地统计 + 连续活跃 streak + 里程碑成就（教程毕业、各难度首胜、
  题目里程碑），庆祝动效复用批 4 徽章叠层；无社交排行，遥测仅发
  奖章类别不发内容，语义与围棋/象棋同构。
- PM 补充（chess 特有，随 M5 实现）：双人对弈同享断点续弈；终局
  「再来一局」沿用本局配置一键开局。

## pureweiqi 踩坑清单（执行者必读）

1. flutter test 连不上 tester = 代理问题 → NO_PROXY=localhost,127.0.0.1。
2. iOS 引擎相关目录必须用沙盒绝对路径（logDir/homeDataDir 教训：相对
   路径→容器根不可写→子线程 throw→无 handler→整 app abort）。
3. 引擎子线程的异常 Dart 层 catch 不到 → 崩溃哨兵（phase 文件+native
   面包屑 fsync）从第一天就接。
4. 事件队列必须落盘补发（闪退时 crash 事件才追得回）。
5. TestFlight 静默拒收只发邮件：purpose strings（相册/相机/定位，
   file_picker 连带）与 framework MinimumOSVersion≤app 提前做对。
6. CocoaPods vendored framework 链接不可靠 → 如走 FFI 用 dlopen+dlsym
   （mangled 名）零链接依赖模式。
7. pubspec 并行任务都会碰 → 新依赖追加在依赖区末尾，合并冲突维护者解。
8. UI 结果文案区固定高度，别让文本变化推动棋盘。
9. copilot 产物必须独立复跑 analyze+test 验收，自报不作数。
10. stockfish pod 的 NNUE 权重靠 script phase curl 下载，Xcode 15+ 用户
    脚本沙盒会拦（报 Could not find incbin file）。CI 在 pub get 后把
    权重预取到 pub-cache 的 ios/Stockfish/src；本地 mac 构建同理预放。
11. 并行分支合并冲突必须手工逐块解，绝不能 sed 删标记了事（批 3
    router.dart 重复路由事故）；纯追加型（pubspec 依赖、遥测白名单、
    并列测试）两边都留。
