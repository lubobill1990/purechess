import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/engine/stockfish_service.dart';
import 'package:purechess/features/settings/ai_status_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_stockfish_transport.dart';

void main() {
  late Directory dir;
  late Analytics analytics;
  late SharedPreferences prefs;
  late FakeStockfishTransport transport;
  late StockfishService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('chess_ai_widget_');
    analytics = Analytics.testing(directory: dir);
    await analytics.init(prefs);
    transport = FakeStockfishTransport();
    service = StockfishService(
      transportFactory: () => transport,
      analytics: analytics,
      prefs: prefs,
    );
  });
  tearDown(() async {
    await service.dispose();
    analytics.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AiStatusTile(
          analytics: analytics,
          prefs: prefs,
          service: service,
        ),
      ),
    ),
  );

  Future<void> check(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('检查 AI'));
      // Analytics persists the phase/crash streak through platform storage.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('check AI performs real service flow and shows ready', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('AI 尚未启动'), findsOneWidget);
    await check(tester);
    expect(find.text('AI 已就绪'), findsOneWidget);
    expect(transport.commands.last, 'go movetime 100');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'startup failure is visible, technical cause hidden, retry works',
    (tester) async {
      transport.launchError = StateError('Stockfish DLL path secret');
      await mount(tester);
      await check(tester);
      expect(find.text('AI 启动失败，请重试'), findsOneWidget);
      expect(find.textContaining('Stockfish'), findsNothing);
      transport = FakeStockfishTransport();
      await check(tester);
      expect(find.text('AI 已就绪'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('unexpected idle exit updates UI without another button press', (
    tester,
  ) async {
    await mount(tester);
    await check(tester);
    transport.output.close();
    await tester.pumpAndSettle();
    expect(find.text('AI 意外退出，请重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
