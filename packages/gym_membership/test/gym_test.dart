import 'package:flutter_test/flutter_test.dart';
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

  group('renewalStart', () {
    final today = DateTime(2026, 11, 7);

    test('today, with no membership', () {
      expect(renewalStart([], 'm1', today), today);
    });

    test('the day after the current one ends', () {
      final subs = [
        sub(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 30)),
        sub(start: DateTime(2026, 12, 1), end: DateTime(2026, 12, 30)),
        sub(member: 'm2', start: DateTime(2026, 11, 1), end: DateTime(2027, 1, 30)),
      ];
      expect(renewalStart(subs, 'm1', today), DateTime(2026, 12, 31));
    });

    test('today, when the last one has ended', () {
      expect(renewalStart([sub(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 30))], 'm1', today), today);
    });
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

    test('matches app_modules and owns /gyms and /my-gym', () {
      expect(module.key, 'gym_membership');
      expect(module.ownsPath('/gyms/g1/manage/check-in'), isTrue);
      expect(module.ownsPath('/my-gym'), isTrue);
      expect(module.publicPaths, containsAll(['/gyms', '/gyms/:id']));
      expect(module.servesVenueType('gym'), isTrue);
    });

    test('front-desk staff get no plans or income', () {
      final staff = module.managerMenuItems(gym, VenueRole.staff).map((i) => i.route).toList();
      final owner = module.managerMenuItems(gym, VenueRole.owner).map((i) => i.route).toList();
      expect(staff, isNot(contains(GymRoutes.plansFor('g1'))));
      expect(staff, isNot(contains(GymRoutes.incomeFor('g1'))));
      expect(staff, contains(GymRoutes.checkInFor('g1')));
      expect(owner, containsAll([GymRoutes.plansFor('g1'), GymRoutes.incomeFor('g1')]));
    });

    test('every route it links to is one it has', () {
      final patterns = module.routes.map((r) => (r as dynamic).path as String).toSet();
      expect(patterns, containsAll([GymRoutes.gyms, GymRoutes.gym, GymRoutes.myGym, GymRoutes.checkIn,
        GymRoutes.requests, GymRoutes.members, GymRoutes.plans, GymRoutes.income]));
    });
  });
}
