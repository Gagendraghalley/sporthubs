import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/ask_data.dart';
import 'package:gym_membership/src/screens/ask_screen.dart';
import 'package:sportshub_core/sportshub_core.dart';

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

GymCheckIn visit(String member, int daysAgo, int hour) => GymCheckIn(
      id: '$member-$daysAgo-$hour',
      venueId: 'g1',
      memberId: member,
      gymMemberId: member,
      memberName: member == 'pema' ? 'Pema Wangmo' : 'Member $member',
      checkedInAt: bhutanMidnightUtc(day(-daysAgo)).add(Duration(hours: hour)),
    );

final subs = [
  GymSubscription(
    id: 's1',
    venueId: 'g1',
    memberId: 'pema',
    gymMemberId: 'pema',
    memberName: 'Pema Wangmo',
    planName: 'Monthly',
    durationDays: 30,
    price: 1500,
    status: SubscriptionStatus.active,
    startDate: day(-20),
    endDate: day(10),
    requestedAt: DateTime.utc(2026, 9, 1),
  ),
];

final visits = [visit('pema', 0, 18), visit('pema', 2, 18), visit('b', 1, 7), visit('b', 3, 18)];

final members = [
  GymMember(
    id: 'pema',
    venueId: 'g1',
    code: 'PQ7KX2',
    qrToken: 't1',
    fullName: 'Pema Wangmo',
    phone: '+97517111222',
    joinedOn: day(-20),
    createdAt: DateTime.utc(2026, 10, 1),
  ),
];

final frontDesk = {GymPermission.members, GymPermission.checkIn, GymPermission.register};

/// The AI, as the ask-ai function would answer: [replies] in turn, or
/// [problem].
class FakeAsk extends Fake implements AskRepository {
  FakeAsk(this.replies, {this.problem});
  final List<Map<String, dynamic>> replies;
  final AssistantProblem? problem;
  final asked = <({String question, int history})>[];

  @override
  Future<({AskReply reply, int? left})> ask(
      String venueId, String question, List<({String question, AskReply reply})> history) async {
    asked.add((question: question, history: history.length));
    if (problem != null) throw problem!;
    final data = replies[asked.length - 1];
    return (reply: AskReply.fromJson(data), left: data['left'] as int?);
  }
}

Future<void> show(WidgetTester tester, FakeAsk ai,
    {String role = VenueRole.owner, Set<String> permissions = const {}, Size size = const Size(1440, 1000), bool dark = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      venueAccessProvider.overrideWith((ref, id) async => VenueAccess(gym, role, permissions: permissions)),
      myVenuesProvider.overrideWith((ref) async => [MyVenue(gym, role, permissions: permissions)]),
      gymSubscriptionsProvider.overrideWith((ref, id) async => subs),
      gymMembersProvider.overrideWith((ref, id) async => members),
      gymCheckInsSinceProvider.overrideWith((ref, q) async => visits),
      venuePaymentsProvider.overrideWith((ref, q) async => const <Payment>[]),
      askRepositoryProvider.overrideWithValue(ai),
      currentUserIdProvider.overrideWithValue('u1'),
      unreadCountProvider.overrideWithValue(0),
    ],
    child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: const AskScreen(venueId: 'g1')),
  ));
  await tester.pumpAndSettle();
}

Future<void> ask(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.tap(find.byTooltip('Ask'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a suggestion is answered from the records, without the AI', (tester) async {
    final ai = FakeAsk(const []);
    await show(tester, ai);
    expect(find.text('Ask about Peak Fitness'), findsOneWidget);
    await tester.tap(find.text('Busiest hours this month'));
    await tester.pumpAndSettle();
    expect(find.text('Busiest hours · last 30 days'), findsOneWidget);
    expect(find.text('6–7 pm is the busiest hour: 3 check-ins in the last 30 days.'), findsOneWidget);
    expect(ai.asked, isEmpty);
  });

  testWidgets('a question in their own words: the AI picks the report, the app answers', (tester) async {
    final ai = FakeAsk([
      {'kind': 'report', 'report': 'find_member', 'name': 'Pema', 'left': 24},
      {'kind': 'report', 'report': 'visits_over_time', 'period': 'week', 'left': 23},
    ]);
    await show(tester, ai);
    await ask(tester, 'When did Pema last come?');
    expect(find.text('When did Pema last come?'), findsOneWidget);
    expect(find.text('1 member matches "Pema".'), findsOneWidget);
    expect(find.text('Pema Wangmo · PQ7KX2'), findsOneWidget);
    expect(find.text('Monthly · Came today'), findsOneWidget);
    expect(find.textContaining('24 questions left today'), findsOneWidget);

    await ask(tester, 'and check-ins this week?');
    expect(ai.asked.last, (question: 'and check-ins this week?', history: 1), reason: 'the conversation so far goes along');
    expect(find.text('4 check-ins in the last 7 days: 0.6 a day.'), findsOneWidget);
    expect(find.textContaining('23 questions left today'), findsOneWidget);
  });

  testWidgets('a how-to opens the page that does it', (tester) async {
    await show(tester, FakeAsk([
      {'kind': 'help', 'page': 'members', 'answer': 'Open the member and tap Renew.'},
    ]));
    await ask(tester, 'How do I renew a member?');
    expect(find.text('How to · Members'), findsOneWidget);
    expect(find.text('Open the member and tap Renew.'), findsOneWidget);
    expect(find.text('Open Members'), findsOneWidget);
  });

  testWidgets('when the AI says no, why, and the way to try again', (tester) async {
    await show(tester, FakeAsk(const [], problem: AssistantProblem("You've asked 25 questions today.", left: 0)));
    await ask(tester, 'Revenue?');
    expect(find.text("Couldn't answer"), findsOneWidget);
    expect(find.text("You've asked 25 questions today."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('0 questions left today'), findsOneWidget);
  });

  testWidgets("the front desk isn't shown money", (tester) async {
    await show(tester, FakeAsk([
      {'kind': 'report', 'report': 'revenue', 'period': 'year'},
    ]), role: VenueRole.staff, permissions: frontDesk);
    expect(find.text('Revenue, last 12 months'), findsNothing);
    expect(find.text('Busiest hours this month'), findsOneWidget);
    await ask(tester, 'How much did we make this year?');
    expect(find.text("Your role here doesn't include this. Ask the gym's owner if you need it."), findsOneWidget);
  });

  testWidgets('on a phone, in the dark, every answer fits', (tester) async {
    await show(tester, FakeAsk([
      {'kind': 'report', 'report': 'inactive_members', 'days': 1},
      {'kind': 'other', 'answer': 'I answer questions about your gym.'},
    ]), size: const Size(390, 844), dark: true);
    await tester.tap(find.text('Busiest hours this month'));
    await tester.pumpAndSettle();
    // Now over the box, in a row that scrolls sideways.
    final chips = find
        .descendant(
            of: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Packages ending this week'), 120, scrollable: chips);
    await tester.ensureVisible(find.text('Packages ending this week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Packages ending this week'));
    await tester.pumpAndSettle();
    expect(find.text('Packages ending soon'), findsOneWidget);
    await ask(tester, "Who hasn't come in today?");
    await ask(tester, 'Tell me a joke');
    expect(find.text('I answer questions about your gym.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
