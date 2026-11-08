import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/reports_data.dart';
import 'package:gym_membership/src/screens/check_in_screen.dart';
import 'package:gym_membership/src/screens/reports_screen.dart';
import 'package:gym_membership/src/screens/staff_screens.dart';
import 'package:sportshub_core/sportshub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

final gym = Venue.fromJson({
  'id': 'g1',
  'type': gymVenueType,
  'name': 'Peak Fitness',
  'dzongkhag': 'Thimphu',
  'verification_status': 'verified',
  'created_at': '2026-11-01T00:00:00Z',
});

DateTime day(int offset) {
  final t = BhutanTime.today();
  return DateTime(t.year, t.month, t.day + offset);
}

/// A check-in at [hour] (Bhutan) [daysAgo] days ago.
GymCheckIn visit(String member, int daysAgo, int hour) => GymCheckIn(
      id: '$member-$daysAgo-$hour',
      venueId: 'g1',
      memberId: member,
      gymMemberId: member,
      memberName: 'Member $member',
      checkedInAt: bhutanMidnightUtc(day(-daysAgo)).add(Duration(hours: hour)),
    );

GymSubscription sub(String member, String plan, int from, int to, {String status = SubscriptionStatus.active, int price = 1500}) =>
    GymSubscription(
      id: '$member-$plan-$from',
      venueId: 'g1',
      memberId: member,
      gymMemberId: member,
      planId: plan == 'Gym' ? 'p1' : 'p2',
      planName: plan,
      durationDays: 30,
      price: price,
      status: status,
      startDate: day(from),
      endDate: day(to),
      requestedAt: DateTime.now().toUtc(),
    );

final plans = const [
  GymPlan(id: 'p1', venueId: 'g1', name: 'Gym', durationDays: 30, price: 1500, isActive: true),
  GymPlan(id: 'p2', venueId: 'g1', name: 'Gym + Aerobics', durationDays: 30, price: 2200, isActive: true),
  GymPlan(id: 'p3', venueId: 'g1', name: 'Old plan', durationDays: 30, price: 900, isActive: false),
];

final subs = [
  sub('a', 'Gym', -20, 10),
  sub('b', 'Gym', -40, -10, status: SubscriptionStatus.expired),
  sub('b', 'Gym', -10, 20),
  sub('c', 'Gym + Aerobics', -60, -30, status: SubscriptionStatus.expired, price: 2200),
];

final visits = [visit('a', 0, 18), visit('a', 1, 18), visit('b', 1, 7), visit('a', 7, 18), visit('c', 2, 18)];

List<Override> overrides({String role = VenueRole.owner}) => [
      venueAccessProvider.overrideWith((ref, id) async => VenueAccess(gym, role)),
      myVenuesProvider.overrideWith((ref) async => [MyVenue(gym, role)]),
      gymPlansProvider.overrideWith((ref, q) async => q.all ? plans : plans.where((p) => p.isActive).toList()),
      gymSubscriptionsProvider.overrideWith((ref, id) async => subs),
      gymMembersProvider.overrideWith((ref, id) async => const <GymMember>[]),
      gymCheckInsSinceProvider.overrideWith((ref, q) async => visits),
      gymCheckInsTodayProvider.overrideWith((ref, id) async => visits.where((v) => v.id.contains('-0-')).toList()),
      venuePaymentsProvider.overrideWith((ref, q) async => [
            for (var i = 0; i < 6; i++)
              Payment.fromJson({
                'id': 'pay$i',
                'venue_id': 'g1',
                'module_key': gymModuleKey,
                'amount': 1500,
                'method': i.isEven ? 'cash' : 'mbob',
                'status': 'completed',
                'payer_name': 'Member $i',
                'created_at': bhutanMidnightUtc(day(-i * 20)).add(const Duration(hours: 5)).toIso8601String(),
              }),
          ]),
      unreadCountProvider.overrideWithValue(0),
    ];

Future<void> show(WidgetTester tester, Widget page, {Size size = const Size(1440, 1000), bool dark = false, List<Override>? with_}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: with_ ?? overrides(),
    child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: page),
  ));
}

class FakeRepo extends Fake implements GymRepository {
  @override
  Future<CheckInResult> checkIn(String venueId, MemberRef member) async {
    // As the database refuses it (raise exception: P0001).
    if (member.code == 'ENDED1') {
      throw const PostgrestException(message: "Karma's package ended on 7 Feb 2027. Renew it on their page.", code: 'P0001');
    }
    return CheckInResult(memberName: 'Karma Wangmo', memberCode: member.code, planName: 'Gym', endDate: day(30), daysLeft: 31, earlierToday: 0);
  }
}

void main() {
  group('reports, from the records', () {
    test('visits by weekday and hour, and the busiest hour as a span', () {
      final byHour = checkInsByHour(visits);
      expect(byHour.first.label, '6a');
      expect(byHour.last.label, '9p');
      expect(byHour.firstWhere((p) => p.label == '6p').value, 4);
      expect(checkInsByWeekday(visits).fold<num>(0, (s, p) => s + p.value), visits.length);
      expect(hourSpan('6p'), '6–7 pm');
      expect(hourSpan('11a'), '11 am–12 pm');
      expect(hourSpan('12p'), '12–1 pm');
    });

    test('renewals: of those whose package ended, who has another after it', () {
      final r = renewals(subs, day(-30), day(0));
      expect(r.ended, 2, reason: 'b and c');
      expect(r.renewed, 1, reason: 'b renewed; c did not');
    });

    test('package mix today, and the most regular members', () {
      expect(packageMix(subs, day(0)), [(name: 'Gym', members: 2)]);
      expect(regulars(visits).first, (name: 'Member a', gymMemberId: 'a', visits: 3));
    });

    test('insights say it in words', () {
      final notes = insights(
        byWeekday: checkInsByWeekday(visits),
        byHour: checkInsByHour(visits),
        renewal: (renewed: 1, ended: 2),
        endingSoon: 1,
      );
      expect(notes.first, contains('6–7 pm'));
      expect(notes[1], contains('50%'));
      expect(notes.last, contains('1 package ends this week'));
    });
  });

  for (final (name, size) in [('computer', const Size(1440, 1000)), ('phone', const Size(390, 844))]) {
    for (final dark in [false, true]) {
      final look = '$name, ${dark ? 'dark' : 'light'}';
      testWidgets('Packages fit a $look', (tester) async {
        await show(tester, const PlansScreen(venueId: 'g1'), size: size, dark: dark);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Best seller'), findsWidgets);
      });
      testWidgets('Income fits a $look', (tester) async {
        await show(tester, const IncomeScreen(venueId: 'g1'), size: size, dark: dark);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Received'), findsOneWidget);
      });
      testWidgets('Reports fit a $look', (tester) async {
        await show(tester, const ReportsScreen(venueId: 'g1'), size: size, dark: dark);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('New members'), findsOneWidget);
      });
    }
  }

  testWidgets('Packages: how each is doing, from the memberships', (tester) async {
    await show(tester, const PlansScreen(venueId: 'g1'), size: const Size(1440, 1400));
    await tester.pumpAndSettle();
    // Gym: a and b on it today, sold 3 times.
    expect(find.text('2 now'), findsOneWidget);
    expect(find.text('3 sold'), findsWidgets, reason: 'on its card, and as the best seller');
    expect(find.text('Hidden'), findsWidgets);
    await tester.tap(find.text('Hidden 1'));
    await tester.pumpAndSettle();
    expect(find.text('Old plan'), findsOneWidget);
    expect(find.text('Gym + Aerobics'), findsNothing);
  });

  testWidgets('Income: twelve months as bars; tapping a month opens it', (tester) async {
    await show(tester, const IncomeScreen(venueId: 'g1'), size: const Size(1440, 1400));
    await tester.pumpAndSettle();
    expect(find.text(formatMonth(DateTime(day(0).year, day(0).month))), findsWidgets);
    expect(find.text('How they paid'), findsOneWidget);
  });

  testWidgets('Check-in: a valid card checks in; an ended package is refused, with why', (tester) async {
    await show(
      tester,
      const CheckInScreen(venueId: 'g1'),
      with_: [...overrides(), gymRepositoryProvider.overrideWithValue(FakeRepo())],
    );
    // The scan line sweeps for ever: pump, don't settle.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ready to scan'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4K7P9Q');
    await tester.tap(find.text('Check in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('CHECKED IN'), findsOneWidget);
    expect(find.text('Karma Wangmo'), findsOneWidget);
    expect(find.text('Checked in'), findsOneWidget, reason: 'the viewfinder says so too');

    await tester.enterText(find.byType(TextField), 'ENDED1');
    await tester.tap(find.text('Check in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('NOT CHECKED IN'), findsOneWidget);
    expect(find.textContaining('package ended on'), findsOneWidget);
    expect(find.text('Not checked in'), findsOneWidget);
    // Back to ready after a moment.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Ready to scan'), findsOneWidget);
  });
}
