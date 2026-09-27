import 'board.dart';
import 'fen.dart';
import 'move.dart';

class GameNode {
  final Move? move;
  GameNode? _parent;
  final List<GameNode> _children = [];
  final List<String> startingComments = [];
  final List<String> comments = [];
  final List<int> nags = [];

  GameNode._(this.move, this._parent);

  GameNode? get parent => _parent;
  List<GameNode> get children => List.unmodifiable(_children);
  bool get isLeaf => _children.isEmpty;
  int get ply => pathFromRoot.length - 1;

  List<GameNode> get pathFromRoot {
    final path = <GameNode>[];
    for (GameNode? node = this; node != null; node = node.parent) {
      path.add(node);
    }
    return path.reversed.toList(growable: false);
  }

  GameNode? childWithMove(Move move) {
    for (final child in _children) {
      if (child.move == move) return child;
    }
    return null;
  }

  Iterable<GameNode> get descendantsAndSelf sync* {
    yield this;
    for (final child in _children) {
      yield* child.descendantsAndSelf;
    }
  }
}

/// The first child is the main line; siblings are recursive PGN variations.
/// Moves/ancestry can only be edited through the record, keeping nodes legal.
class GameRecord {
  static const results = ['*', '1-0', '0-1', '1/2-1/2'];

  final GameNode root = GameNode._(null, null);
  final String initialFen;
  final Map<String, String> tags;

  GameRecord({String initialFen = Fen.initial, Map<String, String>? tags})
    : initialFen = Board.fromFen(initialFen).toFen(),
      tags = Map.of(tags ?? {}) {
    if (!results.contains(result)) {
      throw FormatException('Invalid game result: $result');
    }
  }

  String get result => tags['Result'] ?? '*';
  set result(String value) {
    if (!results.contains(value)) {
      throw ArgumentError.value(value, 'result', 'Invalid game result');
    }
    tags['Result'] = value;
  }

  void _requireMember(GameNode node) {
    if (!identical(node.pathFromRoot.first, root)) {
      throw ArgumentError('Node does not belong to this record');
    }
  }

  Board boardAt(GameNode node) {
    _requireMember(node);
    final board = Board.fromFen(initialFen);
    for (final step in node.pathFromRoot.skip(1)) {
      board.play(step.move!);
    }
    return board;
  }

  GameNode addMove(GameNode parent, Move move, {bool reuse = true}) {
    final board = boardAt(parent);
    if (!board.isLegal(move)) {
      throw IllegalMoveException('Illegal tree move $move in ${board.toFen()}');
    }
    if (reuse) {
      final existing = parent.childWithMove(move);
      if (existing != null) return existing;
    }
    final child = GameNode._(move, parent);
    parent._children.add(child);
    return child;
  }

  GameNode addSan(GameNode parent, String san, {bool reuse = true}) =>
      addMove(parent, boardAt(parent).parseSan(san), reuse: reuse);

  void promoteVariation(GameNode node) {
    _requireMember(node);
    final parent = node.parent;
    if (parent == null) throw ArgumentError('Root is not a variation');
    parent._children
      ..remove(node)
      ..insert(0, node);
  }

  void removeVariation(GameNode node) {
    _requireMember(node);
    final parent = node.parent;
    if (parent == null) throw ArgumentError('Cannot remove the root');
    parent._children.remove(node);
    node._parent = null;
  }

  List<GameNode> get mainLine {
    final line = <GameNode>[root];
    var current = root;
    while (!current.isLeaf) {
      current = current._children.first;
      line.add(current);
    }
    return line;
  }
}

/// UI-independent replay/editor cursor. Returning a fresh board prevents callers
/// from accidentally mutating another branch or the cursor's position.
class GameCursor {
  final GameRecord record;
  GameNode _current;

  GameCursor(this.record) : _current = record.root;

  GameNode get current => _current;
  Board get board => record.boardAt(_current);

  void goTo(GameNode node) {
    record._requireMember(node);
    _current = node;
  }

  GameNode play(Move move) => _current = record.addMove(_current, move);
  GameNode playSan(String san) => play(board.parseSan(san));

  bool back() {
    if (_current.parent == null) return false;
    _current = _current.parent!;
    return true;
  }

  bool forward({int variation = 0}) {
    if (_current.isLeaf) return false;
    if (variation < 0 || variation >= _current._children.length) {
      throw RangeError.index(variation, _current._children, 'variation');
    }
    _current = _current._children[variation];
    return true;
  }
}
