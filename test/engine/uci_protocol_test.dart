import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/fen.dart';
import 'package:purechess/engine/uci_protocol.dart';

void main() {
  test('handshake tolerates surrounding whitespace and CRLF', () {
    expect(parseUciLine('  uciok\r\n'), isA<UciOk>());
    expect(parseUciLine('\treadyok '), isA<UciReady>());
  });
  test('id names and authors retain spaces', () {
    final id = parseUciLine('id name Stockfish 17') as UciId;
    expect(id.field, 'name');
    expect(id.value, 'Stockfish 17');
    expect(
      (parseUciLine('id author the authors') as UciId).value,
      'the authors',
    );
  });
  test('spin and check options', () {
    final option = parseUciLine(
      'option name Skill Level type spin default 20 min 0 max 20',
    ) as UciOption;
    expect(option.name, 'Skill Level');
    expect(option.type, 'spin');
    expect(option.min, 0);
    expect(option.max, 20);
    expect(
      (parseUciLine(
        'option name UCI_LimitStrength type check default false',
      ) as UciOption).min,
      isNull,
    );
  });
  for (final line in ['', 'Stockfish 17 by the authors', 'extension value']) {
    test('unknown/banner: "$line"', () {
      expect(parseUciLine(line), isA<UciUnknown>());
    });
  }
  for (final value in [-130, 0, 57]) {
    test('cp score $value with full info', () {
      final info = parseUciLine(
        'info depth 12 seldepth 19 multipv 1 score cp $value nodes 123 '
        'nps 8000 hashfull 1 tbhits 0 time 15 pv e2e4 e7e5 g1f3',
      ) as UciInfo;
      expect(info.depth, 12);
      expect(info.selectiveDepth, 19);
      expect(info.multiPv, 1);
      expect(info.score!.cp, value);
      expect(info.score!.mate, isNull);
      expect(info.score!.bound, UciScoreBound.exact);
      expect(info.pv, ['e2e4', 'e7e5', 'g1f3']);
      expect(() => info.pv.add('d2d4'), throwsUnsupportedError);
    });
  }
  for (final value in [-4, 0, 3]) {
    test('mate score $value', () {
      final info = parseUciLine('info depth 5 score mate $value') as UciInfo;
      expect(info.score!.mate, value);
      expect(info.score!.cp, isNull);
    });
  }
  for (final bound in {
    'lowerbound': UciScoreBound.lower,
    'upperbound': UciScoreBound.upper,
  }.entries) {
    test('score ${bound.key}', () {
      final info =
          parseUciLine('info score cp -10 ${bound.key} pv e2e4') as UciInfo;
      expect(info.score!.bound, bound.value);
    });
  }
  test('partial updates do not invent a score or depth', () {
    final info = parseUciLine('info nodes 100 nps 1000') as UciInfo;
    expect(info.score, isNull);
    expect(info.depth, isNull);
    expect(info.pv, isEmpty);
  });
  test(
    'info string consumes remaining tokens without parsing score keywords',
    () {
      final info =
          parseUciLine('info string score cp broken depth nope') as UciInfo;
      expect(info.text, 'score cp broken depth nope');
      expect(info.score, isNull);
    },
  );
  test('PV promotions and reordered fields', () {
    final info = parseUciLine(
      'info pv a7a8n h2h1q depth 4 score cp 20 multipv 2',
    ) as UciInfo;
    expect(info.pv, ['a7a8n', 'h2h1q']);
    expect(info.depth, 4);
    expect(info.multiPv, 2);
  });
  test('bestmove with optional ponder and promotion', () {
    final best = parseUciLine('bestmove a7a8q ponder e8d7') as UciBestMove;
    expect(best.move, 'a7a8q');
    expect(best.ponder, 'e8d7');
    expect((parseUciLine('bestmove e1g1') as UciBestMove).ponder, isNull);
  });
  for (final value in ['0000', '(none)']) {
    test('terminal bestmove $value', () {
      expect((parseUciLine('bestmove $value') as UciBestMove).move, isNull);
    });
  }
  for (final line in [
    'id',
    'id name',
    'option',
    'option name Skill type',
    'option name Hash type spin min nope',
    'bestmove',
    'bestmove a9a8',
    'bestmove e2e4 ponder',
    'bestmove e2e4 wrong e7e5',
    'bestmove e2e4 ponder 0000',
    'info depth',
    'info depth x',
    'info depth -1',
    'info seldepth -2',
    'info multipv 0',
    'info score',
    'info score cp',
    'info score cp nope',
    'info score unknown 10',
    'info pv e2e9',
  ]) {
    test('malformed recognized field: $line', () {
      expect(() => parseUciLine(line), throwsFormatException);
    });
  }
  test('command builders canonicalize and encode', () {
    expect(UciCommand.uci, 'uci');
    expect(UciCommand.isReady, 'isready');
    expect(UciCommand.newGame, 'ucinewgame');
    expect(UciCommand.stop, 'stop');
    expect(UciCommand.quit, 'quit');
    expect(
      UciCommand.position('  ${Fen.initial}  '),
      'position fen ${Fen.initial}',
    );
    expect(
      UciCommand.setOption('UCI_LimitStrength', false),
      'setoption name UCI_LimitStrength value false',
    );
    expect(UciCommand.go(movetime: 100), 'go movetime 100');
    expect(UciCommand.go(depth: 12), 'go depth 12');
  });
  for (final args in [
    (null, null),
    (100, 12),
    (0, null),
    (-1, null),
    (null, 0),
    (null, -1),
  ]) {
    test('invalid search limits $args', () {
      expect(
        () => UciCommand.go(movetime: args.$1, depth: args.$2),
        throwsArgumentError,
      );
    });
  }
  test('invalid position and command injection rejected', () {
    expect(() => UciCommand.position('bad fen'), throwsFormatException);
    expect(
      () => UciCommand.position('${Fen.initial}\nquit'),
      throwsFormatException,
    );
    expect(() => UciCommand.setOption('Hash\nquit', 16), throwsFormatException);
    expect(
      () => UciCommand.setOption('Hash', '16\rquit'),
      throwsFormatException,
    );
    expect(() => UciCommand.setOption('', 1), throwsFormatException);
  });
}
