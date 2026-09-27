import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/move.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/engine/uci_protocol.dart';
import 'package:purechess/features/tutorial/tutorial_engine.dart';

class RecordingService extends StockfishService {
  String? receivedFen;
  int? receivedDifficulty;
  String? move = 'e7e5';
  bool closed = false;

  @override
  Future<PositionAnalysis> analyzePosition(
    String fen, {
    int difficulty = 5,
    int? depth,
  }) async {
    receivedFen = fen;
    receivedDifficulty = difficulty;
    return PositionAnalysis(
      score: const UciScore(UciScoreKind.cp, 0),
      bestMove: move,
      bestLine: move == null ? [] : [move!],
      depth: 1,
    );
  }

  @override
  Future<void> dispose() async {
    closed = true;
    await super.dispose();
  }
}

void main() {
  test(
    'real AI adapter requests lowest difficulty and closes owned service',
    () async {
      final service = RecordingService();
      final engine = TutorialAi(service);
      final board = Board()..play(Move.fromUci('e2e4'));
      final reply = await engine.chooseMove(board);
      expect(service.receivedDifficulty, 1);
      expect(service.receivedFen, board.toFen());
      expect(board.isLegal(reply), isTrue);
      await engine.dispose();
      expect(service.closed, isTrue);
    },
  );

  test(
    'missing AI move is an explicit failure for the fallback handler',
    () async {
      final service = RecordingService()..move = null;
      final engine = TutorialAi(service);
      await expectLater(
        engine.chooseMove(Board()),
        throwsA(isA<StockfishException>()),
      );
      await engine.dispose();
    },
  );
}
