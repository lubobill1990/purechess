import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/core/game_tree.dart';
import 'package:purechess/features/library/records_screen.dart';

import '../../support/memory_records_repository.dart';

void main() {
  testWidgets('empty library explains how to save a game', (tester) async {
    final repo = MemoryRecordsRepository();
    await tester.pumpWidget(
      MaterialApp(home: RecordsScreen(openRepository: () async => repo)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有棋谱'), findsOneWidget);
  });

  testWidgets('list failure is visible and retry succeeds', (tester) async {
    final repo = MemoryRecordsRepository()..failList = true;
    await tester.pumpWidget(
      MaterialApp(home: RecordsScreen(openRepository: () async => repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('棋谱库读取失败，请重试'), findsOneWidget);
    repo.failList = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有棋谱'), findsOneWidget);
  });

  testWidgets('corrupt record shows an actionable failure', (tester) async {
    final repo = MemoryRecordsRepository()..failRead = true;
    repo.saved.add(GameRecord());
    await tester.pumpWidget(
      MaterialApp(home: RecordsScreen(openRepository: () async => repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('对局 1'));
    await tester.pumpAndSettle();
    expect(find.text('棋谱打开失败，文件可能损坏或已被移除'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });
}
