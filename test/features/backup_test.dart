import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/features/library/records_repository.dart';
import 'package:purechess/features/settings/backup_data.dart';
import 'package:purechess/features/settings/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pgn = '[Id "game-1"]\n[Event "练习"]\n1. e4 {中心} e5 2. Nf3 *';
final _ids = List.generate(10, (i) => 'p$i');
const _day = 'daily_20260928';

Map<String, Object> _progress({
  int tutorial = 5,
  List<String> solved = const ['p0'],
  List<String> mistakes = const ['p2'],
  List<String> daily = const ['p0'],
  int ply = 4,
}) => {
  'tutorial_progress': tutorial,
  'puzzle_progress_v1': jsonEncode({
    'solved': solved,
    'mistakes': mistakes,
    'dailySolved': {_day: daily},
  }),
  _day: jsonEncode(_ids),
  'library_reading': jsonEncode({'id': 'classic', 'ply': ply}),
  'chess.ai.recommendedLevel': 3,
};

Uint8List _zip({
  Map<String, Object?>? manifest,
  Map<String, String> records = const {},
  bool includeManifest = true,
  List<ArchiveFile> extra = const [],
}) {
  final archive = Archive();
  if (includeManifest) {
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode(
          manifest ??
              {
                'format': 'purechess-backup',
                'version': 1,
                'createdAt': '2026-09-28T00:00:00Z',
                'preferences': {},
                'records': [
                  for (final entry in records.entries)
                    {'id': 'game-1', 'file': entry.key},
                ],
              },
        ),
      ),
    );
  }
  for (final entry in records.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  for (final file in extra) {
    archive.addFile(file);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class _FailOncePreferences extends Fake implements SharedPreferences {
  _FailOncePreferences(this.delegate);
  final SharedPreferences delegate;
  bool failed = false;

  @override
  Set<String> getKeys() => delegate.getKeys();
  @override
  Object? get(String key) => delegate.get(key);
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> setInt(String key, int value) => delegate.setInt(key, value);
  @override
  Future<bool> setString(String key, String value) async {
    await delegate.setString(key, value);
    if (!failed) {
      failed = true;
      return false;
    }
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Directory records;
  late SharedPreferences prefs;
  late BackupCatalog catalog;
  late BackupService service;

  String path(Directory dir, String name) =>
      '${dir.path}${Platform.pathSeparator}$name';
  File record(String name) => File(path(records, name));

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('purechess-backup-test-');
    records = await Directory(path(temp, 'records')).create();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    catalog = BackupCatalog(
      tutorialCount: 18,
      puzzleIds: {..._ids, 'p10'},
      classicPlies: {'classic': 50, 'other': 20},
    );
    service = BackupService(prefs, records, catalog);
  });

  tearDown(() async => temp.delete(recursive: true));

  test(
    'ZIP round trip restores PGN, all progress/settings, not privacy',
    () async {
      final values = _progress();
      SharedPreferences.setMockInitialValues({
        ...values,
        'analyticsEnabled': true,
        'privacyAccepted': true,
        'crashStreak': 5,
      });
      prefs = await SharedPreferences.getInstance();
      service = BackupService(prefs, records, catalog);
      await record('练习.pgn').writeAsString(_pgn);
      final bytes = await service.exportBytes();
      final data = BackupData.decode(bytes);
      expect(data.records, {'练习.pgn': _pgn});
      expect(data.preferences, values);
      expect(data.recordCount, 1);
      expect(data.tutorialCompleted, 5);
      expect(data.puzzleCompleted, 1);
      expect(data.dailyCount, 1);
      final manifest = jsonDecode(
        utf8.decode(
          ZipDecoder().decodeBytes(bytes).findFile('manifest.json')!.content,
        ),
      ) as Map<String, dynamic>;
      expect(manifest['version'], 1);
      expect(manifest['records'], [
        {'id': 'game-1', 'file': 'records/练习.pgn'},
      ]);
      await prefs.clear();
      await prefs.setBool('analyticsEnabled', false);
      await prefs.setBool('privacyAccepted', false);
      await prefs.setInt('crashStreak', 7);
      await record('练习.pgn').delete();
      final zipFile = await File(path(temp, 'backup.zip')).writeAsBytes(bytes);
      await service.restore(await service.read(zipFile));
      for (final entry in values.entries) {
        expect(prefs.get(entry.key), entry.value);
      }
      expect(prefs.getBool('analyticsEnabled'), false);
      expect(prefs.getBool('privacyAccepted'), false);
      expect(prefs.getInt('crashStreak'), 7);
      expect(
        Pgn.generate(
          await RecordsRepository(records).read(record('练习.pgn').path),
        ),
        Pgn.generate(Pgn.parse(_pgn)),
      );
      await service.restore(data);
      expect(await RecordsRepository(records).list(), hasLength(1));
      expect(await Directory(path(temp, '.backup-restore')).exists(), false);
    },
  );

  test(
    'empty backup round trip is valid and preserves local-only data',
    () async {
      final empty = BackupData.decode(await service.exportBytes());
      expect(empty.recordCount, 0);
      await record('local.pgn').writeAsString(_pgn);
      await prefs.setInt('tutorial_progress', 9);
      await service.restore(empty);
      expect(prefs.getInt('tutorial_progress'), 9);
      expect(await record('local.pgn').readAsString(), _pgn);
    },
  );

  test('merge takes max tutorial, unions solved/daily, resolves mistakes', () {
    final local = _progress(
      tutorial: 12,
      solved: ['p0', 'p1'],
      mistakes: ['p2'],
      daily: ['p0', 'p1'],
      ply: 20,
    );
    final incoming = _progress(
      tutorial: 3,
      solved: ['p1', 'p2'],
      mistakes: ['p0', 'p3'],
      daily: ['p1', 'p2'],
      ply: 2,
    );
    final merged = BackupData.mergePreferences(local, incoming);
    expect(merged['tutorial_progress'], 12);
    expect(jsonDecode(merged['library_reading'] as String)['ply'], 20);
    final puzzle = BackupData.puzzleProgress(merged['puzzle_progress_v1']);
    expect(puzzle['solved'], ['p0', 'p1', 'p2']);
    expect(puzzle['mistakes'], ['p3']);
    expect(puzzle['dailySolved'], {
      _day: ['p0', 'p1', 'p2'],
    });
    expect(BackupData.mergePreferences(merged, incoming), merged);
    expect(
      BackupData.mergePreferences(incoming, local)['puzzle_progress_v1'],
      merged['puzzle_progress_v1'],
    );
  });

  test(
    'newer tutorial/bookmark advance; different books keep local position',
    () {
      final local = _progress(tutorial: 1, ply: 1);
      final next = _progress(tutorial: 9, ply: 9);
      expect(BackupData.mergePreferences(local, next)['tutorial_progress'], 9);
      expect(
        jsonDecode(
          BackupData.mergePreferences(local, next)['library_reading'] as String,
        )['ply'],
        9,
      );
      next['library_reading'] = jsonEncode({'id': 'other', 'ply': 2});
      expect(
        BackupData.mergePreferences(local, next)['library_reading'],
        local['library_reading'],
      );
    },
  );

  test(
    'deduplication uses Id, not filename; filename collisions keep both',
    () async {
      await record('same.pgn').writeAsString(_pgn);
      await service.restore(
        BackupData.create({}, {
          'renamed.pgn': _pgn.replaceFirst('中心', '备份评注'),
          'same.pgn': _pgn.replaceFirst('game-1', 'game-2'),
        }),
      );
      expect(await record('same.pgn').readAsString(), _pgn);
      final files = await RecordsRepository(records).list();
      expect(files, hasLength(2));
      final games = await Future.wait(
        files.map((f) => RecordsRepository(records).read(f.path)),
      );
      expect(games.map((g) => g.tags['Id']).toSet(), {'game-1', 'game-2'});
      await service.restore(
        BackupData.create({}, {
          'another.pgn': _pgn.replaceFirst('game-1', 'game-2'),
        }),
      );
      expect(await RecordsRepository(records).list(), hasLength(2));
    },
  );

  test(
    'legacy filename identity survives a restore rename and re-export',
    () async {
      final old = '1. d4 d5 *';
      final backup = BackupData.create({}, {'same.pgn': old});
      await record('same.pgn').writeAsString(_pgn);
      await service.restore(backup);
      await service.restore(backup);
      expect(await RecordsRepository(records).list(), hasLength(2));
      final exported = BackupData.decode(await service.exportBytes());
      expect(
        exported.records.values.map((pgn) => Pgn.parse(pgn).tags['Id']),
        contains('legacy:same.pgn'),
      );
    },
  );

  test('new saves carry persistent distinct IDs', () async {
    final repo = RecordsRepository(records);
    final a = await repo.read(await repo.save(Pgn.parse('1. e4 *')));
    final b = await repo.read(await repo.save(Pgn.parse('1. e4 *')));
    expect(a.tags['Id'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a.tags['Id'], isNot(b.tags['Id']));
  });

  test(
    'write failure rolls back records and preferences, including cache',
    () async {
      final before = _progress(tutorial: 2);
      for (final entry in before.entries) {
        if (entry.value is int) {
          await prefs.setInt(entry.key, entry.value as int);
        } else {
          await prefs.setString(entry.key, entry.value as String);
        }
      }
      await record('local.pgn').writeAsString(_pgn);
      final failing = BackupService(
        _FailOncePreferences(prefs),
        records,
        catalog,
      );
      await expectLater(
        failing.restore(
          BackupData.create(_progress(tutorial: 8, solved: ['p0', 'p1']), {
            'new.pgn': _pgn.replaceFirst('game-1', 'game-2'),
          }),
        ),
        throwsStateError,
      );
      expect(await record('local.pgn').readAsString(), _pgn);
      expect(await RecordsRepository(records).list(), hasLength(1));
      for (final entry in before.entries) {
        expect(prefs.get(entry.key), entry.value);
      }
      await prefs.reload();
      expect(prefs.getInt('tutorial_progress'), 2);
      expect(await Directory(path(temp, '.backup-restore')).exists(), false);
    },
  );

  test(
    'interrupted publication is rolled back before next app startup',
    () async {
      await record('local.pgn').writeAsString(_pgn);
      final work = await Directory(path(temp, '.backup-restore')).create();
      await File(path(work, 'before.json')).writeAsString(
        jsonEncode({
          'hadRecords': true,
          'preferences': {'tutorial_progress': 2},
        }),
      );
      await records.rename(path(work, 'previous'));
      await records.create();
      await record('new.pgn')
          .writeAsString(_pgn.replaceFirst('game-1', 'game-2'));
      await prefs.setInt('tutorial_progress', 12);
      await prefs.setInt('chess.ai.recommendedLevel', 8);
      await BackupService.recoverPending(prefs, records);
      expect(await record('local.pgn').readAsString(), _pgn);
      expect(await record('new.pgn').exists(), false);
      expect(prefs.getInt('tutorial_progress'), 2);
      expect(prefs.get('chess.ai.recommendedLevel'), isNull);
      await BackupService.recoverPending(prefs, records);
    },
  );

  test('committed recovery only cleans up and never rolls back', () async {
    final work = await Directory(path(temp, '.backup-restore')).create();
    await File(path(work, 'committed.json')).writeAsString('{}');
    await record('new.pgn').writeAsString(_pgn);
    await prefs.setInt('tutorial_progress', 12);
    await BackupService.recoverPending(prefs, records);
    expect(await record('new.pgn').exists(), true);
    expect(prefs.getInt('tutorial_progress'), 12);
    expect(await work.exists(), false);
  });

  test(
    'conflicting daily sets reject before modifying any local data',
    () async {
      final local = _progress();
      for (final entry in local.entries) {
        if (entry.value is int) {
          await prefs.setInt(entry.key, entry.value as int);
        } else {
          await prefs.setString(entry.key, entry.value as String);
        }
      }
      await record('local.pgn').writeAsString(_pgn);
      final conflicting = _progress(tutorial: 15);
      conflicting[_day] = jsonEncode([..._ids.take(9), 'p10']);
      await expectLater(
        service.restore(BackupData.create(conflicting, {})),
        throwsFormatException,
      );
      expect(prefs.getInt('tutorial_progress'), 5);
      expect(await record('local.pgn').readAsString(), _pgn);
      expect(await Directory(path(temp, '.backup-restore')).exists(), false);
    },
  );

  for (final values in [
    {'tutorial_progress': 19},
    {'library_reading': '{"id":"missing","ply":1}'},
    {'library_reading': '{"id":"classic","ply":99}'},
    {
      'puzzle_progress_v1':
          '{"solved":["unknown"],"mistakes":[],"dailySolved":{}}',
    },
  ]) {
    test('catalog rejects unsupported data: $values', () async {
      final data = BackupData.create(values, {});
      await expectLater(service.restore(data), throwsFormatException);
      expect(prefs.getKeys(), isEmpty);
    });
  }

  for (final bytes in [
    Uint8List(0),
    Uint8List.fromList([1, 2, 3]),
    _zip(includeManifest: false),
    _zip(records: {'records/bad.pgn': 'not PGN'}),
    _zip(records: {'records/bad.pgn': '[Id "game-1"] 1. e5 *'}),
    _zip(records: {'records/bad.pgn': '[Id "different"] *'}),
    _zip(records: {'records/a.pgn': _pgn, 'records/b.pgn': _pgn}),
  ]) {
    test('corrupt archive rejected (${bytes.length} bytes)', () {
      expect(() => BackupData.decode(bytes), throwsFormatException);
    });
  }

  for (final change in <Map<String, Object?>>[
    {'version': 2},
    {'version': 1.0},
    {'format': 'pureweiqi-backup'},
    {'createdAt': 'invalid'},
    {'preferences': []},
    {
      'preferences': {'analyticsEnabled': true},
    },
    {
      'preferences': {'tutorial_progress': -1},
    },
    {
      'preferences': {'tutorial_progress': '5'},
    },
    {
      'preferences': {'chess.ai.recommendedLevel': 11},
    },
    {
      'preferences': {'puzzle_progress_v1': '{"solved":[]}'},
    },
    {
      'preferences': {'daily_20260230': jsonEncode(_ids)},
    },
    {
      'preferences': {_day: '["p0"]'},
    },
    {
      'preferences': {'library_reading': '{"id":"classic","ply":-1}'},
    },
    {
      'records': [
        {'id': 'missing', 'file': 'records/missing.pgn'},
      ],
    },
  ]) {
    test('invalid manifest rejected: $change', () {
      expect(
        () => BackupData.decode(
          _zip(
            manifest: {
              'format': 'purechess-backup',
              'version': 1,
              'createdAt': '2026-09-28T00:00:00Z',
              'preferences': {},
              'records': [],
              ...change,
            },
          ),
        ),
        throwsFormatException,
      );
    });
  }

  for (final name in [
    '../outside.pgn',
    '/records/a.pgn',
    'records/../a.pgn',
    r'records/a\b.pgn',
    'records/CON.pgn',
    'records/sub/a.pgn',
    'unexpected.json',
    'records/a.pgn:stream',
  ]) {
    test('unsafe archive path rejected: $name', () {
      expect(
        () => BackupData.decode(_zip(records: {name: _pgn})),
        throwsFormatException,
      );
    });
  }

  test('CRC corruption and truncated ZIP rejected', () {
    final bytes = _zip(records: {'records/a.pgn': _pgn});
    final corrupt = Uint8List.fromList(bytes);
    // Flip the central-directory CRC without changing the compressed data.
    for (var i = 0; i < corrupt.length - 20; i++) {
      if (corrupt[i] == 0x50 &&
          corrupt[i + 1] == 0x4b &&
          corrupt[i + 2] == 1 &&
          corrupt[i + 3] == 2) {
        corrupt[i + 16] ^= 0xff;
        break;
      }
    }
    expect(() => BackupData.decode(corrupt), throwsFormatException);
    expect(
      () =>
          BackupData.decode(Uint8List.sublistView(bytes, 0, bytes.length - 40)),
      throwsFormatException,
    );
  });

  test('oversized entry and forged inflate size rejected', () {
    final bomb = _zip(
      extra: [
        ArchiveFile.string(
          'records/huge.pgn',
          'a' * (BackupData.maxFileBytes + 1),
        ),
      ],
    );
    expect(() => BackupData.decode(bomb), throwsFormatException);
    final forged = Uint8List.fromList(bomb);
    final view = ByteData.sublistView(forged);
    for (var i = 0; i < forged.length - 30; i++) {
      if (view.getUint32(i, Endian.little) == 0x02014b50) {
        view.setUint32(i + 24, 10, Endian.little);
      }
    }
    expect(() => BackupData.decode(forged), throwsFormatException);
  });

  test('real bundled catalog accepts an empty snapshot', () async {
    (await BackupCatalog.load()).validate(BackupData.create({}, {}));
  });
}
