// The whole app (core shell, router and both modules) with fake data
// instead of Supabase.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:sportshub_app/main.dart' show modules;
import 'package:sportshub_core/sportshub_core.dart';

class FakeAuth extends Fake implements AuthRepository {
  FakeAuth([this.userId]);

  @override
  final String? userId;

  @override
  bool get isLoggedIn => userId != null;

  @override
  Stream<void> get changes => const Stream.empty();
}

class FakeModules extends Fake implements ModuleRepository {
  FakeModules({required this.gymOn});
  final bool gymOn;

  @override
  Future<List<AppModuleRow>> list() async => [
        const AppModuleRow(key: 'ground_booking', name: 'Ground booking', isEnabled: true, sortOrder: 10),
        AppModuleRow(key: 'gym_membership', name: 'Gym membership', isEnabled: gymOn, sortOrder: 20),
      ];
}

class FakeProfiles extends Fake implements ProfileRepository {
  @override
  Future<Profile?> get(String userId) async =>
      Profile(id: userId, fullName: 'Pema Wangmo', role: PlatformRole.user, memberCode: '4K7P9Q');
}

class FakeVenues extends Fake implements VenueRepository {
  @override
  Future<List<MyVenue>> myVenues(String userId) async => const [];

  @override
  Future<List<Venue>> listPublic({required String type, String? dzongkhag}) async => [
        Venue.fromJson({
          'id': 'g1',
          'type': 'gym',
          'name': 'Peak Fitness',
          'dzongkhag': 'Thimphu',
          'verification_status': 'verified',
          'created_at': '2026-11-07T10:00:00Z',
        }),
      ];
}

class FakeGym extends Fake implements GymRepository {
  @override
  Future<List<GymSubscription>> mySubscriptions(String userId) async => const [];
}

class FakeNotifications extends Fake implements NotificationRepository {
  @override
  Stream<List<AppNotification>> watch(String userId) => Stream.value(const []);
}

Future<ProviderContainer> pumpApp(WidgetTester tester, {String? userId, bool gymOn = true}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    registeredModulesProvider.overrideWithValue(modules),
    authRepositoryProvider.overrideWithValue(FakeAuth(userId)),
    moduleRepositoryProvider.overrideWithValue(FakeModules(gymOn: gymOn)),
    profileRepositoryProvider.overrideWithValue(FakeProfiles()),
    venueRepositoryProvider.overrideWithValue(FakeVenues()),
    gymRepositoryProvider.overrideWithValue(FakeGym()),
    notificationRepositoryProvider.overrideWithValue(FakeNotifications()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SportsHubApp()));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets("visitors land on Welcome, with each module's public pages", (tester) async {
    await pumpApp(tester);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Book a ground'), findsOneWidget);
    expect(find.text('Tournaments'), findsOneWidget);
    expect(find.text('Find a gym'), findsOneWidget);
    expect(find.text('My gym'), findsNothing, reason: 'it needs an account');
  });

  testWidgets('a module that is turned off is hidden', (tester) async {
    await pumpApp(tester, gymOn: false);
    expect(find.text('Book a ground'), findsOneWidget);
    expect(find.text('Find a gym'), findsNothing);
  });

  testWidgets('visitors browse gyms, but sign in for My gym', (tester) async {
    final container = await pumpApp(tester);
    await tester.tap(find.text('Find a gym'));
    await tester.pumpAndSettle();
    expect(find.text('Peak Fitness'), findsOneWidget);

    container.read(appRouterProvider).go(GymRoutes.myGym);
    await tester.pumpAndSettle();
    expect(find.text('Email me a code instead'), findsOneWidget, reason: 'the sign-in page');
  });

  testWidgets('signed in: home has a section for each module', (tester) async {
    await pumpApp(tester, userId: 'u1');
    expect(find.text('Hello, Pema'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Ground booking'), findsOneWidget);
    expect(find.text('Book a ground'), findsOneWidget);
    expect(find.text('Register your venue'), findsOneWidget);
  });

  testWidgets('pages of a module that is off send users home', (tester) async {
    final container = await pumpApp(tester, userId: 'u1', gymOn: false);
    container.read(appRouterProvider).go(GymRoutes.gyms);
    await tester.pumpAndSettle();
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, CoreRoutes.home);
  });

  test('main.dart registers both modules', () {
    expect(modules.map((m) => m.key), ['ground_booking', 'gym_membership']);
  });
}
