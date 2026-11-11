import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportshub_core/sportshub_core.dart';

void main() {
  Future<ProviderContainer> show(WidgetTester tester, ThemeMode initial, {Brightness phone = Brightness.light}) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.platformBrightnessTestValue = phone;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final container = ProviderContainer(overrides: [themeModeProvider.overrideWith(() => ThemeModeController(initial))]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ref.watch(themeModeProvider),
            home: const Scaffold(body: Center(child: ThemeModeButton())),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('light goes dark, and dark goes light', (tester) async {
    final container = await show(tester, ThemeMode.light);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

    await tester.tap(find.byType(ThemeModeButton));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.tap(find.byType(ThemeModeButton));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  testWidgets('under Auto it flips what the phone shows', (tester) async {
    final container = await show(tester, ThemeMode.system, phone: Brightness.dark);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.tap(find.byType(ThemeModeButton));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  testWidgets('before they choose, it is light, even on a phone set to dark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    expect(await ThemeModeController.saved(), ThemeMode.light);
    expect(ThemeModeController().build(), ThemeMode.light);
  });

  testWidgets('the choice is kept on the device', (tester) async {
    await show(tester, ThemeMode.light);
    await tester.tap(find.byType(ThemeModeButton));
    await tester.pumpAndSettle();
    expect(await ThemeModeController.saved(), ThemeMode.dark);
  });
}
