import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/sound.dart';
import 'package:purechess/core/board.dart';
import 'package:purechess/core/move.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late List<String> calls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemSound.play') {
            calls.add(call.arguments as String);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'forward moves classify capture, en passant, castling and promotion',
    () {
      void expectMove(String fen, String uci, ChessSound expected) {
        final before = Board.fromFen(fen);
        final after = before.copy()..play(Move.fromUci(uci));
        expect(soundsForBoards(before, after), [expected], reason: uci);
        expect(soundsForBoards(after, before), isEmpty);
        expect(soundsForBoards(before, before.copy()), isEmpty);
      }

      expectMove(Board().toFen(), 'e2e4', ChessSound.move);
      expectMove(
        '4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1',
        'e4d5',
        ChessSound.capture,
      );
      expectMove(
        '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
        'e5d6',
        ChessSound.capture,
      );
      expectMove('4k3/8/8/8/8/8/8/4K2R w K - 0 1', 'e1g1', ChessSound.move);
      expectMove('8/P7/7k/8/8/8/8/4K3 w - - 0 1', 'a7a8q', ChessSound.move);
      expectMove('4k3/8/8/8/8/8/8/R3K3 w - - 0 1', 'a1a8', ChessSound.check);
      expectMove(
        '7k/5Q2/6K1/8/8/8/8/8 w - - 0 1',
        'f7g7',
        ChessSound.checkmate,
      );
    },
  );

  test('coalesced human and AI plies retained; unrelated positions silent', () {
    final before = Board();
    final after = before.copy()
      ..play(Move.fromUci('e2e4'))
      ..play(Move.fromUci('d7d5'))
      ..play(Move.fromUci('e4d5'));
    expect(soundsForBoards(before, after), [
      ChessSound.move,
      ChessSound.move,
      ChessSound.capture,
    ]);
    final unrelated = Board()..play(Move.fromUci('a2a4'));
    expect(soundsForBoards(unrelated, after), isEmpty);
  });

  testWidgets('every cue uses a distinct, precisely timed click rhythm', (
    tester,
  ) async {
    expect(
      soundPulses.values.map((value) => value.join(',')).toSet(),
      hasLength(ChessSound.values.length),
    );
    final service = SoundService(prefs: prefs);
    addTearDown(service.dispose);
    for (final sound in ChessSound.values) {
      calls.clear();
      await service.play([sound], isCurrent: () => true);
      expect(calls, ['SystemSoundType.click']);
      final pulses = soundPulses[sound]!;
      for (var i = 1; i < pulses.length; i++) {
        await tester.pump(
          Duration(milliseconds: pulses[i] - pulses[i - 1] - 1),
        );
        expect(calls.length, i);
        await tester.pump(const Duration(milliseconds: 1));
        expect(calls.length, i + 1);
      }
    }
  });

  testWidgets('mute cancels a running cue and stays silent after reopening', (
    tester,
  ) async {
    final service = SoundService(prefs: prefs);
    addTearDown(service.dispose);
    await service.play([ChessSound.victory], isCurrent: () => true);
    expect(calls.length, 1);
    await prefs.setBool(SoundService.enabledKey, false);
    SoundService.stopAll();
    await tester.pump(const Duration(seconds: 2));
    await service.play(ChessSound.values, isCurrent: () => true);
    expect(calls.length, 1);
    await prefs.reload();
    final reopened = SoundService(prefs: prefs);
    addTearDown(reopened.dispose);
    await reopened.play([ChessSound.move], isCurrent: () => true);
    expect(calls.length, 1);
    await prefs.setBool(SoundService.enabledKey, true);
    await reopened.play([ChessSound.move], isCurrent: () => true);
    expect(calls.length, 2);
  });

  testWidgets('background, hidden route and disposal cancel remaining pulses', (
    tester,
  ) async {
    final service = SoundService(prefs: prefs);
    var visible = true;
    await service.play([ChessSound.check], isCurrent: () => visible);
    visible = false;
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, 1);
    visible = true;
    await service.play([ChessSound.check], isCurrent: () => visible);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, 2);
    await service.play([ChessSound.move], isCurrent: () => visible);
    expect(calls.length, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await service.play([ChessSound.check], isCurrent: () => visible);
    service.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, 3);
  });

  testWidgets('unsupported system sound is logged once and stops retrying', (
    tester,
  ) async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          attempts++;
          throw PlatformException(code: 'unsupported');
        });
    final service = SoundService(prefs: prefs);
    addTearDown(service.dispose);
    await service.play([ChessSound.victory], isCurrent: () => true);
    await tester.pump(const Duration(seconds: 1));
    await service.play([ChessSound.move], isCurrent: () => true);
    expect(attempts, 1);
    expect(tester.takeException(), isNull);
  });
}
