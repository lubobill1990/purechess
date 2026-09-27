import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/widgets/board/chess_board.dart';

void main() {
  Finder square(String name) => find.byKey(ValueKey('square-$name'));
  late Board board;
  late List<chess.Move> moves;
  late StateSetter rebuild;
  bool flipped = false;
  bool enabled = true;

  setUp(() {
    board = Board();
    moves = [];
    flipped = false;
    enabled = true;
  });

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return ChessBoard(
                    board: board,
                    flipped: flipped,
                    enabled: enabled,
                    onMove: (move) => setState(() {
                      moves.add(move);
                      board.play(move);
                    }),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoardPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<BoardPainter>()
      .single;

  testWidgets(
    'painter raster contains alternating squares and all highlights',
    (tester) async {
      await tester.runAsync(() async {
        for (final flipped in [false, true]) {
          final recorder = ui.PictureRecorder();
          final painter = BoardPainter(
            flipped: flipped,
            selected: chess.parseSquare('e2'),
            targets: {chess.parseSquare('e3')},
            lastMove: chess.Move.fromUci('e2e4'),
            checkedKing: chess.parseSquare('e8'),
          );
          painter.paint(Canvas(recorder), const Size(400, 400));
          final picture = recorder.endRecording();
          final image = await picture.toImage(400, 400);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          Color pixel(int x, int y) {
            final index = (y * 400 + x) * 4;
            return Color.fromARGB(
              bytes.getUint8(index + 3),
              bytes.getUint8(index),
              bytes.getUint8(index + 1),
              bytes.getUint8(index + 2),
            );
          }

          Color center(String name) {
            final square = chess.parseSquare(name);
            final col = flipped ? 7 - (square & 7) : square & 7;
            final row = flipped ? square >> 4 : 7 - (square >> 4);
            return pixel(col * 50 + 25, row * 50 + 25);
          }

          void expectColor(Color actual, Color expected) {
            expect(actual.r * 255, closeTo(expected.r * 255, 1));
            expect(actual.g * 255, closeTo(expected.g * 255, 1));
            expect(actual.b * 255, closeTo(expected.b * 255, 1));
          }

          expect(center('a8'), BoardPainter.lightSquare);
          expect(center('b8'), BoardPainter.darkSquare);
          for (final name in ['e2', 'e4']) {
            expectColor(
              center(name),
              Color.alphaBlend(
                const Color(0x80E7BC54),
                BoardPainter.lightSquare,
              ),
            );
          }
          expectColor(
            center('e8'),
            Color.alphaBlend(const Color(0xDDCE5964), BoardPainter.lightSquare),
          );
          expectColor(
            center('e3'),
            Color.alphaBlend(const Color(0xA0233648), BoardPainter.darkSquare),
          );
          expect(flipped ? pixel(152, 75) : pixel(202, 325), BoardPainter.ink);
          image.dispose();
          picture.dispose();
        }
      });
    },
  );

  testWidgets('renders 64 accessible squares and 32 bundled SVG pieces', (
    tester,
  ) async {
    await launch(tester);
    expect(find.byType(SvgPicture), findsNWidgets(32));
    for (var rank = 1; rank <= 8; rank++) {
      for (final file in 'abcdefgh'.split('')) {
        expect(square('$file$rank'), findsOneWidget);
      }
    }
    expect(
      tester.getTopLeft(square('a8')).dx,
      lessThan(tester.getTopLeft(square('h8')).dx),
    );
    expect(
      tester.getTopLeft(square('a8')).dy,
      lessThan(tester.getTopLeft(square('a1')).dy),
    );
    for (final side in ['w', 'b']) {
      for (final type in 'PNBRQK'.split('')) {
        final svg = await rootBundle.loadString('assets/pieces/$side$type.svg');
        expect(svg, contains('<svg'));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap selects only own pieces, shows legal targets and moves', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(square('e7'));
    await tester.pump();
    expect(painter(tester).selected, isNull);
    await tester.tap(square('e2'));
    await tester.pump();
    expect(painter(tester).selected, chess.parseSquare('e2'));
    expect(painter(tester).targets, {
      chess.parseSquare('e3'),
      chess.parseSquare('e4'),
    });
    expect(
      tester.widget<Semantics>(square('e4')).properties.label,
      contains('合法着点'),
    );
    await tester.tap(square('e4'));
    await tester.pumpAndSettle();
    expect(moves.single.uci, 'e2e4');
    expect(painter(tester).selected, isNull);
    expect(painter(tester).targets, isEmpty);
    expect(painter(tester).lastMove, moves.single);
    expect(board.turn, chess.Color.black);
  });

  testWidgets('reselect, deselect and illegal destinations never commit', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(square('e2'));
    await tester.tap(square('d2'));
    await tester.pump();
    expect(painter(tester).selected, chess.parseSquare('d2'));
    await tester.tap(square('d2'));
    await tester.pump();
    expect(painter(tester).selected, isNull);
    await tester.tap(square('e2'));
    await tester.tap(square('e5'));
    await tester.pump();
    expect(moves, isEmpty);
    expect(board.toFen(), Fen.initial);
  });

  for (final flip in [false, true]) {
    testWidgets('drag commits correct move with flipped=$flip', (tester) async {
      flipped = flip;
      await launch(tester);
      await tester.dragFrom(
        tester.getCenter(square('e2')),
        tester.getCenter(square('e4')) - tester.getCenter(square('e2')),
      );
      await tester.pumpAndSettle();
      expect(moves.single.uci, 'e2e4');
      await tester.dragFrom(
        tester.getCenter(square('e7')),
        tester.getCenter(square('e5')) - tester.getCenter(square('e7')),
      );
      await tester.pumpAndSettle();
      expect(moves.last.uci, 'e7e5');
    });
  }

  testWidgets(
    'offboard, illegal and cancelled drags leave position unchanged',
    (tester) async {
      await launch(tester);
      await tester.dragFrom(
        tester.getCenter(square('e2')),
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getCenter(square('e2')),
        tester.getCenter(square('e5')) - tester.getCenter(square('e2')),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(square('e2')));
      await gesture.moveBy(const Offset(0, -50));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(moves, isEmpty);
      expect(board.toFen(), Fen.initial);
    },
  );

  testWidgets('flip remaps squares, clears selection and keeps correct taps', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(square('e2'));
    rebuild(() => flipped = true);
    await tester.pumpAndSettle();
    expect(painter(tester).selected, isNull);
    expect(
      tester.getTopLeft(square('h1')).dx,
      lessThan(tester.getTopLeft(square('a1')).dx),
    );
    expect(
      tester.getTopLeft(square('h1')).dy,
      lessThan(tester.getTopLeft(square('h8')).dy),
    );
    await tester.tap(square('e2'));
    await tester.tap(square('e4'));
    await tester.pumpAndSettle();
    expect(moves.single.uci, 'e2e4');
  });

  testWidgets('disabled board blocks both gestures and semantic activation', (
    tester,
  ) async {
    enabled = false;
    await launch(tester);
    await tester.tap(square('e2'));
    await tester.tap(square('e4'));
    await tester.dragFrom(
      tester.getCenter(square('e2')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(moves, isEmpty);
    expect(tester.widget<Semantics>(square('e2')).properties.onTap, isNull);
  });

  testWidgets('selection invalidates when parent mutates same board instance', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(square('e2'));
    rebuild(() => board.playUci('d2d4'));
    await tester.pumpAndSettle();
    expect(painter(tester).selected, isNull);
    expect(painter(tester).lastMove!.uci, 'd2d4');
  });

  testWidgets('check highlighter and legal targets exclude pinned moves', (
    tester,
  ) async {
    board = Board.fromFen('4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1');
    await launch(tester);
    await tester.tap(square('e2'));
    await tester.pump();
    expect(painter(tester).targets.contains(chess.parseSquare('d2')), isFalse);
    rebuild(() => board = Board.fromFen('4r2k/8/8/8/8/8/8/4K3 w - - 0 1'));
    await tester.pumpAndSettle();
    expect(painter(tester).checkedKing, chess.parseSquare('e1'));
    expect(
      tester.widget<Semantics>(square('e1')).properties.label,
      contains('将军'),
    );
  });

  for (final type in [
    chess.PieceType.queen,
    chess.PieceType.rook,
    chess.PieceType.bishop,
    chess.PieceType.knight,
  ]) {
    testWidgets('promotion explicitly chooses ${type.name}', (tester) async {
      board = Board.fromFen('7k/P7/8/8/8/8/8/7K w - - 0 1');
      await launch(tester);
      await tester.tap(square('a7'));
      await tester.tap(square('a8'));
      await tester.pumpAndSettle();
      expect(find.text('选择升变棋子'), findsOneWidget);
      expect(moves, isEmpty);
      await tester.tap(find.byKey(ValueKey('promotion-${type.name}')));
      await tester.pumpAndSettle();
      expect(moves.single.promotion, type);
      expect(board.pieceAt(chess.parseSquare('a8'))!.type, type);
    });
  }

  testWidgets('drag promotion cancellation never auto-queens', (tester) async {
    board = Board.fromFen('7k/P7/8/8/8/8/8/7K w - - 0 1');
    final fen = board.toFen();
    await launch(tester);
    await tester.dragFrom(tester.getCenter(square('a7')), const Offset(0, -50));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(board.toFen(), fen);
    expect(moves, isEmpty);
  });

  testWidgets('stale promotion cannot commit after parent changes position', (
    tester,
  ) async {
    board = Board.fromFen('7k/P7/8/8/8/8/8/7K w - - 0 1');
    await launch(tester);
    await tester.tap(square('a7'));
    await tester.tap(square('a8'));
    await tester.pumpAndSettle();
    rebuild(() => board = Board());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promotion-queen')));
    await tester.pumpAndSettle();
    expect(moves, isEmpty);
    expect(board.toFen(), Fen.initial);
  });

  for (final (fen, from, to, removed, added) in [
    ('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', 'e1', 'g1', 'h1', 'f1'),
    ('7k/8/8/3pP3/8/8/8/K7 w - d6 0 2', 'e5', 'd6', 'd5', 'd6'),
    ('7k/8/8/8/8/8/r7/R6K w - - 0 1', 'a1', 'a2', 'a1', 'a2'),
  ]) {
    testWidgets('special move $from$to updates every affected piece', (
      tester,
    ) async {
      board = Board.fromFen(fen);
      await launch(tester);
      await tester.tap(square(from));
      await tester.tap(square(to));
      await tester.pumpAndSettle();
      expect(moves.single.uci, '$from$to');
      expect(board.pieceAt(chess.parseSquare(removed)), isNull);
      expect(board.pieceAt(chess.parseSquare(added))!.color, chess.Color.white);
    });
  }
}
