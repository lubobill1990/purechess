import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/game_tree.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/core/pgn.dart';

void main() {
  test('record starts at root and deduplicates replay', () {
    final record = GameRecord();
    final first = record.addSan(record.root, 'e4');
    expect(record.addSan(record.root, 'e4'), same(first));
    expect(record.root.children.length, 1);
    expect(first.parent, same(record.root));
    expect(first.ply, 1);
    expect(first.pathFromRoot, [record.root, first]);
  });
  test('branches compute independent legal positions', () {
    final record = GameRecord();
    final e4 = record.addSan(record.root, 'e4');
    final d4 = record.addSan(record.root, 'd4');
    final e5 = record.addSan(e4, 'e5');
    expect(
      record.boardAt(e5).toFen(),
      (Board()
            ..playUci('e2e4')
            ..playUci('e7e5'))
          .toFen(),
    );
    expect(record.boardAt(d4).toFen(), (Board()..playUci('d2d4')).toFen());
    expect(record.boardAt(record.root).toFen(), Fen.initial);
    expect(record.root.descendantsAndSelf.length, 4);
    expect(record.mainLine, [record.root, e4, e5]);
  });
  test('external mutation of returned board is isolated', () {
    final record = GameRecord();
    final node = record.addSan(record.root, 'e4');
    record.boardAt(node).playUci('e7e5');
    expect(record.boardAt(node).turn, Color.black);
  });
  test('children cannot bypass validation', () {
    final record = GameRecord();
    expect(() => record.root.children.clear(), throwsUnsupportedError);
  });
  test('illegal add does not modify tree', () {
    final record = GameRecord();
    expect(
      () => record.addMove(record.root, Move.fromUci('e2e5')),
      throwsA(isA<IllegalMoveException>()),
    );
    expect(record.root.isLeaf, isTrue);
  });
  test('foreign nodes are rejected', () {
    final a = GameRecord();
    final b = GameRecord();
    expect(() => a.boardAt(b.root), throwsArgumentError);
    expect(() => a.addSan(b.root, 'e4'), throwsArgumentError);
    expect(() => GameCursor(a).goTo(b.root), throwsArgumentError);
  });
  test('promote variation changes main line without losing siblings', () {
    final record = Pgn.parse('1.e4 (1.d4 d5) e5 *');
    final d4 = record.root.children[1];
    record.promoteVariation(d4);
    expect(record.mainLine[1], same(d4));
    expect(record.mainLine.last.move!.uci, 'd7d5');
    expect(record.root.children.length, 2);
    expect(Pgn.generate(record), contains('(1. e4 1... e5)'));
  });
  test('remove variation detaches entire subtree', () {
    final record = Pgn.parse('1.e4 (1.d4 d5) e5 *');
    final d4 = record.root.children[1];
    final d5 = d4.children.first;
    record.removeVariation(d4);
    expect(record.root.children.length, 1);
    expect(d4.parent, isNull);
    expect(() => record.boardAt(d5), throwsArgumentError);
  });
  test('cannot remove or promote root', () {
    final record = GameRecord();
    expect(() => record.removeVariation(record.root), throwsArgumentError);
    expect(() => record.promoteVariation(record.root), throwsArgumentError);
  });
  test('cursor navigates main line and alternatives', () {
    final record = Pgn.parse('1.e4 (1.d4) e5 *');
    final cursor = GameCursor(record);
    expect(cursor.back(), isFalse);
    expect(cursor.forward(variation: 1), isTrue);
    expect(cursor.current.move!.uci, 'd2d4');
    expect(cursor.forward(), isFalse);
    expect(cursor.back(), isTrue);
    cursor.forward();
    cursor.forward();
    expect(cursor.current.move!.uci, 'e7e5');
    expect(cursor.board.turn, Color.white);
    cursor.goTo(record.root);
    expect(cursor.board.toFen(), Fen.initial);
  });
  test('cursor editing reuses existing moves', () {
    final record = GameRecord();
    final cursor = GameCursor(record);
    final e4 = cursor.playSan('e4');
    cursor.back();
    expect(cursor.playSan('e4'), same(e4));
    cursor.back();
    cursor.playSan('d4');
    expect(record.root.children.length, 2);
  });
  test('cursor invalid variation index is explicit', () {
    final cursor = GameCursor(Pgn.parse('1.e4 *'));
    expect(() => cursor.forward(variation: 2), throwsRangeError);
    expect(() => cursor.forward(variation: -1), throwsRangeError);
  });
  test('tree replay preserves repetition history', () {
    final record = Pgn.parse('1.Nf3 Nf6 2.Ng1 Ng8 3.Nf3 Nf6 4.Ng1 Ng8 *');
    final board = record.boardAt(record.mainLine.last);
    expect(board.isThreefoldRepetition, isTrue);
    expect(board.plyCount, 8);
  });
  test('result setter validates values', () {
    final record = GameRecord();
    record.result = '1/2-1/2';
    expect(record.tags['Result'], '1/2-1/2');
    expect(() => record.result = 'draw', throwsArgumentError);
  });
}
