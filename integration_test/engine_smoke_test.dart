import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device/simulator smoke: the full mobile Stockfish startup path that the
/// TestFlight build exercises. Prints the complete error chain on failure so
/// the "AI 启动失败" report can be diagnosed with real evidence.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile stockfish starts, searches, restarts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = StockfishService();
    try {
      await service.ensureStarted();
    } catch (error, stack) {
      // ignore: avoid_print
      print('ENGINE-SMOKE FAILURE: $error');
      // ignore: avoid_print
      print('ENGINE-SMOKE LAST: ${service.lastError}');
      // ignore: avoid_print
      print(stack);
      rethrow;
    }
    expect(service.state, StockfishState.ready);
    // ignore: avoid_print
    print('ENGINE-SMOKE READY name=${service.engineName}');

    final analysis = await service.analyzePosition(
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      difficulty: 3,
    );
    // ignore: avoid_print
    print('ENGINE-SMOKE ANALYSIS $analysis');

    // Second session: stop and restart exercises the single-instance native
    // path (leave a game -> start a new one), a prime suspect on device.
    await service.stop();
    await service.ensureStarted();
    expect(service.state, StockfishState.ready);
    // ignore: avoid_print
    print('ENGINE-SMOKE RESTART OK');
    await service.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
