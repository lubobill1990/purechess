import 'package:purechess/core/fen.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/puzzle.dart';
import 'package:purechess/features/puzzle/puzzle_catalog.dart';

PuzzleProblem practice({String id = 'practice'}) => PuzzleProblem(
  id: id,
  fen: Fen.initial,
  line: ['e2e4', 'e7e5', 'g1f3'].map(Move.fromUci).toList(),
  themes: ['fork'],
  rating: 1000,
);

PuzzleProblem mate({bool black = false}) => PuzzleProblem(
  id: black ? 'black-mate' : 'white-mate',
  fen: black
      ? '8/8/8/8/8/6k1/5q2/7K b - - 0 1'
      : '7k/5Q2/6K1/8/8/8/8/8 w - - 0 1',
  line: [Move.fromUci(black ? 'f2g2' : 'f7g7')],
  themes: ['mateIn1'],
  rating: 900,
);

PuzzleCatalog catalog() => PuzzleCatalog([
  PuzzlePack(
    theme: 'fork',
    band: 'under1200',
    puzzles: List.generate(24, (index) => practice(id: 'p$index')),
  ),
]);
