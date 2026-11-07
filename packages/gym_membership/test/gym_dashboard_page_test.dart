import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/dashboard/gym_dashboard_page.dart';
import 'package:gym_membership/src/widgets/console_kit.dart';
import 'package:sportshub_core/sportshub_core.dart';

/// A gym with a few members, a week of check-ins and payments, as the
/// database would give them: no Supabase needed.
List<Override> sampleGym({required String role}) {
  final today = BhutanTime.today();
  DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);
  final venue = Venue.fromJson({
    'id': 'g1',
    'type': gymVenueType,
    'name': 'Druk Fitness Club',
    'dzongkhag': 'Thimphu',
    'verification_status': 'verified',
    'created_at': '2026-11-01T00:00:00Z',
  });
  GymSubscription sub(String id, String name, String status, int? from, int? to, {int activatedDaysAgo = 3}) =>
      GymSubscription(
        id: id,
        venueId: 'g1',
        memberId: name,
        memberName: name,
        planName: 'Monthly',
        durationDays: 30,
        price: 1500,
        status: status,
        startDate: from == null ? null : day(from),
        endDate: to == null ? null : day(to),
        requestedAt: DateTime.now().toUtc().subtract(Duration(days: activatedDaysAgo + 1)),
        activatedAt: status == SubscriptionStatus.pending ? null : DateTime.now().toUtc().subtract(Duration(days: activatedDaysAgo)),
      );
  final subs = [
    sub('s1', 'Tshering Wangchuk', SubscriptionStatus.active, -10, 19),
    sub('s2', 'Pema Dema', SubscriptionStatus.active, -27, 2),
    sub('s3', 'Karma Lhamo', SubscriptionStatus.expired, -60, -31, activatedDaysAgo: 60),
    sub('s4', 'Sonam Choden', SubscriptionStatus.pending, null, null, activatedDaysAgo: 0),
  ];
  final checkIns = [
    for (var i = 0; i < 5; i++)
      GymCheckIn(
        id: 'c$i',
        venueId: 'g1',
        memberId: 'Tshering Wangchuk',
        memberName: 'Tshering Wangchuk',
        checkedInAt: DateTime.now().toUtc().subtract(Duration(hours: 3 + 20 * i)),
      ),
  ];
  final payments = [
    for (var i = 0; i < 7; i++)
      Payment.fromJson({
        'id': 'p$i',
        'venue_id': 'g1',
        'module_key': gymModuleKey,
        'reference_id': 's${i % 2 + 1}',
        'amount': 1500 * (i % 3 + 1),
        'method': i.isEven ? 'mbob' : 'cash',
        'status': 'completed',
        'created_at': bhutanMidnightUtc(day(-i)).add(const Duration(hours: 4)).toIso8601String(),
      }),
  ];
  final manages = VenueRole.canManage(role);
  return [
    venueAccessProvider.overrideWith((ref, id) async => VenueAccess(venue, role)),
    myVenuesProvider.overrideWith((ref) async => [MyVenue(venue, role)]),
    myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'u1', 'full_name': 'Kinley Dorji'})),
    gymSubscriptionsProvider.overrideWith((ref, id) async => subs),
    gymDashboardProvider.overrideWith((ref, id) async => GymDashboard(
          pending: 1,
          active: 2,
          expiringSoon: 1,
          checkInsToday: 4,
          incomeThisMonth: manages ? 13500 : null,
        )),
    gymRecentCheckInsProvider.overrideWith((ref, id) async => checkIns),
    venuePaymentsProvider.overrideWith((ref, q) async => payments),
    unreadCountProvider.overrideWithValue(0),
  ];
}

Future<void> showDashboard(WidgetTester tester, Size size, {String role = VenueRole.owner, bool dark = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: sampleGym(role: role),
    child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: const GymDashboardPage(venueId: 'g1')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const computer = Size(1440, 1000);
  const tablet = Size(820, 1180);
  const phone = Size(390, 844);

  for (final (name, size) in [('computer', computer), ('tablet', tablet), ('phone', phone)]) {
    for (final dark in [false, true]) {
      testWidgets("an owner's dashboard fits a $name, ${dark ? 'dark' : 'light'}", (tester) async {
        await showDashboard(tester, size, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Kinley'), findsWidgets);
        expect(find.text('Total members'), findsOneWidget);
        expect(find.text('Revenue overview'), findsOneWidget);
        expect(find.text('Income this month'), findsOneWidget);
      });
    }
  }

  testWidgets('the numbers come from the records', (tester) async {
    await showDashboard(tester, computer);
    // 3 people have had a membership (one expired); 1 more only asked.
    expect(find.text('3'), findsWidgets);
    expect(find.text('2 active now'), findsOneWidget);
    expect(find.text('Nu. 13,500'), findsOneWidget);
    // Pema's plan ends in 3 days.
    expect(find.textContaining('Pema'), findsWidgets);
    expect(find.text('3 days left'), findsOneWidget);
    expect(find.text('1 waiting for payment'), findsOneWidget);
  });

  testWidgets('the side menu shows in a wide window, a drawer on a phone', (tester) async {
    await showDashboard(tester, computer);
    expect(find.text('Plans & prices'), findsWidgets);
    expect(find.byTooltip('Menu'), findsNothing);

    await showDashboard(tester, phone);
    expect(find.byTooltip('Menu'), findsOneWidget);
  });

  testWidgets('front desk staff see no revenue or income', (tester) async {
    await showDashboard(tester, computer, role: VenueRole.staff);
    expect(tester.takeException(), isNull);
    expect(find.text('Revenue overview'), findsNothing);
    expect(find.text('Income this month'), findsNothing);
    expect(find.text('Requests waiting'), findsOneWidget);
    expect(find.text('Income'), findsNothing);
    expect(find.text('Front desk'), findsOneWidget);
  });

  test('chart steps are round numbers', () {
    expect([for (final max in [0, 4500, 13500, 999]) 4 * niceStep(max / 4)], [1000, 6000, 16000, 1000]);
    expect(compactNu(1500), '1.5k');
    expect(compactNu(16000), '16k');
  });

  testWidgets('the revenue range switches', (tester) async {
    await showDashboard(tester, computer);
    expect(find.text('Payments, last 7 days'), findsOneWidget);
    await tester.tap(find.text('1Y'));
    await tester.pumpAndSettle();
    expect(find.text('Payments, last 12 months'), findsOneWidget);
  });
}
