import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/game_tree.dart';
import '../../core/pgn.dart';

class ClassicGame {
  ClassicGame(this.record) : line = record.mainLine;

  final GameRecord record;
  final List<GameNode> line;
  String get id => record.tags['Id']!;
  String get title => record.tags['Title']!;
  String get topic => record.tags['Theme']!;
  String get year => record.tags['Date']!.substring(0, 4);
  String get players => '${record.tags['White']} — ${record.tags['Black']}';
  int get plies => line.length - 1;
}

class ClassicLibrary {
  static const asset = 'assets/library/classics.pgn';

  static Future<List<ClassicGame>> load() async =>
      compute(parse, await rootBundle.loadString(asset));

  static List<ClassicGame> parse(String source) {
    final records = Pgn.parseGames(source);
    if (records.isEmpty) throw const FormatException('Empty classic library');
    final ids = <String>{};
    return records
        .map((record) {
          for (final key in [
            'Id',
            'Title',
            'Theme',
            'Date',
            'White',
            'Black',
            'Source',
          ]) {
            if (record.tags[key]?.trim().isNotEmpty != true) {
              throw FormatException('Missing classic metadata: $key');
            }
          }
          final year = int.tryParse(record.tags['Date']!.split('.').first);
          if (year == null || year >= 1900 || !ids.add(record.tags['Id']!)) {
            throw const FormatException('Invalid classic date or duplicate ID');
          }
          final game = ClassicGame(record);
          if (game.plies == 0) {
            throw const FormatException('Empty classic score');
          }
          return game;
        })
        .toList(growable: false);
  }
}

class ReadingProgress {
  const ReadingProgress({this.id, this.ply = 0, this.error});

  static const key = 'library_reading';
  final String? id;
  final int ply;
  final String? error;

  static ReadingProgress read(SharedPreferences prefs) {
    final raw = prefs.get(key);
    if (raw == null) return const ReadingProgress();
    if (raw is String) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic> &&
            json['id'] is String &&
            (json['id'] as String).isNotEmpty &&
            json['ply'] is int &&
            (json['ply'] as int) >= 0) {
          return ReadingProgress(
            id: json['id'] as String,
            ply: json['ply'] as int,
          );
        }
      } on FormatException {
        // The caller displays this error and offers the catalogue instead.
      }
    }
    return const ReadingProgress(error: '阅读进度无法识别，请从名局库重新选择。');
  }

  static Future<void> save(
    SharedPreferences prefs,
    ClassicGame game,
    int ply,
  ) async {
    if (ply < 0 || ply > game.plies) throw RangeError.range(ply, 0, game.plies);
    if (!await prefs.setString(key, jsonEncode({'id': game.id, 'ply': ply}))) {
      throw StateError('Reading progress was not saved');
    }
  }
}
