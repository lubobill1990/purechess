import 'board.dart';
import 'fen.dart';
import 'game_tree.dart';
import 'move.dart';

/// PGN import/export for one game or a collection. Import accepts brace and
/// semicolon comments, RAVs, numeric/symbolic NAGs and compact move numbers.
/// Malformed structure or illegal SAN throws FormatException, never a partial
/// success. Export normalizes whitespace, numbering and annotation glyphs.
class Pgn {
  static GameRecord parse(String text) {
    final games = parseGames(text);
    if (games.length != 1) {
      throw FormatException('Expected one PGN game, found ${games.length}');
    }
    return games.single;
  }

  static List<GameRecord> parseGames(String text) => _Parser(text).parse();

  static String generate(GameRecord record) {
    if (!GameRecord.results.contains(record.result)) {
      throw ArgumentError('Invalid PGN result: ${record.result}');
    }
    final tags = Map<String, String>.of(record.tags);
    tags['Result'] = record.result;
    if (tags.containsKey('SetUp') &&
        tags['SetUp'] != '0' &&
        tags['SetUp'] != '1') {
      throw ArgumentError('Invalid PGN SetUp tag');
    }
    if (record.initialFen != Fen.initial ||
        tags.containsKey('FEN') ||
        tags['SetUp'] == '1') {
      tags['SetUp'] = '1';
      tags['FEN'] = record.initialFen;
    }
    final output = StringBuffer();
    for (final entry in tags.entries) {
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(entry.key)) {
        throw ArgumentError('Invalid PGN tag name: ${entry.key}');
      }
      if (entry.value.contains(RegExp(r'[\r\n]'))) {
        throw ArgumentError('PGN tag values cannot contain newlines');
      }
      final value = entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      output.writeln('[${entry.key} "$value"]');
    }
    output.writeln();
    final tokens = <String>[];
    tokens.addAll(record.root.comments.map(_comment));
    if (!record.root.isLeaf) {
      _writeLine(
        record.root.children.first,
        Board.fromFen(record.initialFen),
        tokens,
        includeSiblings: true,
      );
    }
    tokens.add(record.result);
    output.write(tokens.join(' '));
    return output.toString();
  }

  static String _comment(String text) {
    if (!text.contains('}')) return '{$text}';
    if (text.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('A multiline PGN comment cannot contain "}"');
    }
    return ';$text\n';
  }

  static void _writeLine(
    GameNode first,
    Board board,
    List<String> output, {
    required bool includeSiblings,
  }) {
    var node = first;
    var siblings = includeSiblings;
    while (true) {
      output.add(
        '${board.fullmoveNumber}${board.turn == Color.white ? '.' : '...'}',
      );
      output.addAll(node.startingComments.map(_comment));
      output.add(board.san(node.move!));
      for (final nag in node.nags) {
        if (nag < 0 || nag > 255) {
          throw ArgumentError.value(nag, 'nag', 'PGN NAG must be 0..255');
        }
        output.add('\$$nag');
      }
      output.addAll(node.comments.map(_comment));
      if (siblings) {
        for (final alternative in node.parent!.children.skip(1)) {
          final variation = <String>[];
          _writeLine(
            alternative,
            board.copy(),
            variation,
            includeSiblings: false,
          );
          output.add('(${variation.join(' ')})');
        }
      }
      board.play(node.move!);
      if (node.isLeaf) break;
      node = node.children.first;
      siblings = true;
    }
  }
}

enum _Kind { tag, comment, word, open, close }

class _Token {
  final _Kind kind;
  final String text;
  final String? value;
  final int offset;
  const _Token(this.kind, this.text, this.offset, [this.value]);
}

class _Parser {
  final String source;
  late final List<_Token> tokens = _tokenize();
  var index = 0;

  _Parser(this.source);

  Never _error(String message, [int? offset]) => throw FormatException(
    message,
    source,
    offset ?? (index < tokens.length ? tokens[index].offset : source.length),
  );

  List<_Token> _tokenize() {
    final result = <_Token>[];
    var i = source.startsWith('\uFEFF') ? 1 : 0;
    while (i < source.length) {
      final char = source[i];
      if (RegExp(r'\s').hasMatch(char)) {
        i++;
        continue;
      }
      final start = i;
      if (char == '%' && (i == 0 || source[i - 1] == '\n')) {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
      } else if (char == '{') {
        final end = source.indexOf('}', i + 1);
        if (end < 0) _error('Unterminated PGN comment', start);
        result.add(_Token(_Kind.comment, source.substring(i + 1, end), start));
        i = end + 1;
      } else if (char == ';') {
        i++;
        while (i < source.length && source[i] != '\n' && source[i] != '\r') {
          i++;
        }
        result.add(
          _Token(_Kind.comment, source.substring(start + 1, i), start),
        );
      } else if (char == '(' || char == ')') {
        result.add(_Token(char == '(' ? _Kind.open : _Kind.close, char, i++));
      } else if (char == '*') {
        result.add(_Token(_Kind.word, char, i++));
      } else if (char == r'$') {
        i++;
        while (i < source.length && RegExp(r'\d').hasMatch(source[i])) {
          i++;
        }
        if (i == start + 1) _error('Empty numeric PGN NAG', start);
        result.add(_Token(_Kind.word, source.substring(start, i), start));
      } else if (char == '[') {
        final match = RegExp(
          r'\[\s*([A-Za-z0-9_]+)\s+"((?:\\["\\]|[^"\\\r\n])*)"\s*\]',
        ).matchAsPrefix(source, i);
        if (match == null) _error('Malformed PGN tag pair', start);
        final value = match
            .group(2)!
            .replaceAllMapped(RegExp(r'\\(["\\])'), (match) => match.group(1)!);
        result.add(_Token(_Kind.tag, match.group(1)!, start, value));
        i = match.end;
      } else {
        while (i < source.length &&
            !RegExp(r'[\s{}();\[\]$*]').hasMatch(source[i])) {
          i++;
        }
        if (i == start) _error('Unexpected PGN character "$char"', start);
        var word = source.substring(start, i);
        // Move numbers can be joined to SAN (1.e4, 1...e5).
        final number = RegExp(r'^\d+\.(?:\.\.)?').firstMatch(word);
        if (number != null) {
          result.add(_Token(_Kind.word, number.group(0)!, start));
          word = word.substring(number.end);
        }
        if (word.isNotEmpty) result.add(_Token(_Kind.word, word, start));
      }
    }
    return result;
  }

  List<GameRecord> parse() {
    final games = <GameRecord>[];
    while (index < tokens.length) {
      final tags = <String, String>{};
      while (index < tokens.length && tokens[index].kind == _Kind.tag) {
        final token = tokens[index++];
        if (tags.containsKey(token.text)) {
          _error('Duplicate PGN tag', token.offset);
        }
        tags[token.text] = token.value!;
      }
      if (tags.containsKey('SetUp') &&
          tags['SetUp'] != '0' &&
          tags['SetUp'] != '1') {
        _error('Invalid PGN SetUp tag');
      }
      if (tags['SetUp'] == '1' && !tags.containsKey('FEN')) {
        _error('PGN SetUp requires a FEN tag');
      }
      if (tags['SetUp'] == '0' && tags.containsKey('FEN')) {
        _error('PGN FEN conflicts with SetUp=0');
      }
      final record = GameRecord(
        initialFen: tags['FEN'] ?? Fen.initial,
        tags: tags,
      );
      _line(record, record.root, variation: false);
      games.add(record);
    }
    return games;
  }

  void _line(GameRecord record, GameNode base, {required bool variation}) {
    final board = record.boardAt(base);
    var current = base;
    var moved = false;
    var awaitingMove = false;
    final leading = <String>[];
    while (index < tokens.length) {
      final token = tokens[index];
      if (token.kind == _Kind.close) {
        if (!variation || !moved || awaitingMove) {
          _error('Unexpected or empty PGN variation');
        }
        index++;
        return;
      }
      if (token.kind == _Kind.tag) {
        _error('Missing result before next PGN game');
      }
      index++;
      if (token.kind == _Kind.comment) {
        if (awaitingMove || (!moved && variation)) {
          leading.add(token.text);
        } else {
          current.comments.add(token.text);
        }
      } else if (token.kind == _Kind.open) {
        if (!moved || awaitingMove) {
          _error('Variation must follow a move', token.offset);
        }
        _line(record, current.parent!, variation: true);
      } else {
        final word = token.text;
        if (GameRecord.results.contains(word)) {
          if (variation) _error('Result inside a variation', token.offset);
          if (awaitingMove) _error('Move number requires a move', token.offset);
          if (record.tags.containsKey('Result') && record.result != word) {
            _error('PGN header and movetext results disagree', token.offset);
          }
          record.result = word;
          while (index < tokens.length && tokens[index].kind == _Kind.comment) {
            current.comments.add(tokens[index++].text);
          }
          return;
        }
        if (RegExp(r'^\d+\.(?:\.\.)?$').hasMatch(word)) {
          final expected =
              '${board.fullmoveNumber}${board.turn == Color.white ? '.' : '...'}';
          if (word != expected || awaitingMove) {
            _error('Wrong PGN move number: $word', token.offset);
          }
          awaitingMove = true;
          continue;
        }
        final numericNag = RegExp(r'^\$(\d+)$').firstMatch(word);
        const glyphs = {'!': 1, '?': 2, '!!': 3, '??': 4, '!?': 5, '?!': 6};
        if (numericNag != null || glyphs.containsKey(word)) {
          if (!moved || awaitingMove) {
            _error('Annotation must follow a move', token.offset);
          }
          final nag = numericNag != null
              ? int.tryParse(numericNag.group(1)!)
              : glyphs[word];
          if (nag == null || nag > 255) _error('Invalid PGN NAG', token.offset);
          current.nags.add(nag);
          continue;
        }
        final glyph = RegExp(r'[!?]+$').firstMatch(word)?.group(0);
        if (glyph != null && !glyphs.containsKey(glyph)) {
          _error('Invalid PGN annotation glyph', token.offset);
        }
        Move move;
        try {
          move = board.parseSan(word);
        } on FormatException {
          _error('Illegal PGN SAN: $word', token.offset);
        }
        current = record.addMove(current, move, reuse: false);
        current.startingComments.addAll(leading);
        leading.clear();
        if (glyph != null) current.nags.add(glyphs[glyph]!);
        board.play(move);
        moved = true;
        awaitingMove = false;
      }
    }
    if (variation) _error('Unclosed PGN variation');
    if (awaitingMove) _error('Move number requires a move');
    // In-progress fragments without a termination marker are accepted; the
    // header result (or "*") is retained and export supplies the marker.
  }
}
