import 'dart:io';

import 'package:purechess/core/game_tree.dart';
import 'package:purechess/core/pgn.dart';
import 'package:purechess/features/library/records_repository.dart';

class MemoryRecordsRepository extends RecordsRepository {
  MemoryRecordsRepository() : super(Directory('unused'));

  final List<GameRecord> saved = [];
  bool failSave = false;
  bool failList = false;
  bool failRead = false;

  @override
  Future<String> save(GameRecord record, {String? name}) async {
    if (failSave) throw const FileSystemException('Storage full');
    saved.add(Pgn.parse(Pgn.generate(record)));
    return '${saved.length}.pgn';
  }

  @override
  Future<List<RecordFileInfo>> list() async {
    if (failList) throw const FileSystemException('Storage unavailable');
    return [
      for (var index = 0; index < saved.length; index++)
        RecordFileInfo(
          path: '$index.pgn',
          name: '对局 ${index + 1}',
          modified: DateTime(2026, 9, 28),
        ),
    ];
  }

  @override
  Future<GameRecord> read(String path) async {
    if (failRead) throw const FormatException('Invalid PGN');
    return saved[int.parse(path.split('.').first)];
  }
}
