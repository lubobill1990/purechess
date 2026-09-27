import 'dart:async';

import 'package:purechess/engine/stockfish_transport.dart';

class FakeStockfishTransport implements StockfishTransport {
  final output = StreamController<String>(sync: true);
  final commands = <String>[];
  bool handshake = true;
  bool ready = true;
  bool analysis = true;
  bool omitElo = false;
  bool stopped = false;
  bool launched = false;
  Object? launchError;
  Object? stopError;
  String? sendErrorPrefix;
  Completer<void>? launchGate;
  Completer<void>? stopGate;
  List<String> result = [
    'info depth 8 score cp 24 pv e2e4 e7e5',
    'bestmove e2e4 ponder e7e5',
  ];

  @override
  Stream<String> get lines => output.stream;

  @override
  Future<void> launch() async {
    launched = true;
    if (launchError != null) throw launchError!;
    await launchGate?.future;
  }

  @override
  void send(String line) {
    if (stopped) throw StateError('send after stop');
    commands.add(line);
    if (sendErrorPrefix != null && line.startsWith(sendErrorPrefix!)) {
      throw StateError('fake write failure');
    }
    if (line == 'uci' && handshake) {
      for (final response in [
        'id name Stockfish Fake',
        'option name Threads type spin default 1 min 1 max 1024',
        'option name Hash type spin default 16 min 1 max 33554432',
        'option name MultiPV type spin default 1 min 1 max 256',
        'option name Skill Level type spin default 20 min 0 max 20',
        'option name UCI_LimitStrength type check default false',
        if (!omitElo)
          'option name UCI_Elo type spin default 1320 min 1320 max 3190',
        'uciok',
      ]) {
        output.add(response);
      }
    } else if (line == 'isready' && ready) {
      output.add('readyok');
    } else if (line.startsWith('go ') && analysis) {
      for (final response in result) {
        output.add(response);
      }
    }
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (launchGate != null && !launchGate!.isCompleted) launchGate!.complete();
    await stopGate?.future;
    await output.close();
    if (stopError != null) throw stopError!;
  }
}
