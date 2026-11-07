import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/home/gym_home_page.dart';
import 'package:sportshub_core/sportshub_core.dart';

enum Who { activeOwnerAdmin, newMember, waiting }

/// A signed-in person's records, as the database would give them.
List<Override> person(Who who) {
  final today = BhutanTime.today();
  DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);
  final gym = Venue.fromJson({
    'id': 'g1',
    'type': gymVenueType,
    'name': 'Druk Fitness Club',
    'dzongkhag': 'Thimphu',
    'town': 'Changzamtog',
    'verification_status': 'pending',
    'created_at': '2026-11-01T00:00:00Z',
  });
  GymSubscription sub(String status, {int? from, int? to}) => GymSubscription(
        id: 's-$status',
        venueId: 'g1',
        memberId: 'u1',
        planName: 'Monthly',
        durationDays: 30,
        price: 1500,
        status: status,
        startDate: from == null ? null : day(from),
        endDate: to == null ? null : day(to),
        requestedAt: DateTime.utc(2026, 10, 1),
        gymName: 'Druk Fitness Club',
      );
  final subs = switch (who) {
    Who.activeOwnerAdmin => [sub(SubscriptionStatus.active, from: -24, to: 5)],
    Who.newMember => <GymSubscription>[],
    Who.waiting => [sub(SubscriptionStatus.pending)],
  };
  final checkIns = who == Who.activeOwnerAdmin
      ? [
          for (var i = 0; i < 6; i++)
            GymCheckIn(
              id: 'c$i',
              venueId: 'g1',
              memberId: 'u1',
              gymName: 'Druk Fitness Club',
              checkedInAt: DateTime.now().toUtc().subtract(Duration(days: i, hours: 2)),
            ),
        ]
      : <GymCheckIn>[];
  return [
    currentUserIdProvider.overrideWithValue('00000000-0000-4000-8000-000000000001'),
    myProfileProvider.overrideWith((ref) async => Profile.fromJson({
          'id': 'u1',
          'full_name': 'Gagendra Ghalley',
          'member_code': '4K7P9Q',
          'role': who == Who.activeOwnerAdmin ? 'admin' : 'user',
        })),
    mySubscriptionsProvider.overrideWith((ref) async => subs),
    myCheckInsProvider.overrideWith((ref) async => checkIns),
    myVenuesProvider.overrideWith((ref) async => who == Who.activeOwnerAdmin ? [MyVenue(gym, VenueRole.owner)] : const []),
    enabledModulesProvider.overrideWith((ref) async => const [GymModule()]),
    unreadCountProvider.overrideWithValue(2),
  ];
}

Future<void> showHome(WidgetTester tester, Who who, Size size, {bool dark = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: person(who),
    child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: const GymHomePage()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const computer = Size(1440, 1000);
  const phone = Size(390, 844);
  // Each of the page's layouts: the side menu; the wide top without it; the
  // cards two by two; one column.
  const sizes = {'computer': computer, 'laptop': Size(1024, 768), 'tablet': Size(820, 1180), 'phone': phone};

  for (final who in Who.values) {
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      for (final dark in [false, true]) {
        testWidgets('home fits a $name for ${who.name}, ${dark ? 'dark' : 'light'}', (tester) async {
          await showHome(tester, who, size, dark: dark);
          expect(tester.takeException(), isNull);
          expect(find.textContaining('Good '), findsOneWidget);
          expect(find.textContaining('Gagendra!'), findsOneWidget);
        });
      }
    }
  }

  testWidgets('a member with a plan sees days left, visits, the pass, their gym and admin', (tester) async {
    await showHome(tester, Who.activeOwnerAdmin, computer);
    expect(find.textContaining('6 days left'), findsOneWidget);
    expect(find.text('Ends soon: renew at the desk'), findsOneWidget);
    // Six visits on six days running, all in the last week.
    expect(find.text('6 visits'), findsOneWidget);
    expect(find.text('6 days in a row'), findsOneWidget);
    expect(find.text('6 of 7 days'), findsOneWidget);
    expect(find.text('2 unread'), findsOneWidget);
    expect(find.text('Member pass'), findsOneWidget);
    expect(find.text('4K7P9Q'), findsOneWidget);
    expect(find.text('Checked in at Druk Fitness Club'), findsWidgets);
    expect(find.text('Your gyms'), findsOneWidget);
    expect(find.text('Being checked'), findsOneWidget);
    expect(find.text('Gym owner'), findsOneWidget);
    // In the side menu, and the card at the foot.
    expect(find.text('SportsHub admin'), findsNWidgets(2));
  });

  testWidgets('someone new is shown how to start, the sports to come, and asked if they run a gym', (tester) async {
    await showHome(tester, Who.newMember, computer);
    expect(find.text('No membership yet'), findsOneWidget);
    expect(find.text('No plan yet'), findsOneWidget);
    expect(find.text('Member pass'), findsNothing);
    expect(find.textContaining('fitness goals'), findsOneWidget);
    expect(find.text('Explore SportsHub'), findsOneWidget);
    expect(find.text('Coming soon'), findsNWidgets(2));
    expect(find.text('Put your gym on SportsHub'), findsOneWidget);
    expect(find.text('No check-ins in the last 7 days'), findsOneWidget);
    expect(find.text('SportsHub admin'), findsNothing);
  });

  testWidgets('a request waiting says what to pay', (tester) async {
    await showHome(tester, Who.waiting, computer);
    expect(find.textContaining('to confirm your payment of Nu. 1,500'), findsOneWidget);
    expect(find.text('Waiting for Druk Fitness Club'), findsOneWidget);
    expect(find.textContaining('Pay Nu. 1,500 at Druk Fitness Club'), findsOneWidget);
  });

  testWidgets('the training chart switches between 7, 30 and 90 days', (tester) async {
    await showHome(tester, Who.activeOwnerAdmin, computer);
    expect(find.text('Check-ins, last 7 days'), findsOneWidget);
    await tester.tap(find.text('30D'));
    await tester.pumpAndSettle();
    expect(find.text('Check-ins, last 30 days'), findsOneWidget);
    await tester.tap(find.text('90D'));
    await tester.pumpAndSettle();
    expect(find.text('Check-ins, last 90 days'), findsOneWidget);
  });

  testWidgets('the side menu shows on a computer, and in a drawer on a phone', (tester) async {
    await showHome(tester, Who.activeOwnerAdmin, computer);
    expect(find.text('Register a gym'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);

    await showHome(tester, Who.activeOwnerAdmin, phone);
    expect(find.text('Register a gym'), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Register a gym'), findsOneWidget);
    expect(find.text('Stronger together'), findsOneWidget);
  });
}
