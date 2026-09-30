import 'package:flutter_test/flutter_test.dart';

Future<void> tapGameNavigation(WidgetTester tester, String label) async {
  final menu = find.byTooltip('对局菜单');
  if (menu.evaluate().isNotEmpty) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
  } else {
    await tester.tap(find.byTooltip(label));
  }
}
