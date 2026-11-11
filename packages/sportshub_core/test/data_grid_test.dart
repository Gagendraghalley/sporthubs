import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';

void main() {
  // Names out of order, and more of them than one page holds.
  final names = [for (var i = 0; i < 23; i++) 'Person ${String.fromCharCode(0x41 + (i * 7) % 23)}'];

  Future<void> show(WidgetTester tester, {double width = 1200, ValueChanged<String>? onTap}) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DataGrid<String>(
            rows: names,
            noun: 'people',
            onRowTap: onTap,
            columns: [
              GridColumn(key: 'name', label: 'Name', flex: 3, sortBy: (n) => n, cell: (_, n) => Text(n)),
              GridColumn(key: 'wide', label: 'Only wide', showFrom: 900, cell: (_, n) => const Text('wide cell')),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  List<String> shownNames(WidgetTester tester) =>
      [for (final t in tester.widgetList<Text>(find.textContaining('Person '))) t.data!];

  testWidgets('a page at a time, with its range at the foot', (tester) async {
    await show(tester);
    expect(find.text('1–10 of 23'), findsOneWidget);
    expect(shownNames(tester), names.take(10).toList());

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('11–20 of 23'), findsOneWidget);
    expect(shownNames(tester), names.skip(10).take(10).toList());

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('21–23 of 23'), findsOneWidget);
  });

  testWidgets('a header sorts up, then down, then back as it came', (tester) async {
    await show(tester);
    final sorted = [...names]..sort();

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), sorted.take(10).toList());

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), sorted.reversed.take(10).toList());

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), names.take(10).toList());
  });

  testWidgets('a row opens on a tap', (tester) async {
    String? opened;
    await show(tester, onTap: (n) => opened = n);
    await tester.tap(find.text(names[2]));
    expect(opened, names[2]);
  });

  testWidgets('columns step aside on a narrow screen', (tester) async {
    await show(tester);
    expect(find.text('Only wide'), findsOneWidget);
    await show(tester, width: 600);
    expect(find.text('Only wide'), findsNothing);
    expect(find.text('wide cell'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
