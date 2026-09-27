import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/game_tree.dart';
import 'package:purechess/core/pgn.dart';

Object treeShape(GameNode node) => [
  node.move?.uci,
  node.startingComments,
  node.comments,
  node.nags,
  node.children.map(treeShape).toList(),
];

void expectRoundTrip(GameRecord record) {
  final exported = Pgn.generate(record);
  final restored = Pgn.parse(exported);
  expect(restored.initialFen, record.initialFen);
  expect(restored.result, record.result);
  for (final entry in record.tags.entries) {
    expect(restored.tags[entry.key], entry.value);
  }
  expect(treeShape(restored.root), treeShape(record.root));
  expect(Pgn.generate(restored), exported);
  for (final node in restored.root.descendantsAndSelf) {
    expect(restored.boardAt(node).toFen(), isNotEmpty);
  }
}

void main() {
  const complex = r'''
[Event "Club \"A\" \\ round"]
[Site "Local"]
[Date "2026.09.28"]
[Round "1"]
[White "Alice"]
[Black "Bob"]
[Result "1-0"]
[Custom "preserved"]

{Opening note} 1.e4! {Center}
({Before d4} 1.d4 d5 (1...Nf6 $5 {Indian}) 2.c4)
1...e5 2.Nf3 (2.Bc4 Nf6) 2...Nc6 3.Bb5 a6 1-0
''';
  group('PGN import/export', () {
    test('nested variations, tags, comments, NAGs and result round trip', () {
      final record = Pgn.parse(complex);
      expect(record.tags['Event'], r'Club "A" \ round');
      expect(record.tags['Custom'], 'preserved');
      expect(record.root.comments, ['Opening note']);
      expect(record.root.children.length, 2);
      expect(record.root.children.first.nags, [1]);
      final d4 = record.root.children[1];
      expect(d4.startingComments, ['Before d4']);
      expect(d4.children.length, 2);
      expect(d4.children[1].move!.uci, 'g8f6');
      expect(d4.children[1].nags, [5]);
      expect(record.mainLine.map((n) => n.move?.uci).toList(), [
        null,
        'e2e4',
        'e7e5',
        'g1f3',
        'b8c6',
        'f1b5',
        'a7a6',
      ]);
      expectRoundTrip(record);
    });
    for (final result in GameRecord.results) {
      test('result $result with tags round trip', () {
        final record = Pgn.parse('[Result "$result"]\n1. e4 e5 $result');
        expect(record.result, result);
        expectRoundTrip(record);
      });
    }
    test('multiple sibling variations and nested alternatives', () {
      final record = Pgn.parse('1.e4 (1.d4 d5 (1...Nf6) (1...e6)) (1.c4) e5 *');
      expect(record.root.children.length, 3);
      expect(record.root.children[1].children.length, 3);
      expectRoundTrip(record);
    });
    test('starting comments survive promotion to the main line', () {
      final record = Pgn.parse(
        '{root} 1.e4 ({d4 introduction} 1.d4 d5 '
        '({Nf6 introduction} 1...Nf6)) e5 *',
      );
      final d4 = record.root.children[1];
      record.promoteVariation(d4);
      record.promoteVariation(d4.children[1]);
      expectRoundTrip(record);
    });
    test('comments between number and SAN belong to the following move', () {
      final record = Pgn.parse('1. {first} e4 1... {second} e5 *');
      expect(record.mainLine[1].startingComments, ['first']);
      expect(record.mainLine[2].startingComments, ['second']);
      expect(record.root.comments, isEmpty);
      expectRoundTrip(record);
    });
    test('semicolon comments preserve contents', () {
      final record = Pgn.parse(';intro\n1.e4 ;after e4\n e5 *');
      expect(record.root.comments, ['intro']);
      expect(record.root.children.first.comments, ['after e4']);
      expectRoundTrip(record);
    });
    test('semicolon comment with closing brace round trips', () {
      final record = Pgn.parse('1.e4 ;literal } character\n *');
      expectRoundTrip(record);
    });
    test('Unicode and multiline comments', () {
      final record = Pgn.parse('[Event "国际象棋"]\n{第一行\n第二行} 1.e4 {中心控制} *');
      expect(record.tags['Event'], '国际象棋');
      expectRoundTrip(record);
    });
    test('empty game retains root comment and result', () {
      final record = Pgn.parse('{No moves} 1/2-1/2');
      expect(record.mainLine.length, 1);
      expectRoundTrip(record);
    });
    test('custom FEN with black to move and numbering', () {
      final record = Pgn.parse('''
[SetUp "1"]
[FEN "7k/8/8/8/8/8/4p3/K7 b - - 0 23"]
[Result "*"]

23... e1=Q+ (23...e1=N) 24.Kb2 *
''');
      expect(record.root.children.first.move!.uci, 'e2e1q');
      expect(Pgn.generate(record), contains('23... e1=Q+'));
      expectRoundTrip(record);
    });
    test('FEN without SetUp is accepted and exported with SetUp', () {
      final record = Pgn.parse(
        '[FEN "7k/8/8/8/8/8/4p3/K7 b - - 0 23"] 23...e1=N *',
      );
      expect(Pgn.generate(record), contains('[SetUp "1"]'));
      expectRoundTrip(record);
    });
    test('redundant initial FEN and SetUp tags are preserved', () {
      final record = Pgn.parse('[SetUp "1"] [FEN "${Fen.initial}"] 1.e4 *');
      expectRoundTrip(record);
    });
    test('explicit SetUp zero tag is preserved', () {
      expectRoundTrip(Pgn.parse('[SetUp "0"] 1.e4 *'));
    });
    test('promotion checkmate notation is preserved', () {
      final record = Pgn.parse('''
[SetUp "1"]
[FEN "7k/4P1pp/8/5K2/8/8/8/8 w - - 0 1"]
[Result "1-0"]
1.e8=Q# 1-0
''');
      expect(Pgn.generate(record), contains('e8=Q#'));
      expectRoundTrip(record);
    });
    test('castling and en passant PGN', () {
      final castle = Pgn.parse('''
[FEN "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"]
1.O-O O-O-O *
''');
      final ep = Pgn.parse('''
[FEN "7k/8/8/3pP3/8/8/8/K7 w - d6 0 1"]
1.exd6 *
''');
      expectRoundTrip(castle);
      expectRoundTrip(ep);
    });
    test('all symbolic NAGs normalize to numeric form', () {
      final record = Pgn.parse('1.e4! e5? 2.Nf3!! Nc6?? 3.Bb5!? a6?! *');
      expect(record.mainLine.skip(1).map((n) => n.nags.single), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expectRoundTrip(record);
    });
    test('separate NAGs and arbitrary standard numeric NAG', () {
      final record = Pgn.parse(r'1.e4 ! $14 e5 $0 $255 *');
      expect(record.root.children.first.nags, [1, 14]);
      expectRoundTrip(record);
    });
    test('numeric NAGs are self-delimiting without whitespace', () {
      final record = Pgn.parse(r'1.e4$1$14 e5$0 *');
      expect(record.root.children.first.nags, [1, 14]);
      expectRoundTrip(record);
    });
    test('asterisk termination is self-delimiting', () {
      expectRoundTrip(Pgn.parse('1.e4*'));
    });
    test('missing termination is an in-progress fragment', () {
      final record = Pgn.parse('1.e4 e5');
      expect(record.result, '*');
      expectRoundTrip(record);
    });
    test('comments after result are retained on final node', () {
      final record = Pgn.parse('1.e4 1-0 {Resigned}');
      expect(record.mainLine.last.comments, ['Resigned']);
      expectRoundTrip(record);
    });
    test('BOM and percent escape lines are accepted', () {
      final record = Pgn.parse('\uFEFF[Event "Test"]\n%ignored\n1.e4 *');
      expect(record.initialFen, Fen.initial);
      expectRoundTrip(record);
    });
    test('collection supports multiple games', () {
      final games = Pgn.parseGames('1.e4 1-0\n[Event "Second"]\n1.d4 0-1');
      expect(games.length, 2);
      expect(games[1].tags['Event'], 'Second');
      for (final game in games) {
        expectRoundTrip(game);
      }
    });
    test('empty collection is empty, single-game parser rejects it', () {
      expect(Pgn.parseGames(' \n'), isEmpty);
      expect(() => Pgn.parse(''), throwsFormatException);
    });
    test('single-game parser rejects multiple games', () {
      expect(() => Pgn.parse('1.e4 * 1.d4 *'), throwsFormatException);
    });
  });
  group('PGN errors are explicit', () {
    for (final entry in [
      ('unterminated comment', '1.e4 {missing'),
      ('unterminated tag', '[Event "missing] 1.e4 *'),
      ('invalid tag escape', r'[Event "bad\q"] *'),
      ('duplicate tag', '[Event "A"] [Event "B"] *'),
      ('unknown result', '[Result "draw"] *'),
      ('result mismatch', '[Result "1-0"] 1.e4 0-1'),
      ('missing setup FEN', '[SetUp "1"] *'),
      ('invalid setup', '[SetUp "2"] *'),
      ('conflicting setup', '[SetUp "0"] [FEN "${Fen.initial}"] *'),
      ('invalid FEN', '[FEN "bad"] *'),
      ('illegal SAN', '1.e5 *'),
      ('bad move number', '2.e4 *'),
      ('wrong move side', '1...e4 *'),
      ('unclosed variation', '1.e4 (1.d4 *'),
      ('extra close', '1.e4 ) *'),
      ('empty variation', '1.e4 () *'),
      ('variation before move', '(1.e4) *'),
      ('result in variation', '1.e4 (1.d4 1-0) *'),
      ('nag before move', r'$1 1.e4 *'),
      ('nag out of range', r'1.e4 $256 *'),
      ('empty numeric nag', r'1.e4 $ *'),
      ('dangling move number', '1.e4 e5 2.'),
      ('move number before result', '1. *'),
      ('duplicate move number', '1. 1.e4 *'),
      ('invalid annotation', '1.e4!!! *'),
      ('unexpected brace', '1.e4 } *'),
      ('missing result between games', '1.e4 [Event "Next"] 1.d4 *'),
      ('illegal branch', '1.e4 (1.d5) *'),
    ]) {
      test(entry.$1, () {
        expect(() => Pgn.parse(entry.$2), throwsFormatException);
      });
    }
    test('invalid edited tag name is rejected during export', () {
      final record = GameRecord(tags: {'bad name': 'x'});
      expect(() => Pgn.generate(record), throwsArgumentError);
    });
    test('invalid edited result is rejected during export', () {
      final record = GameRecord()..tags['Result'] = 'draw';
      expect(() => Pgn.generate(record), throwsArgumentError);
    });
    test('invalid edited NAG is rejected during export', () {
      final record = Pgn.parse('1.e4 *');
      record.mainLine.last.nags.add(-1);
      expect(() => Pgn.generate(record), throwsArgumentError);
    });
  });
}
