import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'puzzle_catalog.dart';

class PuzzleRepository extends ChangeNotifier {
  PuzzleRepository({required this.prefs, required this.catalog}) {
    _readProgress();
  }

  static const progressKey = 'puzzle_progress_v1';
  static Future<void>? _pending;
  final SharedPreferences prefs;
  final PuzzleCatalog catalog;
  Set<String> _solved = {};
  Set<String> _mistakes = {};
  Map<String, Set<String>> _dailySolved = {};

  Set<String> get solved => Set.unmodifiable(_solved);
  Set<String> get mistakes => Set.unmodifiable(_mistakes);
  Set<String> completed(String? day) =>
      day == null ? solved : Set.unmodifiable(_dailySolved[day] ?? {});

  static String dailyKey(DateTime date) =>
      'daily_${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  void _readProgress() {
    final raw = prefs.getString(progressKey);
    if (raw == null) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    _solved = (data['solved'] as List<dynamic>).cast<String>().toSet();
    _mistakes = (data['mistakes'] as List<dynamic>).cast<String>().toSet();
    _dailySolved = (data['dailySolved'] as Map<String, dynamic>).map(
      (key, value) =>
          MapEntry(key, (value as List<dynamic>).cast<String>().toSet()),
    );
  }

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      if (identical(_pending, done.future)) _pending = null;
      done.complete();
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      if (!await prefs.setString(key, value)) {
        throw StateError('Puzzle preferences write rejected');
      }
    } catch (_) {
      // Legacy preferences updates its cache before the platform write.
      // Reload so a rejected write cannot masquerade as durable progress.
      await prefs.reload();
      rethrow;
    }
  }

  Future<List<String>> daily(DateTime date) => _serial(() async {
    final key = dailyKey(date);
    final raw = prefs.getString(key);
    if (raw != null) {
      final ids = (jsonDecode(raw) as List<dynamic>).cast<String>();
      if (ids.length != 10 ||
          ids.toSet().length != 10 ||
          ids.any((id) => !catalog.byId.containsKey(id))) {
        throw const FormatException('Saved daily puzzle set is invalid');
      }
      return List.unmodifiable(ids);
    }
    final ids = catalog.byId.keys.toList()..sort();
    if (ids.length < 10) throw StateError('Daily puzzles require 10 problems');
    ids.shuffle(Random(int.parse(key.substring(6))));
    final selected = ids.take(10).toList();
    await _write(key, jsonEncode(selected));
    return List.unmodifiable(selected);
  });

  Future<void> record(String id, {required bool correct, String? day}) =>
      _serial(() async {
        if (!catalog.byId.containsKey(id)) {
          throw ArgumentError.value(id, 'id', 'Unknown puzzle');
        }
        if (day != null) {
          final raw = prefs.getString(day);
          if (!RegExp(r'^daily_\d{8}$').hasMatch(day) ||
              raw == null ||
              !(jsonDecode(raw) as List<dynamic>).contains(id)) {
            throw ArgumentError('Puzzle does not belong to this daily set');
          }
        }
        _readProgress();
        final solved = {..._solved};
        final mistakes = {..._mistakes};
        final dailySolved = {
          for (final entry in _dailySolved.entries) entry.key: {...entry.value},
        };
        if (correct) {
          solved.add(id);
          mistakes.remove(id);
          if (day != null) (dailySolved[day] ??= {}).add(id);
        } else {
          mistakes.add(id);
        }
        await _write(
          progressKey,
          jsonEncode({
            'solved': solved.toList()..sort(),
            'mistakes': mistakes.toList()..sort(),
            'dailySolved': {
              for (final entry in dailySolved.entries)
                entry.key: entry.value.toList()..sort(),
            },
          }),
        );
        _solved = solved;
        _mistakes = mistakes;
        _dailySolved = dailySolved;
        notifyListeners();
      });
}
