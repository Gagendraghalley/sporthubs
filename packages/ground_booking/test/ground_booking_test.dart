import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_booking/ground_booking.dart';
import 'package:sportshub_core/sportshub_core.dart';

void main() {
  const module = GroundBookingModule();

  test('links to the booking website with its hash URLs', () {
    expect(GroundBookingModule.page('/grounds').toString(), '${GroundBookingModule.siteUrl}/#/grounds');
    expect(module.playerMenuItems().every((i) => i.isExternal), isTrue);
  });

  test('grounds are registered on the booking website', () {
    final kind = module.venueKinds.single;
    expect(kind.externalRegisterUrl.toString(), endsWith('/#/register-ground'));
    expect(module.servesVenueType('ground'), isFalse, reason: 'SportsHub runs no grounds itself yet');
  });

  test('keeps its paths in SportsHub for when it moves in (one domain)', () {
    expect(module.ownsPath('/grounds/venue/1'), isTrue);
    expect(module.ownsPath('/tournaments/7'), isTrue);
    expect(module.ownsPath('/register-ground'), isTrue);
    expect(module.publicPaths, containsAll(['/grounds', '/tournaments']));
  });

  testWidgets('adds booking and tournament links to the service navigation', (tester) async {
    ServiceNav? nav;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          nav = module.navigation(ref, '/');
          return const SizedBox.shrink();
        }),
      ),
    ));

    expect(nav?.key, 'ground_booking');
    expect(nav?.destinations.map((d) => d.label), ['Book a ground', 'Tournaments']);
    expect(nav?.destinations.every((d) => d.isExternal), isTrue);
  });
}
