import 'package:flutter_test/flutter_test.dart';
import 'package:ground_booking/ground_booking.dart';

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
}
