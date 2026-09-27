# 素材来源与许可

## Lichess 战术题（M3b）

- 来源：[Lichess 开放数据库](https://database.lichess.org/#puzzles)，下载地址：
  <https://database.lichess.org/lichess_db_puzzle.csv.zst>。
- 许可：**[CC0 1.0 公共领域贡献](https://creativecommons.org/publicdomain/zero/1.0/)**。
  题目、rating 和主题标签来自 Lichess；中文分类与提示由本项目编写。
- 提取日期：2026-09-28；本次 HTTP `Last-Modified`：
  `Wed, 09 Sep 2026 17:40:14 GMT`。版本与每个分包的 SHA-256 见
  `assets/puzzles/manifest.json`。
- 共 **1,050 道唯一题目 / 21 个分包**。mateIn1、mateIn2、fork、pin、
  skewer、hangingPiece、backRankMate 各 150 题；每个主题的
  `<1200`、`1200–1599`、`1600–1999` 三段各 50 题。多标签题只分配到
  一个分包，JSON 中仍保留全部原始标签，因此按标签计数可能超过分包计数。
- `fen` 已应用 CSV 第一手（对手铺垫着），`line` 是从解题方开始的
  UCI 主线，不再包含铺垫着。保留原始 `id`、`themes`、`rating`；
  可用 `https://lichess.org/training/<id>` 回溯单题。

使用 `uv` 重建资产（不需要全局 Python 或手动装解压工具）：

```powershell
uv run scripts\fetch_lichess_puzzles.py
# 可选：使用已下载的完整 CSV.zst；默认每个分层抽取 50 题
uv run scripts\fetch_lichess_puzzles.py --input D:\datasets\lichess_db_puzzle.csv.zst
uv run scripts\test_fetch_lichess_puzzles.py
$env:NO_PROXY='localhost,127.0.0.1'
flutter test test\features\puzzle
```

脚本固定 `python-chess` / `zstandard` 依赖，边下载边解压 CSV，达到所有
分层配额就关闭流，不保存数 GB 的整库；本次扫描 91,715 行。无效 FEN、
非法主线、错误的将杀标签、配额不足或网络失败都会显式失败，不发布不完整
抽样。相同来源与参数重跑产生相同 JSON；上游更新后可能产生新抽样，
应将 manifest 和分包作为同一次资产更新一起提交。分包校验使用 SHA-256；
Python 与项目 Dart core 分别逐题复核局面和主线合法性。将杀标签末着必须
将杀，mateIn1 / mateIn2 分别要求 1 / 3 半回合。非将杀战术标签沿用
Lichess 的分析结果；合法性测试不声称重新证明其评分或最佳着唯一性。

应用入口为 `AppRouter.puzzles`（`/puzzles`），首页接入口由首页维护者处理。
三级页面为集合 → 题目列表 → 做题；复用 ChessBoard / PuzzleSession，
对手自动应着。普通题按最佳主线判定；按 Lichess 规则，mateIn1 的其他
合法将杀着也接受。两级提示先给主题思路，再仅高亮起点格；黑方题自动翻转。
结果区固定高度，保存失败可重试或确认放弃，不能显示为已保存。

本地 prefs：`daily_YYYYMMDD` 保存设备本地日期对应的 10 个不重复题目 ID，
同日重开不换题；`puzzle_progress_v1` 一次写入累计完成、错题与每日完成记录。
每日完成独立计数，不把历史做对自动当作今天完成；午夜后新开每日题单使用
新日期，已打开的题单仍记在原日期。做错加入错题本，做对移出；写入成功才
更新页面状态。`puzzle_result` 遥测只发送 `correct`、`attempts`、
`duration_ms`、`rating`，遵循现有隐私开关，不发送 FEN、着法或题目 ID。

## Cburnett 棋子 SVG

作者：**Colin M. L. Burnett（Cburnett）**。本项目包含白、黑双方的兵、马、
象、车、后、王，共 12 个 SVG，通过 `flutter_svg` 离线渲染。

- 下载来源：[lichess-org/lila / public/piece/cburnett][lila-pieces]。
- 固定版本：`b3634e3fa5cbfd8472eb037d68b3fa0c619bbe12`。
- 下载日期：2026-09-28。
- 本项目未修改 SVG 内容，仅复制到 `assets/pieces/`；这些 SVG 本身即为
  随仓库提供的可编辑源文件。
- **这不是公共领域（public domain）素材。** Cburnett 的 Wikimedia 原作
  提供包括 [CC-BY-SA 3.0][cc-by-sa] 在内的多重许可；例如
  [白兵原作及许可说明][original-pawn]。CC-BY-SA 要求署名、附许可链接、
  标明修改，并对改编作品以相同或兼容许可共享。
- **本次实际下载的 Lichess 版本，上游 [COPYING.md][lila-copying] 将
  `public/piece/cburnett` 明确列为 GPLv2+。** 不将上游处理后的文件擅自
  重标为 CC-BY-SA：保留作者署名、源地址及 GPLv2-or-later 的许可声明，
  [GPLv2 完整文本](licenses/GPL-2.0.txt) 随仓库提供。原作 CC-BY-SA
  信息用于溯源，不替代此处实际下载版本的上游许可。

| 本地文件（`assets/pieces/`） | 棋子 | Cburnett 原作 |
| --- | --- | --- |
| `wP.svg` | 白兵 | [Chess plt45.svg](https://commons.wikimedia.org/wiki/File:Chess_plt45.svg) |
| `wN.svg` | 白马 | [Chess nlt45.svg](https://commons.wikimedia.org/wiki/File:Chess_nlt45.svg) |
| `wB.svg` | 白象 | [Chess blt45.svg](https://commons.wikimedia.org/wiki/File:Chess_blt45.svg) |
| `wR.svg` | 白车 | [Chess rlt45.svg](https://commons.wikimedia.org/wiki/File:Chess_rlt45.svg) |
| `wQ.svg` | 白后 | [Chess qlt45.svg](https://commons.wikimedia.org/wiki/File:Chess_qlt45.svg) |
| `wK.svg` | 白王 | [Chess klt45.svg](https://commons.wikimedia.org/wiki/File:Chess_klt45.svg) |
| `bP.svg` | 黑兵 | [Chess pdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_pdt45.svg) |
| `bN.svg` | 黑马 | [Chess ndt45.svg](https://commons.wikimedia.org/wiki/File:Chess_ndt45.svg) |
| `bB.svg` | 黑象 | [Chess bdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_bdt45.svg) |
| `bR.svg` | 黑车 | [Chess rdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_rdt45.svg) |
| `bQ.svg` | 黑后 | [Chess qdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_qdt45.svg) |
| `bK.svg` | 黑王 | [Chess kdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_kdt45.svg) |

原始下载 URL 模板：

```text
https://raw.githubusercontent.com/lichess-org/lila/b3634e3fa5cbfd8472eb037d68b3fa0c619bbe12/public/piece/cburnett/{filename}
```

发布二进制前，应将素材署名和相应许可纳入应用内许可披露，并复核整个发行包
（包括后续 AI 组件）的许可兼容性。此记录不表示其他素材或第三方组件的许可。

[lila-pieces]: https://github.com/lichess-org/lila/tree/b3634e3fa5cbfd8472eb037d68b3fa0c619bbe12/public/piece/cburnett
[lila-copying]: https://github.com/lichess-org/lila/blob/b3634e3fa5cbfd8472eb037d68b3fa0c619bbe12/COPYING.md
[original-pawn]: https://commons.wikimedia.org/wiki/File:Chess_plt45.svg
[cc-by-sa]: https://creativecommons.org/licenses/by-sa/3.0/
# Third-party credits and release obligations

## Stockfish

The AI is [Stockfish](https://stockfishchess.org/), by the Stockfish developers.
Engine source: <https://github.com/official-stockfish/Stockfish>.
License: **GNU GPL version 3**; preserve the upstream copyright notices,
`AUTHORS`, and `Copying.txt` when distributing an engine.

Android/iOS use [`stockfish` 1.8.1](https://pub.dev/packages/stockfish),
maintained by Arjan Aswal, through its Dart/native FFI bridge:
<https://github.com/ArjanAswal/stockfish>. Treat this integration as GPLv3;
the CocoaPods metadata's MIT label is not a license exemption for Stockfish.
The package's NNUE networks are downloaded by its native build scripts and
embedded in the app, not downloaded by the user at runtime.

Desktop uses an external UCI process. Local Windows validation used the
unmodified [official Stockfish 19 release](https://github.com/official-stockfish/Stockfish/releases/tag/sf_19)
(published 2026-09-05), `stockfish-windows-x86-64-universal.zip`.
Archive SHA-256:
`3c8bf1f9ea66a09350a40df4f632288285ac206d99f33ab5842c408fc30b48a7`.
The archive includes the matching source and GPL notices. Local executable,
archive, source, and networks stay in ignored `engine_assets`; none are committed.

**Before distribution:** the maintainer must confirm a GPLv3-compatible app
licensing/source-distribution strategy, especially for the in-process mobile
integration; provide corresponding source and applicable notices for every
shipped engine/build. Process separation alone is not a blanket GPL exemption.
Verify App Store distribution terms and complete the in-app legal notices
before release. This development milestone is not legal or store approval.

## Package evaluation not shipped

[`stockfish_chess_engine` 0.8.2](https://pub.dev/packages/stockfish_chess_engine)
was evaluated but is **not** a dependency. Its source and credits are at
<https://github.com/loloof64/StockfishChessEngineFlutter>. See
`CHESS_PLAN.md` for the reproducible desktop failure that ruled it out.

## 十九世纪名局 PGN（M3d）

资产：`assets/library/classics.pgn`，**21 局、1183 个半回合、105 条原创中文
简注（每局 5 条，含开局导读）**。全部对局早于 1900 年；离线随包，不在运行时
请求来源网站。每局的 `Id` 是稳定阅读书签，`Source` 标签保存直接来源，
`Title` / `Theme` / `Annotator` 及中文注释由本项目新写。

### 公版依据与使用边界

- 本项目转录的是**实际发生的着法、对局者、时间、地点与结果等历史事实**，
  并非现代作者的讲解文章、分析变化、图片或译文。事实与作者表达须区分：
  [Feist Publications v. Rural Telephone, 499 U.S. 340 (1991)](https://www.law.cornell.edu/supremecourt/text/499/340)
  明确说明事实本身不受版权保护，而原创的选择、编排和表达可能受保护。
- 「公版棋谱」在这里指这些历史事实性棋谱，不是把整个下载网站或数据库
  宣称为公版。免费可下载**不等于** CC0 或允许复制现代注释。我们从大型棋手
  集合中独立选出教学用局，重新编排、重新注释，不分发下载的完整数据库，
  不复制网页正文及第三方评注。数据库特殊权利及各发行地规则仍须发布前复核。
- 所收对局年代为 1851–1895；古老年代为历史资料溯源提供辅助依据，但不以
  「棋手去世超过若干年」替代事实/表达的区分。中文注释是本项目新作品，
  并不冒称十九世纪原注或公共领域文本。
- PGN Mentor 原谱若把将杀写为 `+`，本项目仅将实际将杀着规范为 `#`：
  歌剧院局、不朽局、常青局、罗萨内斯—安德森 1863、斯坦尼茨—蒙格雷迪恩
  1862、斯坦尼茨—洛克、皮尔斯伯里—塔拉什，共 7 处。**未改任何实际走子**。
  core 严格 SAN 解析、逐着合法性、SAN 往返及全局撤回测试均覆盖。

### 来源与名局清单

下载/核对日期：2026-09-28。PGN Mentor 的
[公开下载索引](https://www.pgnmentor.com/files.html)提供按棋手的 ZIP；
下表中 M / A / S / Z / L / P 分别对应下方存档 URL。
未确认的月日保留为 `??`，不臆造精确日期；表中简称仅便于阅读，PGN 保留
来源的棋手拼写。

| 稳定 Id | 名局 / 对阵 | 年份 | 半回合 | 来源 |
| --- | --- | --- | ---: | --- |
| `opera-1858` | 歌剧院局：莫菲—布伦瑞克公爵、伊苏阿尔伯爵 | 1858 | 33 | M |
| `immortal-1851` | 不朽局：安德森—基泽里茨基 | 1851 | 45 | A |
| `evergreen-1852` | 常青局：安德森—杜弗雷纳 | 1852 | 47 | A |
| `paulsen-morphy-1857` | 保尔森—莫菲：弃后追击 | 1857 | 56 | M |
| `morphy-anderssen-3-1858` | 莫菲—安德森，巴黎第 3 局 | 1858 | 39 | M |
| `morphy-anderssen-7-1858` | 莫菲—安德森，巴黎第 7 局 | 1858 | 49 | M |
| `morphy-anderssen-9-1858` | 莫菲—安德森，巴黎第 9 局 | 1858 | 33 | M |
| `morphy-anderssen-11-1858` | 莫菲—安德森，巴黎第 11 局 | 1858 | 71 | M |
| `anderssen-kieseritzky-1851` | 安德森—基泽里茨基：伦敦伊文斯弃兵局 | 1851 | 73 | A |
| `rosanes-anderssen-1862` | 罗萨内斯—安德森：后换开线 | 1862 | 38 | A |
| `rosanes-anderssen-1863` | 罗萨内斯—安德森：让出角车 | 1863 | 46 | A |
| `steinitz-blackburne-1862` | 斯坦尼茨—布莱克本：f 线攻势 | 1862 | 83 | S |
| `steinitz-mongredien-1862` | 斯坦尼茨—蒙格雷迪恩：升车攻王 | 1862 | 57 | S |
| `steinitz-mongredien-1863` | 斯坦尼茨—蒙格雷迪恩：异侧易位 | 1863 | 43 | S |
| `steinitz-rock-1863` | 斯坦尼茨—洛克：追王到 a 线 | 1863 | 35 | S |
| `steinitz-blackburne-1876` | 斯坦尼茨—布莱克本：双象瞄准王翼 | 1876 | 67 | S |
| `steinitz-bardeleben-1895` | 斯坦尼茨—巴德莱本：黑斯廷斯的不朽车 | 1895 | 49 | S |
| `zukertort-blackburne-1883` | 楚凯尔托特—布莱克本 | 1883 | 65 | Z |
| `lasker-bauer-1889` | 拉斯克—鲍尔：双象牺牲 | 1889 | 75 | L |
| `pillsbury-tarrasch-1895` | 皮尔斯伯里—塔拉什 | 1895 | 103 | P |
| `iglesias-capablanca-1893` | 伊格莱西亚斯—卡帕布兰卡：白方让后 | 1893-09-17 | 76 | C |

- M: <https://www.pgnmentor.com/players/Morphy.zip>
- A: <https://www.pgnmentor.com/players/Anderssen.zip>
- S: <https://www.pgnmentor.com/players/Steinitz.zip>
- Z: <https://www.pgnmentor.com/players/Zukertort.zip>
- L: <https://www.pgnmentor.com/players/Lasker.zip>
- P: <https://www.pgnmentor.com/players/Pillsbury.zip>
- C: <https://www.chessgames.com/perl/chessgame?gid=1481959>，仅转录该页公开的
  `olga-data` PGN 中对局事实，不使用 `notes` 或计算机评注。起始 FEN 为
  `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1`：
  **伊格莱西亚斯执白让后，卡帕布兰卡执黑接受让子**，而不是卡帕布兰卡让后。
  `SetUp "1"`、FEN、日期和 76 个半回合均保留。

历史交叉核对：
[歌剧院局](https://en.wikipedia.org/wiki/Opera_Game)、
[不朽局](https://en.wikipedia.org/wiki/Immortal_Game)。
只使用事实核对，不复制维基文章或注释，因此本资产不将维基正文的 CC-BY-SA
许可混作棋谱事实的许可。**不朽局采用通行的 23.Be7# 完整版本**，已有史料对
实战是否提前结束提出疑问，读者开局导读明确提醒；巴德莱本局只到 25.Rxh7+，
不加入赛后展示的将杀续着。

下载 ZIP 的 SHA-256（供来源版本复核，不要求用户运行时联网）：

```text
M 0fbc42563014f6467a0ce7356d23cfb50ddc6a35b72a4f84b3030240caaaf93e
A a7b44e18652e06058dd36f32d10e3f425bf645a1aa71703714494209f01175d4
S b402eb57e0f64ad1291221bc89654a87e1eb1e9c015ff364e3fd31dee0cb593b
Z 55dc6b42fc143f23e48b23b5321a0f7ddd3c5c1aa3282f2770534386b990806c
L bb1bb16d87a198905f043d4f8be900dc96c966f69b1f278887e3143139eb7a1d
P 71021bf6b738ee80057a33f5ba890c6a816ac989042749557b90987144833658
```
