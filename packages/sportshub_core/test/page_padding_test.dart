import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';

void main() {
  const first = Key('first');

  /// The first item's gap below the app bar.
  double gapBelowAppBar(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(first)).dy - tester.getBottomLeft(find.byType(AppBar)).dy;

  Widget list(BuildContext context) =>
      ListView(padding: pagePadding(context), children: const [SizedBox(key: first, height: 40)]);

  testWidgets('a screen building an AppPage starts its list below the app bar', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => AppPage(title: 'Page', body: list(context)))));
    expect(gapBelowAppBar(tester), 12);
  });

  testWidgets('a widget inside an AppPage body gets the same gap, not the app bar twice', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AppPage(title: 'Page', body: Builder(builder: list))));
    expect(gapBelowAppBar(tester), 12);
  });
}
