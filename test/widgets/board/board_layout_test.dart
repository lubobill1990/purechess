import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/app_theme.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/features/game/ai_difficulty.dart';
import 'package:purechess/features/game/ai_game_screen.dart';
import 'package:purechess/features/game/game_screen.dart';
import 'package:purechess/features/game/game_session.dart';
import 'package:purechess/features/game/review_screen.dart';
import 'package:purechess/features/library/classic_library.dart';
import 'package:purechess/features/library/classic_reader_screen.dart';
import 'package:purechess/features/puzzle/puzzle_repository.dart';
import 'package:purechess/features/puzzle/puzzle_screen.dart';
import 'package:purechess/features/tutorial/tutorial_controller.dart';
import 'package:purechess/features/tutorial/tutorial_engine.dart';
import 'package:purechess/features/tutorial/tutorial_level.dart';
import 'package:purechess/features/tutorial/tutorial_screen.dart';
import 'package:purechess/widgets/board/board_panel.dart';
import 'package:purechess/widgets/board/chess_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/game/fake_game_engine.dart';
import '../../features/puzzle/fixtures.dart' as puzzles;

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 1366),
    const Size(768, 800),
  ]) {
    for (final screen in [
      'local',
      'ai',
      'puzzle',
      'tutorial',
      'review',
      'reader',
    ]) {
      testWidgets('$screen fills short edge at $size with joined rails', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        late Widget home;
        switch (screen) {
          case 'local':
            home = GameScreen(prefs: prefs);
          case 'ai':
            home = AiGameScreen(
              config: AiGameConfig(),
              rating: AiDifficulty(prefs),
              engine: FakeGameEngine(),
            );
          case 'puzzle':
            final repository = PuzzleRepository(
              prefs: prefs,
              catalog: puzzles.catalog(),
            );
            addTearDown(repository.dispose);
            home = PuzzleSolveScreen(repository: repository, ids: const ['p0']);
          case 'tutorial':
            final catalog = (await tester.runAsync(TutorialCatalog.load))!;
            final controller = TutorialController(
              prefs: prefs,
              catalog: catalog,
              engine: FakeEngine(),
            )..start(0);
            addTearDown(controller.dispose);
            home = TutorialPlayScreen(controller: controller);
          case 'review':
            home = ReviewScreen(
              record: Pgn.parse('1. e4 e5 *'),
              engine: FakeGameEngine(),
            );
          case 'reader':
            final classics = (await tester.runAsync(ClassicLibrary.load))!;
            home = ClassicReaderScreen(prefs: prefs, game: classics.first);
        }
        await tester.pumpWidget(
          MaterialApp(theme: buildLightTheme(), home: home),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final panel = tester.getRect(find.byType(BoardPanel));
        final board = tester.getRect(find.byType(ChessBoard));
        final landscape = panel.width > panel.height;
        const m = BoardPanel.margin;
        // Near-full use of the short edge with a breathing margin around the
        // framed panel.
        expect(
          board.size,
          Size.square((landscape ? panel.height : panel.width) - m * 2),
        );
        expect(board.left, panel.left + m);
        if (landscape) {
          expect(board.top, panel.top + m);
          expect(board.bottom, panel.bottom - m);
        } else {
          expect(board.width, size.width - m * 2);
          expect(board.right, panel.right - m);
        }
        final rails = tester
            .widgetList<BoardRail>(find.byType(BoardRail))
            .map((rail) => tester.getRect(find.byWidget(rail)))
            .toList();
        expect(rails, isNotEmpty);
        expect(
          rails.any(
            (rail) => landscape
                ? rail.left == board.right + m + 2
                : rail.width == board.width &&
                      (rail.bottom == board.top || rail.top == board.bottom),
          ),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('face-to-face lift follows the player, not flipped coordinates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final session = GameSession();
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: session)));
    await tester.pumpAndSettle();
    ChessBoard board() => tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board().flipFingerOffset, isFalse);
    await tester.tap(
      find.byKey(const ValueKey('square-e2')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.tap(
      find.byKey(const ValueKey('square-e4')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(board().flipFingerOffset, isTrue);
    await tester.tap(find.byTooltip('翻转棋盘'));
    await tester.pumpAndSettle();
    expect(board().flipFingerOffset, isTrue);
    final rect = tester.getRect(find.byType(ChessBoard));
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('square-e7'))),
    );
    await pointer.moveTo(
      tester.getCenter(find.byKey(const ValueKey('square-e5'))) -
          Offset(0, rect.width / 8 * 1.5),
    );
    await tester.pump();
    expect(session.moveCount, 1);
    expect(tester.getRect(find.byType(ChessBoard)), rect);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(session.moveCount, 2);
    expect(board().flipFingerOffset, isFalse);
    expect(tester.getRect(find.byType(ChessBoard)), rect);
  });
}
