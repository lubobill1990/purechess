import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/telemetry/app_logger.dart';
import '../../core/pgn.dart';
import '../library/classic_library.dart';
import '../library/records_repository.dart';
import '../puzzle/puzzle_catalog.dart';
import '../puzzle/puzzle_repository.dart';
import '../tutorial/tutorial_level.dart';
import 'backup_data.dart';

class BackupCatalog {
  BackupCatalog({
    required this.tutorialCount,
    required this.puzzleIds,
    required this.classicPlies,
  });

  final int tutorialCount;
  final Set<String> puzzleIds;
  final Map<String, int> classicPlies;

  static Future<BackupCatalog> load() async {
    final tutorial = await TutorialCatalog.load();
    final puzzles = await PuzzleCatalog.load();
    final classics = await ClassicLibrary.load();
    return BackupCatalog(
      tutorialCount: tutorial.levels.length,
      puzzleIds: puzzles.byId.keys.toSet(),
      classicPlies: {for (final game in classics) game.id: game.plies},
    );
  }

  void validate(BackupData data) {
    if (data.tutorialCompleted > tutorialCount) {
      throw const FormatException('备份教程进度超出当前版本，请先更新应用');
    }
    void checkIds(List<dynamic> ids) {
      if (ids.any((id) => !puzzleIds.contains(id))) {
        throw const FormatException('备份引用了当前版本没有的谜题，请先更新应用');
      }
    }

    final puzzle = data.preferences[PuzzleRepository.progressKey];
    if (puzzle != null) {
      final progress = BackupData.puzzleProgress(puzzle);
      checkIds(progress['solved'] as List);
      checkIds(progress['mistakes'] as List);
    }
    for (final entry in data.preferences.entries) {
      if (BackupData.dailyPattern.hasMatch(entry.key)) {
        checkIds(jsonDecode(entry.value as String) as List);
      }
    }
    final reading = data.preferences[ReadingProgress.key];
    if (reading != null) {
      final mark = jsonDecode(reading as String) as Map<String, dynamic>;
      final limit = classicPlies[mark['id']];
      if (limit == null || (mark['ply'] as int) > limit) {
        throw const FormatException('备份名局阅读位置无效或当前版本不支持');
      }
    }
  }
}

class BackupService {
  BackupService(this.prefs, this.recordsDirectory, this.catalog);

  final SharedPreferences prefs;
  final Directory recordsDirectory;
  final BackupCatalog catalog;

  static String _path(Directory dir, String name) =>
      '${dir.path}${Platform.pathSeparator}$name';

  Map<String, Object> _preferences() => {
    for (final key in prefs.getKeys())
      if (BackupData.includes(key)) key: prefs.get(key)!,
  };

  Future<BackupData> _snapshot() async {
    final records = <String, String>{};
    final ids = <String>{};
    var total = 0;
    if (await recordsDirectory.exists()) {
      final files = await RecordsRepository(recordsDirectory).list();
      if (files.length >= BackupData.maxEntries) {
        throw const FormatException('棋谱数量超出备份限制');
      }
      for (final info in files) {
        final file = File(info.path);
        final size = await file.length();
        total += size;
        if (size > BackupData.maxFileBytes ||
            total > BackupData.maxTotalBytes) {
          throw const FormatException('棋谱大小超出备份限制');
        }
        final text = await file.readAsString();
        final name = file.uri.pathSegments.last;
        // Old versions had no Id tag; the stable filename identifies those games.
        final id = BackupData.recordId(name, text);
        if (ids.add(id)) records[name] = text;
      }
    }
    final data = BackupData.create(_preferences(), records);
    catalog.validate(data);
    return data;
  }

  Future<Uint8List> exportBytes() => RecordsRepository.exclusive(() async {
    await recoverPending(prefs, recordsDirectory);
    final snapshot = await _snapshot();
    final bytes = await compute(_encode, snapshot);
    await compute(BackupData.decode, bytes);
    return bytes;
  });

  static Uint8List _encode(BackupData data) => data.encode();

  Future<BackupData> read(File file) async {
    if (await file.length() > BackupData.maxZipBytes) {
      throw const FormatException('备份文件超过 64 MB');
    }
    final data = await compute(BackupData.decode, await file.readAsBytes());
    catalog.validate(data);
    // Check local merge conflicts before showing the confirmation dialog.
    BackupData.mergePreferences(_preferences(), data.preferences);
    return data;
  }

  static Future<void> _replacePreferences(
    SharedPreferences prefs,
    Map<String, Object> values,
  ) async {
    for (final key in prefs.getKeys().where(BackupData.includes).toList()) {
      if (!values.containsKey(key) && !await prefs.remove(key)) {
        throw StateError('无法移除设置：$key');
      }
    }
    for (final entry in values.entries) {
      final saved = switch (entry.value) {
        int value => await prefs.setInt(entry.key, value),
        String value => await prefs.setString(entry.key, value),
        _ => throw StateError('不支持的设置类型：${entry.key}'),
      };
      if (!saved) throw StateError('无法保存设置：${entry.key}');
    }
  }

  static Directory _recovery(Directory records) =>
      Directory(_path(records.parent, '.backup-restore'));

  /// The journal also rolls back an interrupted import before app state loads.
  static Future<void> recoverPending(
    SharedPreferences prefs,
    Directory records,
  ) async {
    final work = _recovery(records);
    if (!await work.exists()) return;
    final journal = File(_path(work, 'before.json'));
    if (await journal.exists()) {
      final before =
          jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
      final previous = Directory(_path(work, 'previous'));
      if (await previous.exists()) {
        if (await records.exists()) {
          final discarded = await work.createTemp('discarded-');
          await records.rename(_path(discarded, 'records'));
        }
        await previous.rename(records.path);
      } else if (before['hadRecords'] == false &&
          !await Directory(_path(work, 'staged')).exists() &&
          await records.exists()) {
        final discarded = await work.createTemp('discarded-');
        await records.rename(_path(discarded, 'records'));
      }
      await _replacePreferences(
        prefs,
        BackupData.validatePreferences(
          before['preferences'] as Map<String, dynamic>,
        ),
      );
      logI('backup', 'Interrupted restore rolled back');
    }
    await work.delete(recursive: true);
  }

  Future<void> restore(BackupData data) =>
      RecordsRepository.exclusive(() async {
        await recoverPending(prefs, recordsDirectory);
        catalog.validate(data);
        // Revalidate the entire snapshot and merge before any persistent write.
        final local = await _snapshot();
        final preferences = BackupData.mergePreferences(
          local.preferences,
          data.preferences,
        );
        final merged = {...local.records};
        final ids = {
          for (final entry in local.records.entries)
            BackupData.recordId(entry.key, entry.value),
        };
        final names = merged.keys.map((name) => name.toLowerCase()).toSet();
        for (final entry in data.records.entries) {
          final id = BackupData.recordId(entry.key, entry.value);
          if (!ids.add(id)) continue;
          var name = entry.key;
          var suffix = 1;
          while (!names.add(name.toLowerCase())) {
            name = 'import-${suffix++}.pgn';
          }
          final record = Pgn.parse(entry.value);
          record.tags['Id'] = id;
          merged[name] = Pgn.generate(record);
        }
        final validated = BackupData.create(preferences, merged);
        catalog.validate(validated);
        final work = _recovery(recordsDirectory);
        await work.create(recursive: true);
        try {
          final staged = await Directory(_path(work, 'staged')).create();
          for (final entry in validated.records.entries) {
            await File(_path(staged, entry.key))
                .writeAsString(entry.value, flush: true);
          }
          // Rename the flushed journal into place before moving any live data.
          final journal = await File(_path(work, 'before.tmp')).writeAsString(
            jsonEncode({
              'hadRecords': await recordsDirectory.exists(),
              'preferences': local.preferences,
            }),
            flush: true,
          );
          await journal.rename(_path(work, 'before.json'));
          if (await recordsDirectory.exists()) {
            await recordsDirectory.rename(_path(work, 'previous'));
          }
          await staged.rename(recordsDirectory.path);
          await _replacePreferences(prefs, preferences);
          await File(_path(work, 'before.json'))
              .rename(_path(work, 'committed.json'));
        } catch (error, stack) {
          logE('backup', 'Restore failed: $error\n$stack');
          try {
            await recoverPending(prefs, recordsDirectory);
          } catch (rollbackError, rollbackStack) {
            logE('backup', 'Rollback failed: $rollbackError\n$rollbackStack');
            throw StateError('恢复中断且回滚尚未完成。请勿修改数据，重启应用以重试恢复。');
          }
          throw StateError('恢复失败，原有数据已保留。请检查可用空间后重试。');
        }
        try {
          await recoverPending(prefs, recordsDirectory);
        } catch (error, stack) {
          // A committed transaction is already durable; cleanup can wait for launch.
          logE('backup', 'Committed restore cleanup failed: $error\n$stack');
          throw StateError('数据已恢复，但临时文件清理失败，请重启应用重试清理。');
        }
      });
}
