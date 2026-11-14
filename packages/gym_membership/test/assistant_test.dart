import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/ask_data.dart';
import 'package:sportshub_core/sportshub_core.dart';

// The floating Ask AI button: a gym's own Ask AI on its staff pages,
// SportsHub's assistant everywhere else, for visitors too.

const gymId = '0f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5b';

Venue venue(String id, String name, {String dzongkhag = 'Thimphu'}) => Venue.fromJson({
      'id': id,
      'type': 'gym',
      'name': name,
      'dzongkhag': dzongkhag,
      'verification_status': 'verified',
      'created_at': '2026-11-01T00:00:00Z',
    });

class FakePublic extends Fake implements PublicAssistantRepository {
  final asked = <String>[];

  @override
  Future<({PublicReply reply, int? left})> ask(String question, List<({String question, PublicReply reply})> history) async {
    asked.add(question);
    return (
      reply: PublicReply.fromJson({'kind': 'help', 'answer': 'Go to the gym: the front desk registers you.', 'page': 'gyms'}),
      left: 14,
    );
  }
}

/// The app's frame at [at], as [userId] (null: a visitor), with a stand-in
/// for each page.
Future<GoRouter> showApp(WidgetTester tester, {String? userId, String at = '/gyms/$gymId/manage', Size size = const Size(1440, 1000), FakePublic? ai}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget page(String name) => AppPage(title: name, body: Center(child: Text('Page: $name')));
  final router = GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          for (final (path, name) in [
            (GymRoutes.gyms, 'Gyms'),
            (GymRoutes.gym, 'A gym'),
            (GymRoutes.dashboard, 'Dashboard'),
            (GymRoutes.registerMember, 'Register member'),
            (GymRoutes.ask, 'Ask AI page'),
          ])
            GoRoute(path: path, builder: (_, __) => page(name)),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  final gym = venue(gymId, 'Druk Fitness Club');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue(userId),
      myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'u1', 'full_name': 'Pema Owner'})),
      myAccessProvider.overrideWith((ref) async => PlatformAccess(isSuperAdmin: false, isActive: true, permissions: const {})),
      myVenuesProvider.overrideWith((ref) async => userId == null ? const <MyVenue>[] : [MyVenue(gym, VenueRole.owner)]),
      enabledModulesProvider.overrideWith((ref) async => const [GymModule()]),
      pendingVenuesProvider.overrideWith((ref) async => const []),
      unreadCountProvider.overrideWithValue(0),
      publicVenuesProvider.overrideWith((ref, q) async => [
            for (final v in [venue('g-a', 'Peak Fitness'), venue('g-b', 'Paro Power Gym', dzongkhag: 'Paro')])
              if (q.dzongkhag == null || v.dzongkhag == q.dzongkhag) v,
          ]),
      if (ai != null) publicAssistantRepositoryProvider.overrideWithValue(ai),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

Future<void> openAssistant(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ask AI'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("on a gym's pages it opens that gym's Ask AI, not a menu entry", (tester) async {
    final router = await showApp(tester, userId: 'u1');
    expect(find.text('Ask AI'), findsOneWidget, reason: 'the button, labelled, on a computer');
    expect(find.descendant(of: find.byType(PlatformSidebar), matching: find.text('Ask AI')), findsNothing);

    await openAssistant(tester);
    expect(find.text('Ask about Druk Fitness Club'), findsOneWidget);
    expect(find.text("Druk Fitness Club · your gym's records"), findsOneWidget);
    expect(find.text('Busiest hours this month'), findsOneWidget);

    // Open full size: the panel closes and the page opens.
    await tester.tap(find.byTooltip('Open full size'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, GymRoutes.askFor(gymId));
    expect(find.text('Ask about Druk Fitness Club'), findsNothing);
    expect(find.byTooltip('Ask AI'), findsNothing, reason: 'not over Ask AI itself');
  });

  testWidgets('it stays out of the way of the register form\'s Save bar', (tester) async {
    await showApp(tester, userId: 'u1', at: GymRoutes.registerMemberFor(gymId));
    expect(find.byTooltip('Ask AI'), findsNothing);
  });

  testWidgets('visitors get SportsHub\'s assistant: suggestions, gyms near them, and questions', (tester) async {
    final ai = FakePublic();
    final router = await showApp(tester, at: GymRoutes.gyms, ai: ai);
    await openAssistant(tester);
    expect(find.text('SportsHub assistant'), findsOneWidget);
    expect(find.text('Hi! Ask me about SportsHub'), findsOneWidget);

    await tester.tap(find.text('What is SportsHub?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('brings gyms, grounds and games across Bhutan'), findsOneWidget);
    expect(ai.asked, isEmpty, reason: 'a suggestion is answered here');

    await tester.enterText(find.byType(TextField), 'How do I become a member?');
    await tester.tap(find.byTooltip('Ask'));
    await tester.pumpAndSettle();
    expect(ai.asked, ['How do I become a member?']);
    expect(find.text('Go to the gym: the front desk registers you.'), findsOneWidget);
    expect(find.text("Written by AI from SportsHub's guide."), findsOneWidget);
    expect(find.textContaining('14 questions left today'), findsOneWidget);

    // Gyms in Thimphu: from SportsHub's own list, and a tap opens one. The
    // suggestions are now in a row over the box that scrolls sideways.
    final chips = find
        .descendant(
            of: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Gyms in Thimphu'), 120, scrollable: chips);
    await tester.ensureVisible(find.text('Gyms in Thimphu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gyms in Thimphu'));
    await tester.pumpAndSettle();
    expect(find.text('1 gym in Thimphu.'), findsOneWidget);
    await tester.tap(find.text('Peak Fitness'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, GymRoutes.gymFor('g-a'));
    expect(find.text('SportsHub assistant'), findsNothing, reason: 'the panel closed');
  });

  testWidgets('it remembers the conversation, and fills the screen on a phone', (tester) async {
    await showApp(tester, at: GymRoutes.gyms, size: const Size(390, 844));
    expect(find.text('Ask AI'), findsNothing, reason: 'just its icon on a phone');
    await openAssistant(tester);
    await tester.tap(find.text('How do I check in?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Show your QR card at the counter'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Show your QR card at the counter'), findsNothing);

    await openAssistant(tester);
    expect(find.textContaining('Show your QR card at the counter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the gym module points the assistant at its pages', () {
    const module = GymModule();
    expect(module.assistantLinks['gyms']?.route, GymRoutes.gyms);
    expect(module.publicVenueRoute(venue('g-a', 'Peak Fitness')), GymRoutes.gymFor('g-a'));
    expect(module.hidesAssistantButton(GymRoutes.askFor(gymId)), isTrue);
    expect(module.hidesAssistantButton(GymRoutes.editMemberFor(gymId, 'm1')), isTrue);
    expect(module.hidesAssistantButton(GymRoutes.membersFor(gymId)), isFalse);
    expect(askChatProvider, isNotNull);
  });
}
