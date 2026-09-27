import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/preferences_store.dart';

void main() {
  late Directory dir;
  late SharedPreferences prefs;
  late Analytics analytics;
  late FailingPreferencesStore store;

  setUp(() async {
    store = FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    prefs = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('purechess_privacy_test_');
    analytics = Analytics.testing(directory: dir);
    await analytics.init(prefs);
  });

  tearDown(() async {
    analytics.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(MyApp(prefs: prefs, analytics: analytics));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'first launch blocks dismissal and exposes policy before choice',
    (tester) async {
      await launch(tester);
      expect(find.text('隐私告知'), findsOneWidget);
      expect(analytics.consentGranted, isFalse);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('隐私告知'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('隐私告知'), findsOneWidget);
      await tester.tap(find.text('阅读隐私政策'));
      await tester.pumpAndSettle();
      expect(find.text('纯弈国象隐私说明（占位稿）'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('隐私告知'), findsOneWidget);
    },
  );

  testWidgets('accept persists choice and opens local game from home', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('隐私告知'), findsNothing);
    expect(prefs.getBool(Analytics.privacyAcceptedKey), isTrue);
    expect(analytics.consentGranted, isTrue);
    expect(find.text('双人对弈'), findsOneWidget);
    await tester.tap(find.text('双人对弈'));
    await tester.pumpAndSettle();
    expect(find.text('面对面对弈'), findsOneWidget);
    expect(find.byKey(const ValueKey('square-e2')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('双人对弈'), findsOneWidget);
  });

  testWidgets(
    'decline keeps app usable and settings can re-enable statistics',
    (tester) async {
      await launch(tester);
      await tester.tap(find.text('关闭统计并继续'));
      await tester.pumpAndSettle();
      expect(analytics.enabled, isFalse);
      expect(
        File('${dir.path}/pending_events.jsonl').readAsStringSync(),
        isEmpty,
      );
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '匿名使用统计'),
            )
            .value,
        false,
      );
      await tester.tap(find.widgetWithText(SwitchListTile, '匿名使用统计'));
      await tester.pumpAndSettle();
      expect(analytics.enabled, isTrue);
      expect(prefs.getBool(Analytics.enabledKey), isTrue);
      await tester.tap(find.widgetWithText(SwitchListTile, '匿名使用统计'));
      await tester.pumpAndSettle();
      expect(analytics.enabled, isFalse);
      await tester.tap(find.text('隐私政策'));
      await tester.pumpAndSettle();
      expect(find.text('纯弈国象隐私说明（占位稿）'), findsOneWidget);
    },
  );

  testWidgets('saved decline skips first-launch dialog on next app mount', (
    tester,
  ) async {
    await analytics.savePrivacyChoice(false, prefs);
    await launch(tester);
    expect(find.text('隐私告知'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
  });

  testWidgets('failed privacy save keeps dialog open and allows retry', (
    tester,
  ) async {
    store.failKey = 'flutter.${Analytics.privacyAcceptedKey}';
    await launch(tester);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('隐私选择保存失败，请重试。确认前不会发送统计。'), findsOneWidget);
    expect(analytics.consentGranted, isFalse);
    expect(prefs.getBool(Analytics.privacyAcceptedKey), isNull);
    store.failKey = null;
    await tester.tap(find.text('关闭统计并继续'));
    await tester.pumpAndSettle();
    expect(find.text('隐私告知'), findsNothing);
    expect(analytics.enabled, isFalse);
  });

  testWidgets('failed settings save displays error and does not opt in', (
    tester,
  ) async {
    await analytics.savePrivacyChoice(false, prefs);
    await launch(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    store.failKey = 'flutter.${Analytics.enabledKey}';
    await tester.tap(find.widgetWithText(SwitchListTile, '匿名使用统计'));
    await tester.pumpAndSettle();
    expect(find.text('统计设置保存失败，请重试'), findsOneWidget);
    expect(analytics.enabled, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '匿名使用统计'))
          .value,
      false,
    );
  });

  testWidgets('lifecycle transitions preserve queue while consent is absent', (
    tester,
  ) async {
    await launch(tester);
    final file = File('${dir.path}/pending_events.jsonl');
    final before = file.readAsStringSync();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(file.readAsStringSync(), before);
    expect(analytics.consentGranted, isFalse);
  });
}
