import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/features/library/records_repository.dart';
import 'package:purechess/features/settings/backup.dart';
import 'package:purechess/features/settings/backup_data.dart';
import 'package:purechess/features/settings/backup_service.dart';
import 'package:purechess/features/settings/settings.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Picker extends FilePicker {
  String? path;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(type, FileType.custom);
    expect(allowedExtensions, ['zip']);
    expect(allowMultiple, false);
    expect(withData, false);
    return path == null
        ? null
        : FilePickerResult([
            PlatformFile(name: 'backup.zip', size: 0, path: path),
          ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Directory records;
  late SharedPreferences prefs;
  late Analytics analytics;
  late BackupService service;
  late File backup;
  late _Picker picker;
  const storage = MethodChannel('plugins.flutter.io/path_provider');
  const sharing = MethodChannel('dev.fluttercommunity.plus/share');

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('purechess-backup-ui-');
    records = await Directory('${temp.path}${Platform.pathSeparator}records')
        .create();
    SharedPreferences.setMockInitialValues({'tutorial_progress': 2});
    prefs = await SharedPreferences.getInstance();
    analytics = Analytics.testing(directory: temp);
    await analytics.init(prefs);
    service = BackupService(
      prefs,
      records,
      BackupCatalog(tutorialCount: 18, puzzleIds: {}, classicPlies: {}),
    );
    backup = await File('${temp.path}${Platform.pathSeparator}backup.zip')
        .writeAsBytes(
          BackupData.create(
            {'tutorial_progress': 8, 'chess.ai.recommendedLevel': 4},
            {'test.pgn': '[Id "one"] 1. e4 *'},
          ).encode(),
        );
    picker = _Picker()..path = backup.path;
    FilePicker.platform = picker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (_) async => temp.path);
  });

  tearDown(() async {
    analytics.dispose();
    for (final channel in [storage, sharing]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    await temp.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester tester, {
    bool settings = false,
    Future<ShareResult> Function(File, Rect)? shareFile,
    Future<File?> Function()? pickFile,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: settings
            ? SettingsScreen(prefs: prefs, analytics: analytics)
            : BackupScreen(
                prefs: prefs,
                analytics: analytics,
                service: service,
                shareFile: shareFile,
                pickFile: pickFile,
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 300; i++) {
        await tester.pump();
        if (target.evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('Did not find $target');
    });
    await tester.pump(const Duration(milliseconds: 300));
  }

  void expectEvent(String name, int ok) {
    final events =
        File('${temp.path}${Platform.pathSeparator}pending_events.jsonl')
            .readAsLinesSync()
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .where((event) => event['name'] == name);
    expect(events.last['params']['ok'], ok);
  }

  testWidgets('settings entry opens the backup flow', (tester) async {
    await open(tester, settings: true);
    await tester.tap(find.text('备份与恢复'));
    await tester.pumpAndSettle();
    expect(find.byType(BackupScreen), findsOneWidget);
    expect(find.text('导出并分享备份'), findsOneWidget);
  });

  testWidgets('preview precedes restore and confirmation merges records', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('选择备份并恢复'));
    await waitFor(tester, find.text('确认合并恢复？'));
    expect(find.textContaining('1 盘棋谱'), findsOneWidget);
    expect(find.textContaining('教程已完成 8 关'), findsOneWidget);
    expect(prefs.getInt('tutorial_progress'), 2);
    await tester.tap(find.text('合并并恢复'));
    await waitFor(tester, find.textContaining('数据已恢复。'));
    expect(prefs.getInt('tutorial_progress'), 8);
    expect(prefs.getInt('chess.ai.recommendedLevel'), 4);
    expect(
      await tester.runAsync(() => RecordsRepository(records).list()),
      hasLength(1),
    );
    expectEvent('backup_import', 1);
  });

  testWidgets('cancel picker or preview never changes data', (tester) async {
    picker.path = null;
    await open(tester);
    await tester.tap(find.text('选择备份并恢复'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expectEvent('backup_import', 0);
    picker.path = backup.path;
    await tester.tap(find.text('选择备份并恢复'));
    await waitFor(tester, find.text('确认合并恢复？'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(prefs.getInt('tutorial_progress'), 2);
    expect(
      await tester.runAsync(() => RecordsRepository(records).list()),
      isEmpty,
    );
    expectEvent('backup_import', 0);
  });

  testWidgets(
    'invalid ZIP shows a clear error without confirmation or writes',
    (tester) async {
      await tester.runAsync(() => backup.writeAsString('broken zip'));
      await open(tester);
      await tester.tap(find.text('选择备份并恢复'));
      await waitFor(tester, find.textContaining('备份操作失败'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(prefs.getInt('tutorial_progress'), 2);
      expectEvent('backup_import', 0);
    },
  );

  testWidgets('export invokes system sharing with ZIP mime and iPad anchor', (
    tester,
  ) async {
    String? sharedPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sharing, (call) async {
          expect(call.method, 'share');
          final args = call.arguments as Map;
          final paths = args['paths'] as List;
          expect(paths, hasLength(1));
          expect(args['mimeTypes'], ['application/zip']);
          expect(args['originWidth'], greaterThan(0));
          expect(args['originHeight'], greaterThan(0));
          sharedPath = paths.single as String;
          expect(sharedPath, endsWith('.zip'));
          final data = BackupData.decode(await File(sharedPath!).readAsBytes());
          expect(data.tutorialCompleted, 2);
          return 'saved';
        });
    await open(tester);
    await tester.tap(find.text('导出并分享备份'));
    await waitFor(tester, find.textContaining('备份已交给分享面板'));
    expect(sharedPath, isNotNull);
    expect(await tester.runAsync(() => File(sharedPath!).exists()), false);
    expectEvent('backup_export', 1);
  });

  testWidgets('share failure/cancellation cleans up ZIP and records ok=false', (
    tester,
  ) async {
    File? shared;
    var failShare = true;
    await open(
      tester,
      shareFile: (file, origin) async {
        shared = file;
        if (failShare) throw PlatformException(code: 'share_failed');
        return const ShareResult('', ShareResultStatus.dismissed);
      },
    );
    await tester.tap(find.text('导出并分享备份'));
    await waitFor(tester, find.textContaining('备份操作失败'));
    expect(await tester.runAsync(() => shared!.exists()), false);
    expectEvent('backup_export', 0);
    failShare = false;
    await tester.tap(find.text('导出并分享备份'));
    await waitFor(tester, find.text('已取消分享。'));
    expect(await tester.runAsync(() => shared!.exists()), false);
    expectEvent('backup_export', 0);
  });

  testWidgets('busy operation disables actions and blocks back navigation', (
    tester,
  ) async {
    final selection = Completer<File?>();
    await open(tester, pickFile: () => selection.future);
    await tester.tap(find.text('选择备份并恢复'));
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, false);
    selection.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, true);
  });

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets('backup and preview support $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, scale: 2);
      await tester.scrollUntilVisible(find.text('选择备份并恢复'), 150);
      await tester.tap(find.text('选择备份并恢复'));
      await waitFor(tester, find.text('确认合并恢复？'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test('iOS includes file-picker related purpose strings', () {
    final plist = File(
      'ios${Platform.pathSeparator}Runner${Platform.pathSeparator}Info.plist',
    ).readAsStringSync();
    for (final key in [
      'NSPhotoLibraryUsageDescription',
      'NSCameraUsageDescription',
      'NSLocationWhenInUseUsageDescription',
    ]) {
      expect(plist, contains('<key>$key</key>'));
    }
  });
}
