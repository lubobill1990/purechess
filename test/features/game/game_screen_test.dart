import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/move.dart' as chess;
import 'package:purechess/features/game/game_screen.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:purechess/features/game/game_rail.dart';
import 'package:purechess/features/library/records_repository.dart';
import 'package:purechess/widgets/board/chess_board.dart';

import '../../support/memory_records_repository.dart';

void main() {
  late GameSession session;
  late MemoryRecordsRepository repository;

  setUp(() {
    session = GameSession();
    repository = MemoryRecordsRepository();
  });

  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          session: session,
          openRepository: () async => repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  bool active(WidgetTester tester, String name) =>
      tester.widget<ButtonStyleButton>(key(name)).onPressed != null;

  Future<void> move(WidgetTester tester, String from, String to) async {
    await tester.tap(key('square-$from'), kind: PointerDeviceKind.mouse);
    await tester.tap(key('square-$to'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  testWidgets('black bar faces opponent and actions follow turn', (
    tester,
  ) async {
    await launch(tester);
    expect(tester.widget<RotatedBox>(key('black-player-bar')).quarterTurns, 2);
    expect(active(tester, 'white-resign'), isTrue);
    expect(active(tester, 'white-offer-draw'), isTrue);
    expect(active(tester, 'black-resign'), isFalse);
    expect(active(tester, 'black-offer-draw'), isFalse);
    expect(active(tester, 'white-undo'), isFalse);
    expect(active(tester, 'black-undo'), isFalse);
    await move(tester, 'e2', 'e4');
    expect(active(tester, 'white-resign'), isFalse);
    expect(active(tester, 'black-resign'), isTrue);
    expect(active(tester, 'white-undo'), isTrue);
    expect(active(tester, 'black-undo'), isTrue);
    await tester.tap(key('black-undo'));
    await tester.pumpAndSettle();
    expect(session.moveCount, 0);
    await move(tester, 'd2', 'd4');
    await tester.tap(key('white-undo'));
    await tester.pumpAndSettle();
    expect(session.moveCount, 0);
  });

  testWidgets('draw needs opposite bar confirmation and can be declined', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(key('white-offer-draw'));
    await tester.pumpAndSettle();
    expect(find.text('白方\n等待回应'), findsOneWidget);
    expect(find.text('黑方\n对方提和'), findsOneWidget);
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isFalse);
    expect(key('white-accept-draw'), findsNothing);
    await tester.tap(key('black-decline-draw'));
    await tester.pumpAndSettle();
    expect(session.finished, isFalse);
    await tester.tap(key('white-offer-draw'));
    await tester.pumpAndSettle();
    await tester.tap(key('black-accept-draw'));
    await tester.pumpAndSettle();
    expect(find.text('和棋 · 双方协议'), findsOneWidget);
    expect(active(tester, 'white-resign'), isFalse);
    expect(active(tester, 'black-resign'), isFalse);
    await tester.tap(find.text('保存棋谱'));
    await tester.pumpAndSettle();
    expect(repository.saved.single.result, '1/2-1/2');
  });

  testWidgets('resignation can cancel or confirm, result area does not shift', (
    tester,
  ) async {
    await launch(tester, size: const Size(390, 844));
    final before = tester.getRect(find.byType(ChessBoard));
    final resultHeight = tester.getSize(key('game-result-area')).height;
    await tester.tap(key('white-resign'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(session.finished, isFalse);
    await tester.tap(key('white-resign'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认认输'));
    await tester.pumpAndSettle();
    expect(find.text('黑方胜 · 对方认输'), findsOneWidget);
    expect(tester.getRect(find.byType(ChessBoard)), before);
    expect(tester.getSize(key('game-result-area')).height, resultHeight);
    await tester.tap(find.text('保存棋谱'));
    await tester.pumpAndSettle();
    expect(repository.saved.single.result, '0-1');
    expect(tester.getRect(find.byType(ChessBoard)), before);
    expect(find.textContaining('已保存到我的棋谱'), findsOneWidget);
  });

  testWidgets('save failure is visible and retry stores the same position', (
    tester,
  ) async {
    repository.failSave = true;
    await launch(tester);
    await move(tester, 'e2', 'e4');
    final before = tester.getRect(find.byType(ChessBoard));
    await tester.tap(find.text('保存棋谱'));
    await tester.pumpAndSettle();
    expect(find.textContaining('棋谱保存失败'), findsOneWidget);
    expect(repository.saved, isEmpty);
    expect(tester.getRect(find.byType(ChessBoard)), before);
    repository.failSave = false;
    await tester.tap(find.text('保存棋谱'));
    await tester.pumpAndSettle();
    expect(repository.saved.single.mainLine.last.move!.uci, 'e2e4');
    expect(repository.saved.single.result, '*');
    expect(tester.getRect(find.byType(ChessBoard)), before);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '保存棋谱'))
          .onPressed,
      isNull,
    );
    await move(tester, 'e7', 'e5');
    await tester.tap(find.text('保存棋谱'));
    await tester.pumpAndSettle();
    expect(repository.saved.length, 2);
    expect(repository.saved.last.mainLine.length, 3);
  });

  testWidgets('saving can open library and read stored PGN', (tester) async {
    await launch(tester);
    await move(tester, 'e2', 'e4');
    await tester.tap(find.text('保存棋谱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的棋谱'));
    await tester.pumpAndSettle();
    expect(find.text('对局 1'), findsOneWidget);
    await tester.tap(find.text('对局 1'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('1. e4 *'),
    );
  });

  testWidgets('new game requires confirmation and resets board and selection', (
    tester,
  ) async {
    await launch(tester);
    await move(tester, 'e2', 'e4');
    await tester.tap(find.byTooltip('新对局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(session.moveCount, 1);
    await tester.tap(find.byTooltip('新对局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新开始'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).board.plyCount,
      0,
    );
    expect(find.text('白方\n轮到你'), findsOneWidget);
  });

  testWidgets(
    'flip changes board orientation without swapping player ownership',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byTooltip('翻转棋盘'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).flipped,
        isTrue,
      );
      expect(
        tester.widget<RotatedBox>(key('black-player-bar')).quarterTurns,
        2,
      );
      await move(tester, 'e2', 'e4');
      expect(session.moveCount, 1);
      expect(active(tester, 'black-resign'), isTrue);
    },
  );

  testWidgets('mate displays and undo re-enables play', (tester) async {
    for (final uci in ['f2f3', 'e7e5', 'g2g4']) {
      session.play(chess.Move.fromUci(uci));
    }
    await launch(tester);
    final before = tester.getRect(find.byType(ChessBoard));
    await move(tester, 'd8', 'h4');
    expect(find.text('黑方胜 · 将杀'), findsOneWidget);
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isFalse);
    expect(tester.getRect(find.byType(ChessBoard)), before);
    await tester.tap(key('white-undo'));
    await tester.pumpAndSettle();
    expect(session.finished, isFalse);
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isTrue);
  });

  for (final (fen, message) in [
    ('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1', '和棋 · 逼和'),
    ('7k/8/6K1/8/8/8/8/8 w - - 0 1', '和棋 · 不足子力'),
    ('7k/8/6K1/8/8/8/R7/8 w - - 100 1', '和棋 · 50 步规则'),
  ]) {
    testWidgets('terminal UI displays $message and exports drawn PGN', (
      tester,
    ) async {
      session = GameSession(initialFen: fen);
      await launch(tester);
      expect(find.text(message), findsOneWidget);
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled,
        isFalse,
      );
      await tester.tap(find.text('保存棋谱'));
      await tester.pumpAndSettle();
      expect(repository.saved.single.result, '1/2-1/2');
      expect(repository.saved.single.initialFen, fen);
    });
  }

  testWidgets('third repetition is shown as a terminal draw', (tester) async {
    for (final uci in [
      'g1f3',
      'g8f6',
      'f3g1',
      'f6g8',
      'g1f3',
      'g8f6',
      'f3g1',
    ]) {
      session.play(chess.Move.fromUci(uci));
    }
    await launch(tester);
    await move(tester, 'f6', 'g8');
    expect(find.text('和棋 · 三次重复'), findsOneWidget);
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled, isFalse);
  });

  testWidgets(
    'pending save blocks duplicate saves, new games and board moves',
    (tester) async {
      final pending = Completer<RecordsRepository>();
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            session: session,
            openRepository: () => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await move(tester, 'e2', 'e4');
      await tester.tap(find.text('保存棋谱'));
      await tester.pumpAndSettle();
      expect(find.text('正在保存…'), findsOneWidget);
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled,
        isFalse,
      );
      await tester.tap(find.byTooltip('对局菜单'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GameMenuItem>(find.widgetWithText(GameMenuItem, '新对局'))
            .enabled,
        isFalse,
      );
      await tester.tapAt(const Offset(700, 550));
      await tester.pumpAndSettle();
      expect(active(tester, 'white-undo'), isFalse);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '正在保存…'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(repository);
      await tester.pumpAndSettle();
      expect(repository.saved.length, 1);
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).enabled,
        isTrue,
      );
    },
  );

  testWidgets('unsaved back navigation can cancel or discard', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => GameScreen(
                    session: session,
                    openRepository: () async => repository,
                  ),
                ),
              ),
              child: const Text('打开对弈'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开对弈'));
    await tester.pumpAndSettle();
    await move(tester, 'e2', 'e4');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('离开对局'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(ChessBoard), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃并离开'));
    await tester.pumpAndSettle();
    expect(find.text('打开对弈'), findsOneWidget);
    expect(find.byType(ChessBoard), findsNothing);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets('layout fits $size and result height is always 72', (
      tester,
    ) async {
      await launch(tester, size: size);
      expect(tester.takeException(), isNull);
      final board = tester.getRect(find.byType(ChessBoard));
      expect(board.width, greaterThan(0));
      expect(board.width, board.height);
      expect(board.left, greaterThanOrEqualTo(0));
      expect(board.right, lessThanOrEqualTo(size.width));
      expect(tester.getSize(key('game-result-area')).height, 72);
      await tester.tap(key('white-offer-draw'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(ChessBoard)), board);
    });
  }
}
