import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/src/welcome/gym_welcome_page.dart';
import 'package:sportshub_core/sportshub_core.dart';

void main() {
  Future<void> show(WidgetTester tester, Size size, {bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: const GymWelcomePage())),
    );
  }

  const sizes = {'phone': Size(390, 844), 'tablet': Size(820, 1180), 'computer': Size(1440, 900)};

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    for (final dark in [false, true]) {
      testWidgets('Welcome fits a $name, ${dark ? 'dark' : 'light'}', (tester) async {
        await show(tester, size, dark: dark);
        // The whole page is laid out (it scrolls as one), so an overflow
        // anywhere on it fails here.
        expect(tester.takeException(), isNull);
        expect(find.text('Choose Your\nPerfect Plan'), findsOneWidget);
        expect(find.text('Have Questions?'), findsOneWidget);
      });
    }
  }

  testWidgets('a question opens to its answer', (tester) async {
    await show(tester, sizes['computer']!);
    const question = 'What payment methods are accepted?';
    // Scrolled to, the questions rise into place; then they're where a
    // second look finds them.
    await tester.ensureVisible(find.text(question));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(question));
    await tester.pumpAndSettle();
    expect(find.textContaining('cash, mBoB or bank transfer'), findsNothing);
    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(find.textContaining('cash, mBoB or bank transfer'), findsOneWidget);
  });

  testWidgets('the answers follow how gyms work today: the front desk registers members', (tester) async {
    await show(tester, sizes['computer']!);
    const question = 'How do I join a gym?';
    await tester.ensureVisible(find.text(question));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(question));
    await tester.pumpAndSettle();
    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(find.textContaining('the front desk registers you'), findsOneWidget);
    for (final old in ['ask to join', 'Open My gym', 'the day after the current one ends', 'cancel a request']) {
      expect(find.textContaining(old), findsNothing, reason: old);
    }
  });

  testWidgets('it claims no member counts, ratings or prices', (tester) async {
    await show(tester, sizes['computer']!);
    for (final madeUp in ['10K+', '10,000', '4.8', 'Nu ', 'Rated']) {
      expect(find.textContaining(madeUp), findsNothing, reason: madeUp);
    }
  });
}
