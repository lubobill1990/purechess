import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/move.dart';
import '../../core/puzzle.dart';

const puzzleThemes = <String, ({String title, String hint})>{
  'mateIn1': (title: '一步将杀', hint: '寻找将军，并封住对方王的所有逃路。'),
  'mateIn2': (title: '两步将杀', hint: '先用将军限制王的选择，再寻找最后的将杀。'),
  'fork': (title: '双重攻击', hint: '寻找能同时攻击两个目标的一步，优先观察将军。'),
  'pin': (title: '牵制', hint: '观察同一条线上的棋子：前面的棋子能放心离开吗？'),
  'skewer': (title: '串击', hint: '攻击价值较高的前方棋子，迫使它让开后方目标。'),
  'hangingPiece': (title: '无保护棋子', hint: '寻找没有保护的棋子，吃子前确认对方的反击。'),
  'backRankMate': (title: '底线将杀', hint: '观察被己方兵堵住的王，尝试用车或后侵入底线。'),
};

const puzzleBands = <String, String>{
  'under1200': '入门 · <1200',
  '1200-1600': '进阶 · 1200–1599',
  '1600-2000': '挑战 · 1600–1999',
};

bool ratingInBand(int rating, String band) => switch (band) {
  'under1200' => rating >= 0 && rating < 1200,
  '1200-1600' => rating >= 1200 && rating < 1600,
  '1600-2000' => rating >= 1600 && rating < 2000,
  _ => false,
};

class PuzzlePack {
  PuzzlePack({
    required this.theme,
    required this.band,
    required List<PuzzleProblem> puzzles,
  }) : puzzles = List.unmodifiable(puzzles);

  final String theme;
  final String band;
  final List<PuzzleProblem> puzzles;
  String get title => puzzleThemes[theme]!.title;
}

class PuzzleCatalog {
  PuzzleCatalog(List<PuzzlePack> packs)
    : packs = List.unmodifiable(packs),
      byId = Map.unmodifiable({
        for (final pack in packs)
          for (final puzzle in pack.puzzles) puzzle.id: puzzle,
      });

  final List<PuzzlePack> packs;
  final Map<String, PuzzleProblem> byId;

  static Future<PuzzleCatalog> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final manifest = jsonDecode(
      await assets.loadString('assets/puzzles/manifest.json'),
    ) as Map<String, dynamic>;
    if (manifest['schema'] != 1 || manifest['fenConvention'] != 'after-setup') {
      throw const FormatException('Unsupported puzzle manifest');
    }
    final packs = <PuzzlePack>[];
    final ids = <String>{};
    final strata = <String>{};
    for (final entry in manifest['packs'] as List<dynamic>) {
      final spec = entry as Map<String, dynamic>;
      final theme = spec['theme'] as String;
      final band = spec['band'] as String;
      if (!puzzleThemes.containsKey(theme) ||
          !puzzleBands.containsKey(band) ||
          !strata.add('$theme/$band') ||
          spec['file'] != '${theme}_$band.json') {
        throw const FormatException('Invalid puzzle pack');
      }
      final rows = jsonDecode(
        await assets.loadString('assets/puzzles/${spec['file']}'),
      ) as List<dynamic>;
      final puzzles = <PuzzleProblem>[];
      for (final row in rows) {
        final data = row as Map<String, dynamic>;
        final problem = PuzzleProblem(
          id: data['id'] as String,
          fen: data['fen'] as String,
          line: (data['line'] as List<dynamic>)
              .map((move) => Move.fromUci(move as String))
              .toList(),
          themes: (data['themes'] as List<dynamic>).cast<String>(),
          rating: data['rating'] as int,
        );
        if (problem.id.isEmpty ||
            !ids.add(problem.id) ||
            !problem.themes.contains(theme) ||
            !ratingInBand(problem.rating!, band) ||
            problem.line.length.isEven) {
          throw FormatException('Invalid puzzle: ${problem.id}');
        }
        puzzles.add(problem);
      }
      if (puzzles.isEmpty || puzzles.length != spec['count']) {
        throw const FormatException('Puzzle count mismatch');
      }
      packs.add(PuzzlePack(theme: theme, band: band, puzzles: puzzles));
    }
    if (ids.length != manifest['total'] || ids.length < 10) {
      throw const FormatException('Puzzle total mismatch');
    }
    return PuzzleCatalog(packs);
  }
}
