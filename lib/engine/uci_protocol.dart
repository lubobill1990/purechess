import '../core/fen.dart';
import '../core/move.dart';

enum UciScoreKind { cp, mate }

enum UciScoreBound { exact, lower, upper }

/// Scores are relative to the side to move, not always White.
class UciScore {
  const UciScore(this.kind, this.value, {this.bound = UciScoreBound.exact});

  final UciScoreKind kind;
  final int value;
  final UciScoreBound bound;
  int? get cp => kind == UciScoreKind.cp ? value : null;
  int? get mate => kind == UciScoreKind.mate ? value : null;
}

sealed class UciMessage {
  const UciMessage();
}

class UciOk extends UciMessage {
  const UciOk();
}

class UciReady extends UciMessage {
  const UciReady();
}

class UciId extends UciMessage {
  const UciId(this.field, this.value);
  final String field;
  final String value;
}

class UciOption extends UciMessage {
  const UciOption(this.name, this.type, {this.min, this.max});
  final String name;
  final String type;
  final int? min;
  final int? max;
}

class UciInfo extends UciMessage {
  UciInfo({
    this.depth,
    this.selectiveDepth,
    this.multiPv = 1,
    this.score,
    List<String> pv = const [],
    this.text,
  }) : pv = List.unmodifiable(pv);

  final int? depth;
  final int? selectiveDepth;
  final int multiPv;
  final UciScore? score;
  final List<String> pv;
  final String? text;
}

class UciBestMove extends UciMessage {
  const UciBestMove(this.move, {this.ponder});
  final String? move;
  final String? ponder;
}

class UciUnknown extends UciMessage {
  const UciUnknown(this.line);
  final String line;
}

String _move(String token) => Move.fromUci(token).uci;

/// Ignores extension/banner lines; malformed recognized fields fail explicitly.
UciMessage parseUciLine(String line) {
  final tokens = line.trim().split(RegExp(r'\s+'));
  int number(int index) {
    if (index >= tokens.length) {
      throw const FormatException('Missing UCI number');
    }
    final value = int.tryParse(tokens[index]);
    if (value == null) throw const FormatException('Invalid UCI number');
    return value;
  }

  switch (tokens.first) {
    case 'uciok':
      return const UciOk();
    case 'readyok':
      return const UciReady();
    case 'id':
      if (tokens.length < 3) throw const FormatException('Invalid UCI id');
      return UciId(tokens[1], tokens.skip(2).join(' '));
    case 'option':
      final type = tokens.indexOf('type');
      if (tokens.length < 5 ||
          tokens[1] != 'name' ||
          type < 3 ||
          type + 1 >= tokens.length) {
        throw const FormatException('Invalid UCI option');
      }
      final min = tokens.indexOf('min', type + 1);
      final max = tokens.indexOf('max', type + 1);
      return UciOption(
        tokens.sublist(2, type).join(' '),
        tokens[type + 1],
        min: min < 0 ? null : number(min + 1),
        max: max < 0 ? null : number(max + 1),
      );
    case 'bestmove':
      if (tokens.length != 2 &&
          !(tokens.length == 4 && tokens[2] == 'ponder')) {
        throw const FormatException('Invalid UCI bestmove');
      }
      final move = switch (tokens[1]) {
        '(none)' || '0000' => null,
        final value => _move(value),
      };
      return UciBestMove(
        move,
        ponder: tokens.length == 4 ? _move(tokens[3]) : null,
      );
    case 'info':
      int? depth;
      int? selectiveDepth;
      var multiPv = 1;
      UciScore? score;
      var pv = <String>[];
      String? text;
      for (var i = 1; i < tokens.length; i++) {
        switch (tokens[i]) {
          case 'depth':
            depth = number(++i);
            if (depth < 0) throw const FormatException('Negative UCI depth');
          case 'seldepth':
            selectiveDepth = number(++i);
            if (selectiveDepth < 0) {
              throw const FormatException('Negative UCI seldepth');
            }
          case 'multipv':
            multiPv = number(++i);
            if (multiPv < 1) throw const FormatException('Invalid UCI multipv');
          case 'score':
            if (++i >= tokens.length) {
              throw const FormatException('Missing UCI score kind');
            }
            final kind = switch (tokens[i]) {
              'cp' => UciScoreKind.cp,
              'mate' => UciScoreKind.mate,
              _ => throw const FormatException('Invalid UCI score kind'),
            };
            final value = number(++i);
            var bound = UciScoreBound.exact;
            if (i + 1 < tokens.length) {
              if (tokens[i + 1] == 'lowerbound') {
                bound = UciScoreBound.lower;
                i++;
              } else if (tokens[i + 1] == 'upperbound') {
                bound = UciScoreBound.upper;
                i++;
              }
            }
            score = UciScore(kind, value, bound: bound);
          case 'pv':
            i++;
            const fields = {
              'depth',
              'seldepth',
              'multipv',
              'score',
              'nodes',
              'nps',
              'time',
              'hashfull',
              'tbhits',
              'cpuload',
              'currmove',
              'currmovenumber',
              'string',
              'wdl',
              'refutation',
              'currline',
            };
            while (i < tokens.length && !fields.contains(tokens[i])) {
              pv.add(_move(tokens[i++]));
            }
            i--;
          case 'string':
            text = tokens.skip(i + 1).join(' ');
            i = tokens.length;
        }
      }
      return UciInfo(
        depth: depth,
        selectiveDepth: selectiveDepth,
        multiPv: multiPv,
        score: score,
        pv: pv,
        text: text,
      );
    default:
      return UciUnknown(line);
  }
}

abstract final class UciCommand {
  static const uci = 'uci';
  static const isReady = 'isready';
  static const newGame = 'ucinewgame';
  static const stop = 'stop';
  static const quit = 'quit';

  static String setOption(String name, Object value) {
    final text = value.toString();
    if (name.trim().isEmpty ||
        text.isEmpty ||
        name.contains(RegExp(r'[\r\n]')) ||
        text.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Invalid UCI option command');
    }
    return 'setoption name $name value $text';
  }

  static String position(String fen) =>
      'position fen ${Fen.generate(Fen.parse(fen))}';

  static String go({int? movetime, int? depth}) {
    if ((movetime == null) == (depth == null) ||
        (movetime != null && movetime < 1) ||
        (depth != null && depth < 1)) {
      throw ArgumentError('Specify one positive movetime or depth');
    }
    return movetime != null ? 'go movetime $movetime' : 'go depth $depth';
  }
}
