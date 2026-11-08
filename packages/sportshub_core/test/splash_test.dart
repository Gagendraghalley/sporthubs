import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';

/// The image the logo (or the splash) asked for.
String shownImage(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image)).image;
  return (image as AssetImage).assetName;
}

void main() {
  group('the logo', () {
    testWidgets('navy lettering in light, white lettering in dark, no tile', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const SportsHubLogo()));
      expect(shownImage(tester), endsWith('/sportshub_logo.png'));

      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const SportsHubLogo(markOnly: true)));
      await tester.pumpAndSettle(); // the theme fades from light to dark
      expect(shownImage(tester), endsWith('/sportshub_mark_on_dark.png'));
      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('places that are navy in both themes ask for the white one', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const SportsHubLogo(onDark: true)));
      expect(shownImage(tester), endsWith('/sportshub_logo_on_dark.png'));
    });

    test('every version it can ask for is in the package', () {
      for (final markOnly in [false, true]) {
        for (final onDark in [false, true]) {
          final path = SportsHubLogo.assetFor(markOnly: markOnly, onDark: onDark);
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
    });
  });

  group('the splash', () {
    Future<void> showSplash(WidgetTester tester, Size screen, {ThemeData? theme}) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: theme, home: const SportsHubSplash()));
    }

    testWidgets('the logo is dead centre, 240 wide on a phone, as the launch screens draw it', (tester) async {
      await showSplash(tester, const Size(390, 844));
      final logo = tester.getRect(find.byType(Image));
      expect(logo.center, const Offset(195, 422));
      expect(logo.width, 240);
      expect(logo.height, closeTo(240 * 482 / 900, 0.01));
    });

    testWidgets('320 wide on a computer', (tester) async {
      await showSplash(tester, const Size(1440, 900));
      final logo = tester.getRect(find.byType(Image));
      expect(logo.center, const Offset(720, 450));
      expect(logo.width, 320);
    });

    testWidgets('white lettering on navy, in the light theme too, and it says it is loading', (tester) async {
      final semantics = tester.ensureSemantics();
      await showSplash(tester, const Size(390, 844), theme: AppTheme.light);
      expect(shownImage(tester), endsWith('/sportshub_logo_on_dark.png'));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      // The bar sits under the logo.
      final logo = tester.getRect(find.byType(Image));
      final bar = tester.getRect(find.bySemanticsLabel('Loading'));
      expect(bar.top, logo.bottom + SportsHubSplash.barGap);
      expect(bar.center.dx, logo.center.dx);
      semantics.dispose();
    });
  });

  testWidgets('the gate shows the splash until ready, then fades to the page', (tester) async {
    Widget gate(bool ready) => MaterialApp(home: SplashGate(ready: ready, builder: (_) => const Text('the page')));
    await tester.pumpWidget(gate(false));
    expect(find.byType(SportsHubSplash), findsOneWidget);
    expect(find.text('the page'), findsNothing);

    await tester.pumpWidget(gate(true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(SportsHubSplash), findsOneWidget, reason: 'still fading out');
    expect(find.text('the page'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(SportsHubSplash), findsNothing);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('signed in, the frame shows the splash while the modules load', (tester) async {
    final modules = Completer<List<SportsHubModule>>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u1'),
        enabledModulesProvider.overrideWith((ref) => modules.future),
      ],
      child: const MaterialApp(home: AppShell(location: '/home', child: Text('the page'))),
    ));
    expect(find.byType(SportsHubSplash), findsOneWidget);
    expect(find.text('the page'), findsNothing);

    modules.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(SportsHubSplash), findsNothing);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('the loader spins, and says what it is waiting for', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Center(child: SportsHubLoader(size: 56, semanticsLabel: 'Loading gyms')),
      ));
      expect(tester.getSize(find.byType(SportsHubLoader)), const Size(56, 56));
      expect(find.bySemanticsLabel('Loading gyms'), findsOneWidget);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tester.binding.hasScheduledFrame, isTrue);
    }
    // Small: the orange arc alone.
    await tester.pumpWidget(const MaterialApp(home: Center(child: SportsHubLoader(size: 20))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets("pages waiting on data show the shape of what's coming, shimmering", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AsyncValueView<int>(value: const AsyncLoading(), data: (n) => Text('$n')),
    ));
    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('a skeleton fits a small box and a list alike', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(children: [SizedBox(height: 60, child: LoadingSkeleton()), LoadingSkeleton.rows()]),
    ));
    expect(tester.takeException(), isNull);
  });
}
