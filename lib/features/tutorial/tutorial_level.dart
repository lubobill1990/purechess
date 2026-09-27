import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/board.dart';
import '../../core/move.dart';
import '../../core/puzzle.dart';

enum TutorialGoal {
  movement,
  capture,
  check,
  evadeCapture,
  evadeBlock,
  evadeEscape,
  checkmate,
  mateIn1,
  castling,
  promotion,
  enPassant,
  stalemateTrap,
  graduation,
}

class TutorialLevel {
  TutorialLevel.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      goal = TutorialGoal.values.byName(json['goal'] as String),
      fen = json['fen'] as String,
      intro = json['intro'] as String,
      success = json['success'] as String,
      failure = json['failure'] as String,
      guided = json['guided'] as bool? ?? false,
      line = List.unmodifiable(
        (json['line'] as List).cast<String>().map(Move.fromUci),
      ) {
    Board.fromFen(fen);
    if ([
      id,
      title,
      intro,
      success,
      failure,
    ].any((text) => text.trim().isEmpty)) {
      throw const FormatException('Tutorial text must not be empty');
    }
    if (graduation) {
      if (line.isNotEmpty) {
        throw const FormatException('Graduation must be a free game');
      }
    } else {
      problem; // Validate every main-line move with the core.
    }
  }

  final String id;
  final String title;
  final TutorialGoal goal;
  final String fen;
  final String intro;
  final String success;
  final String failure;
  final bool guided;
  final List<Move> line;

  bool get graduation => goal == TutorialGoal.graduation;
  PuzzleProblem get problem => PuzzleProblem(
    id: id,
    title: title,
    fen: fen,
    line: line,
    themes: [goal.name],
  );
}

class TutorialCatalog {
  TutorialCatalog(List<TutorialLevel> levels)
    : levels = List.unmodifiable(levels) {
    if (levels.isEmpty ||
        levels.map((level) => level.id).toSet().length != levels.length ||
        !levels.last.graduation ||
        levels.take(levels.length - 1).any((level) => level.graduation)) {
      throw const FormatException('Invalid tutorial sequence');
    }
  }

  final List<TutorialLevel> levels;

  static Future<TutorialCatalog> load({AssetBundle? bundle}) async {
    final json = jsonDecode(
      await (bundle ?? rootBundle).loadString('assets/tutorial/levels.json'),
    ) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unsupported tutorial version');
    }
    return TutorialCatalog([
      for (final level in json['levels'] as List)
        TutorialLevel.fromJson(level as Map<String, dynamic>),
    ]);
  }
}
