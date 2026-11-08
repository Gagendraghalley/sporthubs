// The whole app (core shell, router and the gym module) with fake data
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

class FakeGym extends Fake implements GymRepository {}

class FakeNotifications extends Fake implements NotificationRepository {
  @override
  Stream<List<AppNotification>> watch(String userId) => Stream.value(const []);
}

/// A signed-in member: no SportsHub team roles.
class FakeAccess extends Fake implements AccessRepository {
  @override
  Future<PlatformAccess> myAccess() async => const PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {});
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
    accessRepositoryProvider.overrideWithValue(FakeAccess()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SportsHubApp()));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('visitors land on the public Welcome page', (tester) async {
    final container = await pumpApp(tester);
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, CoreRoutes.welcome);
    expect(find.text('Find a gym'), findsWidgets);
  });

  testWidgets("visitors browse the gyms' public pages", (tester) async {
    final container = await pumpApp(tester);
    container.read(appRouterProvider).go(GymRoutes.gyms);
    await tester.pumpAndSettle();
    expect(find.text('Peak Fitness'), findsOneWidget);
  });

  testWidgets("a gym's staff pages need signing in", (tester) async {
    final container = await pumpApp(tester);
    container.read(appRouterProvider).go(GymRoutes.membersFor('g1'));
    await tester.pumpAndSettle();
    expect(find.text('Email me a code instead'), findsOneWidget, reason: 'the sign-in page');
  });

  testWidgets('signing in and signing up have a way back to the Welcome page', (tester) async {
    final container = await pumpApp(tester);
    final router = container.read(appRouterProvider);
    for (final page in [CoreRoutes.signIn, CoreRoutes.signUp]) {
      router.go(page);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to home'));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, CoreRoutes.welcome, reason: page);
    }
  });

  testWidgets('signed in, running no gym yet: Overview shows how to start', (tester) async {
    await pumpApp(tester, userId: 'u1');
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Gym management'), findsWidgets, reason: 'the service, in the menu and on Overview');
    expect(find.text('Set up your gym'), findsWidgets);
    expect(find.textContaining('Work at a gym?'), findsOneWidget);
  });

  testWidgets('pages of a module that is off send users home', (tester) async {
    final container = await pumpApp(tester, userId: 'u1', gymOn: false);
    container.read(appRouterProvider).go(GymRoutes.gyms);
    await tester.pumpAndSettle();
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, CoreRoutes.home);
  });

  test('main.dart registers the gym module (others come back as their own modules)', () {
    expect(modules.map((m) => m.key), ['gym_membership']);
  });
}
