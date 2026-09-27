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
  低档位辅以 `Skill Level`。无大模型下载：NNUE 小网随包（几 MB）。
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

### 批 2（M1 合并后并行）
- **M2a 棋盘组件+双人对弈**［task/board］：棋盘 widget（拖/点双模式、
  合法点提示、最后一手/将军高亮、翻转视角、升变弹窗）；双人对弈
  （面对面布局吸收 pureweiqi 经验：顶部操作条旋转 180°）；终局判定展示；
  PGN 保存到本地棋谱库。
- **M2b Stockfish 集成**［task/engine］：评估并接入 stockfish 包或 FFI；
  StockfishService（启动/UCI 握手/难度设置/go movetime 或 depth/
  bestmove 解析/eval 解析）；错误透传与崩溃哨兵接线（吸收 pureweiqi：
  引擎故障必须 UI 可见，绝不无声吞掉）。10 档难度常量表。
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

### 批 4（收尾）
- 音效/庆祝、golden 测试、每日推送、备份导入导出（全部照抄 pureweiqi
  二期对应实现思路）；GA 新属性创建与 ID 回填（维护者做）；ASC 建
  App 记录（维护者做）；TestFlight build 1。

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
