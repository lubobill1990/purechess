import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/game_tree.dart';
import '../../core/pgn.dart';

class RecordFileInfo {
  const RecordFileInfo({
    required this.path,
    required this.name,
    required this.modified,
  });

  final String path;
  final String name;
  final DateTime modified;
}

/// PGN files under the application's absolute documents/purechess/records path.
/// I/O and parse failures propagate to the caller for visible error reporting.
class RecordsRepository {
  RecordsRepository(this.dir);

  static Future<void> _pendingSave = Future<void>.value();
  final Directory dir;

  static Future<RecordsRepository> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}purechess'
      '${Platform.pathSeparator}records',
    );
    await dir.create(recursive: true);
    return RecordsRepository(dir);
  }

  Future<List<RecordFileInfo>> list() async {
    final result = <RecordFileInfo>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.pgn')) {
        continue;
      }
      final filename = entity.uri.pathSegments.last;
      result.add(
        RecordFileInfo(
          path: entity.path,
          name: filename.substring(0, filename.length - 4),
          modified: (await entity.stat()).modified,
        ),
      );
    }
    result.sort((a, b) {
      final byDate = b.modified.compareTo(a.modified);
      return byDate == 0 ? a.name.compareTo(b.name) : byDate;
    });
    return result;
  }

  Future<GameRecord> read(String path) async =>
      Pgn.parse(await File(path).readAsString());

  Future<String> save(GameRecord record, {String? name}) async {
    final pgn = Pgn.generate(record);
    final base = _sanitize(
      name ??
          '${record.tags['Date'] ?? '对局'}-${DateTime.now().microsecondsSinceEpoch}',
    );
    // POSIX locks are process-scoped, so also serialize saves in this isolate.
    final previous = _pendingSave;
    final done = Completer<void>();
    _pendingSave = done.future;
    await previous;
    try {
      return await _publish(pgn, base);
    } finally {
      done.complete();
    }
  }

  Future<String> _publish(String pgn, String base) async {
    await dir.create(recursive: true);
    // Serialize publication across repository instances using an OS file lock.
    final lock = await File('${dir.path}${Platform.pathSeparator}.save.lock')
        .open(mode: FileMode.append);
    Directory? staging;
    try {
      await lock.lock(FileLock.blockingExclusive);
      var path = '${dir.path}${Platform.pathSeparator}$base.pgn';
      var suffix = 2;
      while (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        path = '${dir.path}${Platform.pathSeparator}$base ($suffix).pgn';
        suffix++;
      }
      staging = await dir.createTemp('.pgn-');
      final temp = File('${staging.path}${Platform.pathSeparator}record.tmp');
      await temp.writeAsString(pgn, flush: true);
      await temp.rename(path);
      return path;
    } finally {
      try {
        if (staging != null) await staging.delete(recursive: true);
      } finally {
        await lock.close();
      }
    }
  }

  String _sanitize(String name) {
    var safe = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (safe.isEmpty) safe = '对局';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
      caseSensitive: false,
    ).hasMatch(safe)) {
      safe = '_$safe';
    }
    // Keep room for the suffix and extension on mobile and desktop filesystems.
    return String.fromCharCodes(safe.runes.take(60));
  }
}
