import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/features/puzzle/puzzle_catalog.dart';

import 'fixtures.dart';

class PuzzleBundle extends CachingAssetBundle {
  PuzzleBundle() {
    rows = [
      for (var i = 0; i < 10; i++)
        {
          'id': 'p$i',
          'fen': practice().fen,
          'line': ['e2e4', 'e7e5', 'g1f3'],
          'themes': ['fork'],
          'rating': 1000,
        },
    ];
  }

  final Map<String, dynamic> manifest = {
    'schema': 1,
    'fenConvention': 'after-setup',
    'total': 10,
    'packs': [
      {
        'file': 'fork_under1200.json',
        'theme': 'fork',
        'band': 'under1200',
        'count': 10,
      },
    ],
  };
  late List<Map<String, dynamic>> rows;

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      jsonEncode(key.endsWith('manifest.json') ? manifest : rows);

  @override
  Future<ByteData> load(String key) => throw UnsupportedError('Use loadString');
}

void main() {
  test(
    'catalog preserves immutable solver FEN, UCI line, rating and themes',
    () async {
      final catalog = await PuzzleCatalog.load(bundle: PuzzleBundle());
      expect(catalog.byId.length, 10);
      expect(catalog.packs.single.title, '双重攻击');
      expect(catalog.byId['p0']!.fen, practice().fen);
      expect(catalog.byId['p0']!.line.map((move) => move.uci), [
        'e2e4',
        'e7e5',
        'g1f3',
      ]);
      expect(catalog.byId['p0']!.rating, 1000);
      expect(catalog.byId['p0']!.themes, ['fork']);
      expect(() => catalog.byId.clear(), throwsUnsupportedError);
      expect(() => catalog.packs.clear(), throwsUnsupportedError);
      expect(
        () => catalog.packs.single.puzzles.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test('unknown FEN convention and schema are rejected', () async {
    for (final change in [
      {'schema': 2},
      {'fenConvention': 'before-setup'},
    ]) {
      final bundle = PuzzleBundle()..manifest.addAll(change);
      await expectLater(
        PuzzleCatalog.load(bundle: bundle),
        throwsFormatException,
      );
    }
  });
  test(
    'duplicate IDs, wrong theme and out-of-band rating are rejected',
    () async {
      for (final change in [
        {'id': 'p1'},
        {
          'themes': ['pin'],
        },
        {'rating': 1200},
        {
          'line': ['e2e4', 'e7e5'],
        },
        {'id': ''},
      ]) {
        final bundle = PuzzleBundle();
        bundle.rows.first.addAll(change);
        await expectLater(
          PuzzleCatalog.load(bundle: bundle),
          throwsFormatException,
        );
      }
    },
  );
  test('manifest file names, counts and total must match', () async {
    for (final change in [
      {'file': '../other.json'},
      {'count': 11},
      {'theme': 'unknown'},
      {'band': '2000+'},
    ]) {
      final bundle = PuzzleBundle();
      (bundle.manifest['packs'] as List<Map<String, Object>>).first.addAll(
        change,
      );
      await expectLater(
        PuzzleCatalog.load(bundle: bundle),
        throwsFormatException,
      );
    }
    final bundle = PuzzleBundle()..manifest['total'] = 11;
    await expectLater(
      PuzzleCatalog.load(bundle: bundle),
      throwsFormatException,
    );
  });
  test('rating boundaries are exclusive at 1200, 1600 and 2000', () {
    expect(ratingInBand(1199, 'under1200'), isTrue);
    expect(ratingInBand(1200, 'under1200'), isFalse);
    expect(ratingInBand(1200, '1200-1600'), isTrue);
    expect(ratingInBand(1599, '1200-1600'), isTrue);
    expect(ratingInBand(1600, '1200-1600'), isFalse);
    expect(ratingInBand(1600, '1600-2000'), isTrue);
    expect(ratingInBand(1999, '1600-2000'), isTrue);
    expect(ratingInBand(2000, '1600-2000'), isFalse);
    expect(ratingInBand(-1, 'under1200'), isFalse);
    expect(ratingInBand(1000, 'unknown'), isFalse);
  });
}
