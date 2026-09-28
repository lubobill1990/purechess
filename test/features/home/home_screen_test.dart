import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purechess/app/router.dart';
import 'package:purechess/app/telemetry/analytics.dart';
import 'package:purechess/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  var now = DateTime(2026, 9, 28, 12);

  setUp(() async {
    now = DateTime(2026, 9, 28, 12);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> launch(
    WidgetTester tester, {
    bool resume = false,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: HomeScreen(
          prefs: prefs,
          now: () => now,
          canResumeGame: resume,
          recommendedDifficulty: 3,
        ),
        routes: {
          AppRouter.tutorial: (context) => Scaffold(
            appBar: AppBar(title: const Text('教程测试页')),
            body: TextButton(
              onPressed: () async {
                await prefs.setInt('tutorial_progress', 18);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('毕业'),
            ),
          ),
          AppRouter.newGame: (context) => Scaffold(
            appBar: AppBar(title: const Text('对局测试页')),
            body: Text('${ModalRoute.of(context)!.settings.arguments}'),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tutorial main card, secondary old entries and no fabricated progress',
    (tester) async {
      await launch(tester);
      expect(find.text('继续教程第 1 关'), findsOneWidget);
      expect(find.text('还没有学习记录，从第 1 关开始。'), findsOneWidget);
      expect(find.text('每日战术题'), findsNothing);
      for (final label in ['双人对弈', '我的棋谱', '名局库']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(prefs.getKeys(), isEmpty);
    },
  );

  testWidgets('return from tutorial refreshes prefs into the three-card flow', (
    tester,
  ) async {
    await prefs.setInt('tutorial_progress', 7);
    await launch(tester);
    await tester.tap(find.text('继续教程第 8 关'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('毕业'));
    await tester.pumpAndSettle();
    expect(find.text('每日战术题'), findsOneWidget);
    expect(find.text('新对局'), findsOneWidget);
    expect(find.text('读一盘名局'), findsOneWidget);
    expect(find.text('推荐难度 3 / 10 档'), findsOneWidget);
    expect(find.textContaining('继续教程第'), findsNothing);
  });

  testWidgets(
    'resume card and recommended difficulty reach game route arguments',
    (tester) async {
      await prefs.setInt('tutorial_progress', 18);
      await launch(tester, resume: true);
      await tester.ensureVisible(find.text('继续对局'));
      await tester.tap(find.text('继续对局'));
      await tester.pumpAndSettle();
      expect(find.text('{difficulty: 3, resume: true}'), findsOneWidget);
    },
  );

  for (final resume in [false, true]) {
    testWidgets('AI entry can start a fresh game with resume=$resume', (
      tester,
    ) async {
      await launch(tester, resume: resume);
      await tester.tap(find.text('人机对弈'));
      await tester.pumpAndSettle();
      expect(find.text('对局测试页'), findsOneWidget);
      expect(find.text('null'), findsOneWidget);
    });
  }

  testWidgets(
    'game return reloads the committed difficulty preference contract',
    (tester) async {
      await prefs.setInt('tutorial_progress', 18);
      await prefs.setInt('chess.ai.recommendedLevel', 6);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(prefs: prefs),
          routes: {
            AppRouter.newGame: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await prefs.setInt('chess.ai.recommendedLevel', 7);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('结束对局'),
              ),
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('推荐难度 6 / 10 档'), findsOneWidget);
      await tester.ensureVisible(find.text('新对局'));
      await tester.tap(find.text('新对局'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('结束对局'));
      await tester.pumpAndSettle();
      expect(find.text('推荐难度 7 / 10 档'), findsOneWidget);
    },
  );

  for (final invalid in <Object>[11, 'bad']) {
    testWidgets(
      'invalid recommendation is visibly downgraded, never rewritten: $invalid',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'tutorial_progress': 18,
          'chess.ai.recommendedLevel': invalid,
        });
        final store = await SharedPreferences.getInstance();
        await tester.pumpWidget(MaterialApp(home: HomeScreen(prefs: store)));
        await tester.pumpAndSettle();
        expect(find.text('推荐难度 1 / 10 档'), findsOneWidget);
        expect(find.text('推荐难度无法识别，暂用入门第 1 档。'), findsOneWidget);
        expect(store.get('chess.ai.recommendedLevel'), invalid);
      },
    );
  }

  testWidgets(
    'read progress is reflected without taking ownership of learning prefs',
    (tester) async {
      await prefs.setInt('tutorial_progress', 18);
      await prefs.setString('library_reading', '{"id":"opera-1858","ply":12}');
      await launch(tester);
      expect(find.text('继续看的名局'), findsOneWidget);
      expect(find.text('已读 12 半回合 · 回到上次的位置'), findsOneWidget);
    },
  );

  testWidgets('midnight switches the daily date without restarting home', (
    tester,
  ) async {
    now = DateTime(2026, 9, 28, 23, 59, 59);
    await prefs.setInt('tutorial_progress', 18);
    await prefs.setInt('daily_20260928', 10);
    await launch(tester);
    expect(find.text('今日 10 / 10 题'), findsOneWidget);
    now = DateTime(2026, 9, 29);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('今日还没有练习记录。'), findsOneWidget);
  });

  testWidgets('tutorial entry navigates to the real tutorial screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: AppRouter.routes(prefs: prefs, analytics: Analytics.instance),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续教程第 1 关'));
    await tester.pumpAndSettle();
    expect(find.text('新手互动教程'), findsOneWidget);
  });

  testWidgets('router accepts independently supplied feature builders', (
    tester,
  ) async {
    await prefs.setInt('tutorial_progress', 18);
    await tester.pumpWidget(
      MaterialApp(
        routes: AppRouter.routes(
          prefs: prefs,
          analytics: Analytics.instance,
          dailyBuilder: (_) => const Scaffold(body: Text('已接入每日题')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('每日战术题'));
    await tester.pumpAndSettle();
    expect(find.text('已接入每日题'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(844, 390),
      const Size(1024, 1366),
    ]) {
      testWidgets('home layout $brightness $size with enlarged text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.binding.platformDispatcher.platformBrightnessTestValue =
            brightness;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();
        });
        await prefs.setInt('tutorial_progress', 18);
        await launch(tester, scale: 2);
        expect(tester.takeException(), isNull);
        final scaffold = tester.element(find.byType(Scaffold));
        expect(Theme.of(scaffold).brightness, brightness);
        await tester.ensureVisible(find.text('名局库'));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
