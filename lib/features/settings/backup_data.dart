import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/pgn.dart';
import '../achievements/achievements.dart';
import '../game/ai_difficulty.dart';
import '../library/classic_library.dart';
import '../puzzle/puzzle_repository.dart';
import '../tutorial/tutorial_controller.dart';

/// No filesystem extraction: only flat, validated PGN paths enter the snapshot.
class BackupData {
  BackupData._(this.preferences, this.records, this.createdAt);

  static const maxZipBytes = 64 * 1024 * 1024;
  static const maxFileBytes = 8 * 1024 * 1024;
  static const maxTotalBytes = 128 * 1024 * 1024;
  static const maxEntries = 10000;
  static final dailyPattern = RegExp(r'^daily_\d{8}$');
  static const preferenceKeys = {
    AchievementData.preferenceKey,
    TutorialController.progressKey,
    PuzzleRepository.progressKey,
    AiDifficulty.preferenceKey,
    ReadingProgress.key,
  };

  final Map<String, Object> preferences;
  final Map<String, String> records;
  final DateTime createdAt;

  int get recordCount => records.length;
  int get tutorialCompleted =>
      preferences[TutorialController.progressKey] as int? ?? 0;
  int get puzzleCompleted => preferences[PuzzleRepository.progressKey] == null
      ? 0
      : (puzzleProgress(preferences[PuzzleRepository.progressKey])['solved']
                as List)
            .length;
  int get dailyCount => preferences.keys.where(dailyPattern.hasMatch).length;

  static bool includes(String key) =>
      preferenceKeys.contains(key) || dailyPattern.hasMatch(key);

  static BackupData create(
    Map<String, Object> preferences,
    Map<String, String> records, {
    DateTime? createdAt,
  }) {
    final checked = validatePreferences(preferences);
    final ids = <String>{};
    for (final entry in records.entries) {
      validatePath('records/${entry.key}');
      if (!ids.add(recordId(entry.key, entry.value))) {
        throw const FormatException('备份含重复的棋谱 ID');
      }
    }
    return BackupData._(
      Map.unmodifiable(checked),
      Map.unmodifiable(records),
      createdAt ?? DateTime.now().toUtc(),
    );
  }

  static String recordId(String name, String pgn) {
    final record = Pgn.parse(pgn);
    final id = record.tags['Id'] ?? 'legacy:$name';
    if (id.trim().isEmpty ||
        id.length > 512 ||
        RegExp(r'[\x00-\x1f]').hasMatch(id)) {
      throw const FormatException('棋谱 ID 无效');
    }
    return id;
  }

  Uint8List encode() {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'format': 'purechess-backup',
            'version': 1,
            'createdAt': createdAt.toUtc().toIso8601String(),
            'preferences': preferences,
            'records': [
              for (final entry in records.entries)
                {
                  'id': recordId(entry.key, entry.value),
                  'file': 'records/${entry.key}',
                },
            ],
          }),
        ),
      );
    for (final entry in records.entries) {
      archive.addFile(ArchiveFile.string('records/${entry.key}', entry.value));
    }
    if (archive.length > maxEntries ||
        archive.files.any((f) => f.size > maxFileBytes) ||
        archive.files.fold<int>(0, (n, f) => n + f.size) > maxTotalBytes) {
      throw const FormatException('备份内容超出大小或数量限制');
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    if (bytes.length > maxZipBytes) {
      throw const FormatException('备份文件超过 64 MB');
    }
    return bytes;
  }

  static BackupData decode(Uint8List bytes) {
    try {
      return _decode(bytes);
    } on FormatException {
      rethrow;
    } catch (_) {
      // Archive's low-level decoder also throws range/state errors on bad ZIPs.
      throw const FormatException('备份文件损坏，无法读取 ZIP 内容');
    }
  }

  static BackupData _decode(Uint8List bytes) {
    if (bytes.length > maxZipBytes) {
      throw const FormatException('备份文件超过 64 MB');
    }
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.fileHeaders.isEmpty ||
        directory.fileHeaders.length > maxEntries) {
      throw const FormatException('备份为空或文件数量超出限制');
    }
    final names = <String>{};
    var total = 0;
    for (final header in directory.fileHeaders) {
      final file = header.file;
      if (file == null ||
          header.filename != file.filename ||
          !names.add(header.filename.toLowerCase()) ||
          (header.externalFileAttributes >> 16) & 0xf000 == 0xa000 ||
          file.flags & 1 != 0 ||
          ![0, 8].contains(header.compressionMethod) ||
          file.compressionMethod !=
              (header.compressionMethod == 8
                  ? CompressionType.deflate
                  : CompressionType.none)) {
        throw const FormatException('备份含重复文件、链接、加密或不支持的压缩格式');
      }
      validatePath(header.filename);
      total += header.uncompressedSize;
      if (header.uncompressedSize < 0 ||
          header.uncompressedSize > maxFileBytes ||
          total > maxTotalBytes) {
        throw const FormatException('备份解压大小超出限制');
      }
    }
    final contents = <String, String>{};
    for (final header in directory.fileHeaders) {
      final output = _LimitedOutput(header.uncompressedSize);
      final compressed = header.file!.getStream(decompress: false);
      // Stream inflation enforces the limit even with forged ZIP size fields.
      if (header.compressionMethod == 8) {
        Inflate.stream(compressed, output: output);
      } else {
        output.writeStream(compressed);
      }
      final content = output.getBytes();
      if (content.length != header.uncompressedSize ||
          getCrc32(content) != header.crc32) {
        throw const FormatException('备份文件损坏（大小或校验和不符）');
      }
      contents[header.filename] = utf8.decode(content);
    }
    final raw = contents.remove('manifest.json');
    if (raw == null) throw const FormatException('缺少备份清单 manifest.json');
    final manifest = jsonDecode(raw);
    if (manifest is! Map<String, dynamic> ||
        manifest['format'] != 'purechess-backup' ||
        manifest['version'] is! int ||
        manifest['version'] != 1 ||
        manifest['createdAt'] is! String ||
        manifest['preferences'] is! Map<String, dynamic> ||
        manifest['records'] is! List) {
      throw const FormatException('备份版本或结构不受支持，请使用兼容版本的纯弈国际象棋');
    }
    final date = DateTime.tryParse(manifest['createdAt'] as String);
    if (date == null) throw const FormatException('备份日期无效');
    final listed = <String>{};
    for (final item in manifest['records'] as List) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! String ||
          item['file'] is! String) {
        throw const FormatException('备份棋谱索引无效');
      }
      final path = item['file'] as String;
      if (!listed.add(path) ||
          !contents.containsKey(path) ||
          recordId(path.substring('records/'.length), contents[path]!) !=
              item['id']) {
        throw const FormatException('备份棋谱与清单不一致');
      }
    }
    if (listed.length != contents.length) {
      throw const FormatException('备份含未登记的棋谱');
    }
    return create(
      validatePreferences(manifest['preferences'] as Map<String, dynamic>),
      {
        for (final entry in contents.entries)
          entry.key.substring('records/'.length): entry.value,
      },
      createdAt: date,
    );
  }

  static void validatePath(String name) {
    if (name == 'manifest.json') return;
    final parts = name.split('/');
    if (parts.length != 2 ||
        parts.first != 'records' ||
        !parts.last.toLowerCase().endsWith('.pgn') ||
        parts.last.length > 200 ||
        parts.last.endsWith(' ') ||
        RegExp(r'[<>:"\\|?*\x00-\x1f]').hasMatch(parts.last) ||
        RegExp(
          r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(parts.last)) {
      throw const FormatException('备份含无效或不安全的棋谱路径');
    }
  }

  static Map<String, dynamic> puzzleProgress(Object? raw) {
    if (raw is! String) throw const FormatException('谜题进度格式无效');
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data.keys.toSet().difference({
          'solved',
          'mistakes',
          'dailySolved',
        }).isNotEmpty ||
        !_ids(data['solved']) ||
        !_ids(data['mistakes']) ||
        data['dailySolved'] is! Map<String, dynamic>) {
      throw const FormatException('谜题进度结构无效');
    }
    for (final entry in (data['dailySolved'] as Map<String, dynamic>).entries) {
      if (!_day(entry.key) ||
          !_ids(entry.value) ||
          !(entry.value as List).every(
            (id) => (data['solved'] as List).contains(id),
          )) {
        throw const FormatException('每日题完成进度无效');
      }
    }
    return data;
  }

  static bool _ids(Object? value) =>
      value is List &&
      value.every((id) => id is String && id.isNotEmpty && id.length <= 200) &&
      value.toSet().length == value.length;

  static bool _day(String key) {
    if (!dailyPattern.hasMatch(key)) return false;
    final date = DateTime.tryParse(key.substring(6));
    return date != null && PuzzleRepository.dailyKey(date) == key;
  }

  static Map<String, Object> validatePreferences(Map<String, dynamic> values) {
    final result = <String, Object>{};
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value;
      var valid = false;
      if (key == AchievementData.preferenceKey) {
        AchievementData.decode(value);
        valid = true;
      } else if (key == TutorialController.progressKey) {
        valid = value is int && value >= 0;
      } else if (key == AiDifficulty.preferenceKey) {
        valid = value is int && value >= 1 && value <= 10;
      } else if (key == PuzzleRepository.progressKey) {
        puzzleProgress(value);
        valid = true;
      } else if (_day(key) && value is String) {
        final ids = jsonDecode(value);
        valid = _ids(ids) && (ids as List).length == 10;
      } else if (key == ReadingProgress.key && value is String) {
        final bookmark = jsonDecode(value);
        valid =
            bookmark is Map<String, dynamic> &&
            bookmark['id'] is String &&
            (bookmark['id'] as String).isNotEmpty &&
            bookmark['ply'] is int &&
            (bookmark['ply'] as int) >= 0;
      }
      if (!valid) throw FormatException('备份进度或设置无效：$key');
      result[key] = value as Object;
    }
    final puzzle = result[PuzzleRepository.progressKey];
    if (puzzle != null) {
      final days =
          puzzleProgress(puzzle)['dailySolved'] as Map<String, dynamic>;
      for (final day in days.entries) {
        final raw = result[day.key];
        if (raw is! String ||
            !(day.value as List).every(
              (id) => (jsonDecode(raw) as List).contains(id),
            )) {
          throw const FormatException('每日题进度与题目清单不一致');
        }
      }
    }
    return result;
  }

  static Map<String, Object> mergePreferences(
    Map<String, Object> local,
    Map<String, Object> incoming,
  ) {
    validatePreferences(local);
    validatePreferences(incoming);
    final merged = {...local, ...incoming};
    for (final entry in local.entries) {
      final other = incoming[entry.key];
      if (other == null) continue;
      if (entry.key == AchievementData.preferenceKey) {
        merged[entry.key] = AchievementData.merge(
          AchievementData.decode(entry.value),
          AchievementData.decode(other),
        ).encode();
      } else if (entry.key == TutorialController.progressKey) {
        merged[entry.key] = max(entry.value as int, other as int);
      } else if (dailyPattern.hasMatch(entry.key)) {
        final a = (jsonDecode(entry.value as String) as List).toSet();
        final b = (jsonDecode(other as String) as List).toSet();
        if (a.length != b.length || !a.containsAll(b)) {
          throw const FormatException('同一天的每日题清单冲突，无法安全合并；尚未恢复任何内容');
        }
        merged[entry.key] = entry.value;
      } else if (entry.key == ReadingProgress.key) {
        final a = jsonDecode(entry.value as String) as Map<String, dynamic>;
        final b = jsonDecode(other as String) as Map<String, dynamic>;
        // Different books have incomparable positions: keep the local bookmark.
        merged[entry.key] = a['id'] == b['id']
            ? jsonEncode({
                'id': a['id'],
                'ply': max(a['ply'] as int, b['ply'] as int),
              })
            : entry.value;
      } else if (entry.key == PuzzleRepository.progressKey) {
        final a = puzzleProgress(entry.value);
        final b = puzzleProgress(other);
        List<String> union(Object? x, Object? y) => {
          ...(x as List? ?? []),
          ...(y as List? ?? []),
        }.cast<String>().toList()..sort();
        final solved = union(a['solved'], b['solved']);
        final daysA = a['dailySolved'] as Map<String, dynamic>;
        final daysB = b['dailySolved'] as Map<String, dynamic>;
        merged[entry.key] = jsonEncode({
          'solved': solved,
          'mistakes': union(a['mistakes'], b['mistakes'])
            ..removeWhere(solved.contains),
          'dailySolved': {
            for (final day in {...daysA.keys, ...daysB.keys})
              day: union(daysA[day], daysB[day]),
          },
        });
      }
    }
    return validatePreferences(merged);
  }
}

class _LimitedOutput extends OutputMemoryStream {
  _LimitedOutput(this.limit);
  final int limit;

  void _check(int count) {
    if (count < 0 || length + count > limit) {
      throw const FormatException('备份解压大小与清单不符');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
