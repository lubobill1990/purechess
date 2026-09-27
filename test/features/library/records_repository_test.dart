import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/game_tree.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/features/library/records_repository.dart';

void main() {
  late Directory dir;
  late RecordsRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('purechess_records_test_');
    repo = RecordsRepository(dir);
  });

  tearDown(() async => dir.delete(recursive: true));

  test(
    'saves UTF-8 PGN with metadata, moves and result across repository opens',
    () async {
      final record = Pgn.parse('[Event "面对面对弈"] 1. f3 e5 2. g4 Qh4# 0-1');
      final path = await repo.save(record, name: '对弈');
      expect(path, endsWith('${Platform.pathSeparator}对弈.pgn'));
      final reopened = RecordsRepository(dir);
      final restored = await reopened.read(path);
      expect(Pgn.generate(restored), Pgn.generate(record));
      expect((await reopened.list()).single.path, path);
      expect((await reopened.list()).single.name, '对弈');
      expect(await dir.list().where((e) => e is Directory).isEmpty, isTrue);
    },
  );

  test(
    'duplicate and concurrent saves never overwrite existing games',
    () async {
      final first = await repo.save(GameRecord(), name: 'same');
      final paths = await Future.wait([
        repo.save(Pgn.parse('1. e4 *'), name: 'same'),
        RecordsRepository(dir).save(Pgn.parse('1. d4 *'), name: 'same'),
      ]);
      expect({first, ...paths}.length, 3);
      expect((await repo.read(first)).root.isLeaf, isTrue);
      expect((await repo.read(paths[0])).mainLine.last.move!.uci, 'e2e4');
      expect((await repo.read(paths[1])).mainLine.last.move!.uci, 'd2d4');
    },
  );

  test('lists only regular PGN files sorted newest first', () async {
    final first = File(await repo.save(GameRecord(), name: 'first'));
    final second = File(await repo.save(GameRecord(), name: 'second'));
    await first.setLastModified(DateTime(2020));
    await second.setLastModified(DateTime(2021));
    await File('${dir.path}${Platform.pathSeparator}partial.tmp')
        .writeAsString('not a game');
    await Directory('${dir.path}${Platform.pathSeparator}folder.pgn').create();
    await File('${dir.path}${Platform.pathSeparator}external.PGN')
        .writeAsString('*');
    expect((await repo.list()).map((file) => file.name), [
      'external',
      'second',
      'first',
    ]);
  });

  for (final name in [
    '../escape',
    'a/b\\c:*?"<>|',
    '...',
    ' ',
    'CON',
    'nul.txt',
  ]) {
    test(
      'sanitizes unsafe filename "$name" inside records directory',
      () async {
        final path = await repo.save(GameRecord(), name: name);
        expect(File(path).parent.path, dir.path);
        expect(
          File(path).uri.pathSegments.last,
          isNot(matches(RegExp(r'[<>:"/\\|?*]'))),
        );
        expect(await File(path).exists(), isTrue);
      },
    );
  }

  test('long Unicode filenames stay within filesystem limits', () async {
    for (final char in ['棋', String.fromCharCode(0x1F600)]) {
      final path = await repo.save(GameRecord(), name: char * 500);
      expect(
        File(path).uri.pathSegments.last.runes.length,
        lessThanOrEqualTo(64),
      );
    }
    expect((await repo.list()).length, 2);
  });

  test('failed publication propagates and a later retry succeeds', () async {
    final blocked = File('${dir.path}${Platform.pathSeparator}blocked');
    await blocked.writeAsString('file');
    final broken = RecordsRepository(Directory(blocked.path));
    await expectLater(
      broken.save(GameRecord()),
      throwsA(isA<FileSystemException>()),
    );
    final path = await repo.save(GameRecord());
    expect(await File(path).exists(), isTrue);
  });

  test('invalid PGN read and missing file are explicit errors', () async {
    final file = File('${dir.path}${Platform.pathSeparator}invalid.pgn');
    await file.writeAsString('not a valid game');
    await expectLater(repo.read(file.path), throwsFormatException);
    await expectLater(
      repo.read('${dir.path}${Platform.pathSeparator}missing.pgn'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
