import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/ask_data.dart';
import 'package:gym_membership/src/data/dashboard_data.dart';
import 'package:sportshub_core/sportshub_core.dart';

final today = DateTime(2026, 11, 14);
DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);

GymSubscription sub(String member, int from, int to, {String status = SubscriptionStatus.active}) => GymSubscription(
      id: '$member-$from',
      venueId: 'g1',
      memberId: member,
      gymMemberId: member,
      memberName: 'Member $member',
      planName: 'Monthly',
      durationDays: 30,
      price: 1500,
      status: status,
      startDate: day(from),
      endDate: day(to),
      requestedAt: DateTime.utc(2026, 9, 1),
    );

GymCheckIn visit(String member, int daysAgo) => GymCheckIn(
      id: '$member-$daysAgo',
      venueId: 'g1',
      memberId: member,
      gymMemberId: member,
      checkedInAt: bhutanMidnightUtc(day(-daysAgo)).add(const Duration(hours: 18)),
    );

GymMember member(String id, String name, {String code = 'AAAAAA', String phone = '+97517000000', DateTime? joined}) =>
    GymMember(
      id: id,
      venueId: 'g1',
      code: code,
      qrToken: 'token-$id',
      fullName: name,
      phone: phone,
      joinedOn: joined ?? day(-100),
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('what the ask-ai function says', () {
    test('a report, its period and its days', () {
      final r = AskReply.fromJson({'kind': 'report', 'report': 'inactive_members', 'period': 'year', 'days': 21, 'left': 3});
      expect(r.kind, AskKind.report);
      expect(r.report, AskReport.inactiveMembers);
      expect(r.period, AskPeriod.year);
      expect(r.days, 21);
    });

    test('days default where a report has them, and only there', () {
      expect(AskReply.fromJson({'kind': 'report', 'report': 'ending_soon'}).days, 7);
      expect(AskReply.fromJson({'kind': 'report', 'report': 'inactive_members'}).days, 14);
      expect(AskReply.fromJson({'kind': 'report', 'report': 'revenue', 'days': 9}).days, isNull);
      expect(AskReply.fromJson({'kind': 'report', 'report': 'revenue', 'period': 'decade'}).period, AskPeriod.month);
    });

    test('finding a member needs a name', () {
      final r = AskReply.fromJson({'kind': 'report', 'report': 'find_member', 'name': ' Pema '});
      expect((r.report, r.name), (AskReport.findMember, 'Pema'));
      expect(AskReply.fromJson({'kind': 'report', 'report': 'find_member'}).kind, AskKind.other);
    });

    test('a how-to, and anything else', () {
      final help = AskReply.fromJson({'kind': 'help', 'page': 'members', 'answer': 'Open them and tap Renew.'});
      expect((help.kind, help.page, help.answer), (AskKind.help, AskPage.members, 'Open them and tap Renew.'));
      expect(AskReply.fromJson({'kind': 'report', 'report': 'drop_tables'}).answer, askWhatICanDo);
      expect(AskReply.fromJson({'kind': 'other', 'answer': 'Hello!'}).answer, 'Hello!');
      expect(AskReply.fromJson(const {}).kind, AskKind.other);
    });

    test('sent back in the conversation as the function reads it', () {
      expect(const AskReply.report(AskReport.endingSoon, days: 3).toJson(),
          {'kind': 'report', 'report': 'ending_soon', 'period': 'month', 'days': 3});
      expect(AskReply.fromJson({'kind': 'help', 'page': 'staff', 'answer': 'x'}).toJson(), {'kind': 'help', 'page': 'staff'});
    });

    test('every page opens one of the gym\'s pages', () {
      expect(AskPage.members.route('g1'), GymRoutes.membersFor('g1'));
      expect(AskPage.settings.route('g1'), CoreRoutes.editVenueFor('g1'));
    });
  });

  test('periods end today and start where their charts do', () {
    expect(AskPeriod.week.from(today), day(-6));
    expect(AskPeriod.month.from(today), day(-29));
    expect(AskPeriod.quarter.from(today), day(-89));
    expect(AskPeriod.year.from(today), DateTime(2025, 12, 1));
    expect(AskPeriod.quarter.description, 'the last 90 days');
  });

  test("members with a package who haven't come in, but not those who just joined", () {
    final subs = [
      sub('came', -40, 10),
      sub('away', -40, 10),
      sub('new', -5, 25),
      sub('ended', -60, -30, status: SubscriptionStatus.expired),
      sub('renewed', -60, -20, status: SubscriptionStatus.expired),
      sub('renewed', -20, 10),
    ];
    final visits = [visit('came', 3), visit('away', 20), visit('ended', 1)];
    final away = notComingMembers(subs, visits, today, 14);
    expect(away.map((s) => s.memberId), ['away', 'renewed']);
    expect(notComingMembers(subs, visits, today, 30).map((s) => s.memberId), ['renewed'],
        reason: "'away' came 20 days ago; 'new' joined within the 30 days");
  });

  test('revenue by how it was paid, the most first', () {
    Payment pay(int amount, String method, {String status = 'completed'}) => Payment.fromJson({
          'id': '$amount$method',
          'venue_id': 'g1',
          'module_key': gymModuleKey,
          'amount': amount,
          'method': method,
          'status': status,
          'created_at': '2026-11-10T04:00:00Z',
        });
    expect(revenueByMethod([pay(1500, 'cash'), pay(3000, 'mbob'), pay(500, 'cash'), pay(9000, 'bank', status: 'pending')]), [
      (label: 'mBoB', amount: 3000),
      (label: 'Cash', amount: 2000),
    ]);
  });

  test('finding members by code, name or phone', () {
    final members = [
      member('1', 'Pema Wangmo', code: 'PQ7KX2', phone: '+97517111222'),
      member('2', 'Karma Pema Dorji', code: 'ZZ3ABC'),
      member('3', 'Sonam Choden', code: 'RT5WWW', phone: '+97577123456'),
    ];
    expect(findMembers(members, 'pema').map((m) => m.id), ['1', '2'], reason: 'names that start with it first');
    expect(findMembers(members, 'dorji pema').map((m) => m.id), ['2']);
    expect(findMembers(members, 'pq7-kx2').map((m) => m.id), ['1']);
    expect(findMembers(members, '7712 3456').map((m) => m.id), ['3']);
    expect(findMembers(members, '12'), isEmpty, reason: 'too few digits to be a phone');
    expect(findMembers(members, '  '), isEmpty);
  });

  test('each member\'s last visit', () {
    final last = lastVisits([visit('a', 5), visit('a', 1), visit('b', 9)]);
    expect(last['a'], visit('a', 1).checkedInAt);
    expect(last['b'], visit('b', 9).checkedInAt);
  });

  test('new members counted by day of joining', () {
    final points = joinedSeries([member('1', 'A', joined: day(0)), member('2', 'B', joined: day(-6)), member('3', 'C', joined: day(-7))],
        today, RevenueRange.week);
    expect(points.length, 7);
    expect(points.first.amount, 1);
    expect(points.last.amount, 1);
    expect(points.fold(0, (s, p) => s + p.amount), 2, reason: 'a week ago is outside the 7 days');
  });
}
