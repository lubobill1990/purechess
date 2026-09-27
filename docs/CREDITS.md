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
