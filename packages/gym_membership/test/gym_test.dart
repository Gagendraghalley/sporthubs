import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:sportshub_core/sportshub_core.dart';

GymSubscription sub({
  String member = 'm1',
  String status = SubscriptionStatus.active,
  DateTime? start,
  DateTime? end,
  int days = 30,
}) =>
    GymSubscription(
      id: 's-$member-$status-${start ?? ''}',
      venueId: 'g1',
      memberId: member,
      planName: 'Monthly',
      durationDays: days,
      price: 1500,
      status: status,
      startDate: start,
      endDate: end,
      requestedAt: DateTime.utc(2026, 11, 1),
    );

void main() {
  group('MemberQr', () {
    const id = '0f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5b';

    test('encodes the account id', () {
      expect(MemberQr.encode(id), 'sportshub:member:$id');
    });

    test('reads a scanned code, a bare id or a typed member code', () {
      expect(MemberQr.parse('sportshub:member:$id'), const MemberRef.id(id));
      expect(MemberQr.parse('SPORTSHUB:MEMBER:${id.toUpperCase()}'), const MemberRef.id(id));
      expect(MemberQr.parse(' $id '), const MemberRef.id(id));
      expect(MemberQr.parse('4k7-p9q'), const MemberRef.code('4K7P9Q'));
    });

    test("reads a registered member's card", () {
      const token = '0123456789abcdef0123456789abcdef';
      expect(MemberQr.encodeCard(token), 'sportshub:gym-member:$token');
      expect(MemberQr.parse('sportshub:gym-member:$token'), const MemberRef.card(token));
      expect(MemberQr.parse('SPORTSHUB:GYM-MEMBER:${token.toUpperCase()}'), const MemberRef.card(token));
      expect(MemberQr.parse('sportshub:gym-member:short'), isNull);
    });

    test('rejects anything else', () {
      expect(MemberQr.parse('sportshub:member:not-an-id'), isNull);
      expect(MemberQr.parse('https://example.com'), isNull);
      expect(MemberQr.parse('12345'), isNull);
      expect(MemberQr.parse(''), isNull);
    });
  });

  group('a membership', () {
    final today = DateTime(2026, 11, 7);
    final current = sub(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 30));

    test('covers its first and last days', () {
      expect(current.isCurrentOn(DateTime(2026, 11, 1)), isTrue);
      expect(current.isCurrentOn(DateTime(2026, 11, 30)), isTrue);
      expect(current.isCurrentOn(DateTime(2026, 12, 1)), isFalse);
    });

    test('counts days left with today included', () {
      expect(current.daysLeftOn(today), 24);
      expect(current.daysLeftOn(DateTime(2026, 11, 30)), 1);
      expect(current.progressOn(DateTime(2026, 11, 30)), 1.0);
    });

    test('a renewal is upcoming, a request is pending', () {
      expect(sub(start: DateTime(2026, 12, 1), end: DateTime(2026, 12, 30)).isUpcomingOn(today), isTrue);
      expect(sub(status: SubscriptionStatus.pending).isPending, isTrue);
      expect(sub(status: SubscriptionStatus.pending).isCurrentOn(today), isFalse);
    });
  });

  group('selling a package', () {
    const monthly = GymPlan(id: 'p1', venueId: 'g1', name: 'Gym', durationDays: 30, price: 1500, isActive: true);
    const yearly = GymPlan(id: 'p2', venueId: 'g1', name: 'Gym yearly', durationDays: 365, price: 12000, isActive: true);
    const week = GymPlan(id: 'p3', venueId: 'g1', name: 'Week', durationDays: 7, price: 500, isActive: true);

    test('expires on the same date, months later (as the database works it out)', () {
      // The client's example: joining 8 November 2026 for 3 months.
      expect(packageEnd(DateTime(2026, 11, 8), 3), DateTime(2027, 2, 8));
      expect(packageEnd(DateTime(2026, 11, 8), 1), DateTime(2026, 12, 8));
      expect(packageEnd(DateTime(2026, 12, 15), 12), DateTime(2027, 12, 15));
      // 31 January + 1 month is 28 February (29 in a leap year).
      expect(packageEnd(DateTime(2027, 1, 31), 1), DateTime(2027, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
    });

    test('a renewal starts on the day the current package expires, so the dates keep', () {
      final today = DateTime(2026, 11, 8);
      final current = sub(start: DateTime(2026, 11, 8), end: DateTime(2027, 2, 8));
      expect(renewalStart([current], today), DateTime(2027, 2, 8));
      expect(packageEnd(renewalStart([current], today), 3), DateTime(2027, 5, 8));
      // Already renewed once: after that one.
      final next = sub(start: DateTime(2027, 2, 8), end: DateTime(2027, 5, 8));
      expect(renewalStart([current, next], today), DateTime(2027, 5, 8));
      // Ended (or never had one): from today.
      expect(renewalStart([sub(status: SubscriptionStatus.expired, start: DateTime(2026, 8, 1), end: DateTime(2026, 9, 1))], today),
          today);
      expect(renewalStart([], today), today);
    });

    test('on the expiry day both packages cover it, and the renewal counts', () {
      final day = DateTime(2027, 2, 8);
      final first = sub(start: DateTime(2026, 11, 8), end: day);
      final renewal = sub(start: day, end: DateTime(2027, 5, 8));
      expect(first.isCurrentOn(day) && renewal.isCurrentOn(day), isTrue);
      expect(standingOf([first, renewal], day), MemberStanding.active);
      // The day before, the renewal is still to come: not "ending soon".
      expect(renewal.isUpcomingOn(DateTime(2027, 2, 7)), isTrue);
    });

    test("suggests the package's price for the months, starting on its own length", () {
      expect(packagePrice(monthly, 3), 4500);
      expect(defaultMonths(monthly), 1);
      expect(packagePrice(yearly, 12), 12000);
      expect(packagePrice(yearly, 6), 6000);
      expect(defaultMonths(yearly), 12);
      expect(planMonths(week), 1);
    });

    test("a member's standing", () {
      final today = DateTime(2026, 11, 8);
      expect(standingOf([], today), MemberStanding.none);
      expect(standingOf([sub(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 30))], today), MemberStanding.active);
      expect(standingOf([sub(start: DateTime(2026, 12, 1), end: DateTime(2026, 12, 30))], today), MemberStanding.upcoming);
      expect(standingOf([sub(status: SubscriptionStatus.expired, start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30))], today),
          MemberStanding.ended);
    });
  });

  test('a registered member, and the details sent to register them', () {
    final m = GymMember.fromJson({
      'id': 'gm1',
      'venue_id': 'g1',
      'code': '4K7P9Q',
      'qr_token': '0123456789abcdef0123456789abcdef',
      'full_name': 'Karma Wangmo',
      'phone': '+97517123456',
      'date_of_birth': '1995-04-12',
      'blood_group': 'B+',
      'village_id': 1,
      'gewog_id': 1,
      'dzongkhag_id': 1,
      'village': {'name': 'Chakhar'},
      'gewog': {'name': 'Chokhor'},
      'dzongkhag': {'name': 'Bumthang'},
      'medical_notes': 'Asthma',
      'joined_on': '2026-11-08',
      'created_at': '2026-11-08T04:00:00Z',
    });
    expect(m.placeName, 'Chakhar, Chokhor, Bumthang');
    expect(m.dateOfBirth, DateTime(1995, 4, 12));
    final json = MemberDetails(
      fullName: ' Karma Wangmo ',
      phone: '17 12 34 56',
      email: '',
      joinedOn: DateTime(2026, 11, 8),
      emergencyContactPhone: '77123456',
      place: const LocationSelection(dzongkhagId: 1, gewogId: 1, villageId: 1),
    ).toJson();
    expect(json['full_name'], 'Karma Wangmo');
    expect(json['phone'], '+97517123456');
    expect(json['email'], isNull);
    expect(json['emergency_contact_phone'], '+97577123456');
    expect(json['joined_on'], '2026-11-08');
    expect(json['village_id'], 1);
    expect(m.details.place, const LocationSelection(dzongkhagId: 1, gewogId: 1, villageId: 1));
  });

  test('a membership and a check-in from the database', () {
    final s = GymSubscription.fromJson({
      'id': 's1',
      'venue_id': 'g1',
      'member_id': 'm1',
      'plan_id': 'p1',
      'plan_name': 'Monthly',
      'duration_days': 30,
      'price': 1500,
      'status': 'active',
      'start_date': '2026-11-07',
      'end_date': '2026-12-06',
      'requested_at': '2026-11-07T03:00:00Z',
      'activated_at': '2026-11-07T04:00:00Z',
      'member': {'full_name': 'Pema', 'phone': '+97517123456', 'member_code': '4K7P9Q'},
      'gym': {'name': 'Peak Fitness'},
    });
    expect(s.endDate, DateTime(2026, 12, 6));
    expect(s.memberCode, '4K7P9Q');
    expect(s.gymName, 'Peak Fitness');

    final r = CheckInResult.fromJson({
      'member_name': 'Pema',
      'member_code': '4K7P9Q',
      'plan_name': 'Monthly',
      'end_date': '2026-12-06',
      'days_left': 30,
      'earlier_today': 1,
    });
    expect(r.daysLeft, 30);
    expect(r.earlierToday, 1);
  });

  group('GymModule', () {
    const module = GymModule();
    final gym = Venue.fromJson({
      'id': 'g1',
      'type': 'gym',
      'name': 'Peak Fitness',
      'dzongkhag': 'Thimphu',
      'verification_status': 'verified',
      'created_at': '2026-11-07T10:00:00Z',
    });

    test('matches app_modules and owns /gyms', () {
      expect(module.key, 'gym_membership');
      expect(module.ownsPath('/gyms/g1/manage/check-in'), isTrue);
      expect(module.ownsPath('/my-gym'), isFalse);
      expect(module.publicPaths, containsAll(['/gyms', '/gyms/:id']));
      expect(module.servesVenueType('gym'), isTrue);
    });

    List<String?> menu(String role, [Set<String> permissions = const {}]) =>
        module.managerMenuItems(gym, VenueAccess(gym, role, permissions: permissions)).map((i) => i.route).toList();

    test('front-desk staff get no plans or income', () {
      final staff = menu(VenueRole.staff, {GymPermission.members, GymPermission.payments, GymPermission.checkIn});
      final owner = menu(VenueRole.owner);
      expect(staff, isNot(contains(GymRoutes.plansFor('g1'))));
      expect(staff, isNot(contains(GymRoutes.incomeFor('g1'))));
      expect(staff, contains(GymRoutes.checkInFor('g1')));
      expect(owner, containsAll([GymRoutes.plansFor('g1'), GymRoutes.incomeFor('g1')]));
    });

    test('a role made by admins gets exactly its permissions', () {
      final cashier = menu('cashier', {GymPermission.payments, VenuePermission.income});
      expect(cashier, contains(GymRoutes.incomeFor('g1')));
      expect(cashier, isNot(contains(GymRoutes.checkInFor('g1'))));
      expect(cashier, isNot(contains(GymRoutes.membersFor('g1'))));
      expect(cashier, isNot(contains(GymRoutes.plansFor('g1'))));
      // Nothing at all: still the dashboard.
      expect(menu('viewer'), [GymRoutes.dashboardFor('g1')]);
    });

    test('every route it links to is one it has', () {
      final patterns = [for (final r in module.routes) (r as GoRoute).path];
      expect(patterns, containsAll([GymRoutes.gyms, GymRoutes.gym, GymRoutes.dashboard, GymRoutes.checkIn, GymRoutes.members,
        GymRoutes.registerMember, GymRoutes.member, GymRoutes.editMember, GymRoutes.memberRegistered, GymRoutes.plans,
        GymRoutes.income, GymRoutes.reports]));
      // 'new' before ':memberId', or registering would open a member called 'new'.
      expect(patterns.indexOf(GymRoutes.registerMember), lessThan(patterns.indexOf(GymRoutes.member)));
      // All in the app's frame: one menu.
      expect(module.fullScreenRoutes, isEmpty);
    });
  });
}
