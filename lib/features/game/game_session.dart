import '../../core/board.dart';
import '../../core/fen.dart';
import '../../core/game_tree.dart';
import '../../core/move.dart';
import '../../core/pgn.dart';

enum GameEndReason {
  checkmate,
  stalemate,
  threefoldRepetition,
  fiftyMoveDraw,
  insufficientMaterial,
  resignation,
  agreement,
}

class GameOutcome {
  const GameOutcome(this.reason, {this.winner});

  final GameEndReason reason;
  final Color? winner;

  String get result => winner == null
      ? '1/2-1/2'
      : winner == Color.white
      ? '1-0'
      : '0-1';

  String get message {
    final player = winner == Color.white ? '白方' : '黑方';
    return switch (reason) {
      GameEndReason.checkmate => '$player胜 · 将杀',
      GameEndReason.stalemate => '和棋 · 逼和',
      GameEndReason.threefoldRepetition => '和棋 · 三次重复',
      GameEndReason.fiftyMoveDraw => '和棋 · 50 步规则',
      GameEndReason.insufficientMaterial => '和棋 · 不足子力',
      GameEndReason.resignation => '$player胜 · 对方认输',
      GameEndReason.agreement => '和棋 · 双方协议',
    };
  }
}

/// Local play auto-adjudicates claimable draws; the core remains reusable for
/// analysis. Undo removes the abandoned continuation rather than saving a RAV.
class GameSession {
  GameSession({
    String initialFen = Fen.initial,
    DateTime? startedAt,
    Color? humanColor,
  }) : startedAt = startedAt ?? DateTime.now(),
       _board = Board.fromFen(initialFen),
       _record = GameRecord(initialFen: initialFen) {
    _node = _record.root;
    final date = this.startedAt;
    _record.tags.addAll({
      'Event': humanColor == null ? '面对面对弈' : '人机对弈',
      'Site': 'Local',
      'Date': '${date.year}.${_two(date.month)}.${_two(date.day)}',
      'Round': '-',
      'White': humanColor == null
          ? '白方'
          : (humanColor == Color.white ? '我' : 'AI'),
      'Black': humanColor == null
          ? '黑方'
          : (humanColor == Color.black ? '我' : 'AI'),
    });
    _adjudicate();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
  final DateTime startedAt;
  final Board _board;
  final GameRecord _record;
  late GameNode _node;
  GameOutcome? _outcome;
  Color? _drawOffer;
  int _revision = 0;

  Board get board => _board.copy();
  Color get turn => _board.turn;
  int get moveCount => _board.plyCount;
  int get revision => _revision;
  GameOutcome? get outcome => _outcome;
  Color? get drawOffer => _drawOffer;
  bool get finished => _outcome != null;
  bool get canPlay => !finished && _drawOffer == null;
  bool get canUndo => moveCount > 0 && _drawOffer == null;
  bool canAct(Color actor) => canPlay && actor == turn;
  GameRecord snapshot() => Pgn.parse(Pgn.generate(_record));

  void play(Move move) {
    if (!canPlay) throw StateError('The game is not accepting moves');
    final next = _record.addMove(_node, move);
    _board.play(move);
    _node = next;
    _revision++;
    _adjudicate();
  }

  void undo() {
    if (!canUndo) throw StateError('No move can be taken back');
    final abandoned = _node;
    _node = _node.parent!;
    _record.removeVariation(abandoned);
    _board.undo();
    _outcome = null;
    _record.tags.remove('Termination');
    _revision++;
    _adjudicate();
  }

  void resign(Color actor, {bool requireTurn = true}) {
    if (requireTurn) _requireTurn(actor);
    if (!canPlay) throw StateError('The game is not accepting actions');
    _finish(GameOutcome(GameEndReason.resignation, winner: actor.opponent));
    _revision++;
  }

  void offerDraw(Color actor) {
    _requireTurn(actor);
    _drawOffer = actor;
  }

  void respondToDraw(Color actor, {required bool accept}) {
    if (finished || _drawOffer == null || actor != _drawOffer!.opponent) {
      throw StateError('Only the opponent may respond to a draw offer');
    }
    _drawOffer = null;
    if (accept) {
      _finish(const GameOutcome(GameEndReason.agreement));
      _revision++;
    }
  }

  void _requireTurn(Color actor) {
    if (!canAct(actor)) throw StateError('Action requires the active player');
  }

  void _adjudicate() {
    final reason = switch (_board.status) {
      GameStatus.playing => null,
      GameStatus.checkmate => GameEndReason.checkmate,
      GameStatus.stalemate => GameEndReason.stalemate,
      GameStatus.insufficientMaterial => GameEndReason.insufficientMaterial,
      GameStatus.fiftyMoveDraw => GameEndReason.fiftyMoveDraw,
      GameStatus.threefoldRepetition => GameEndReason.threefoldRepetition,
    };
    if (reason == null) {
      _record.result = '*';
    } else {
      _finish(
        GameOutcome(
          reason,
          winner: reason == GameEndReason.checkmate ? turn.opponent : null,
        ),
      );
    }
  }

  void _finish(GameOutcome outcome) {
    _outcome = outcome;
    _record.result = outcome.result;
    _record.tags['Termination'] = switch (outcome.reason) {
      GameEndReason.resignation => 'resignation',
      GameEndReason.agreement => 'draw agreement',
      _ => 'normal',
    };
    _node.comments.add(outcome.message);
  }
}
