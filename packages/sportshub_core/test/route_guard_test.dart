import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';

void main() {
  const public = {...CoreRoutes.publicPaths, '/gyms', '/gyms/:id'};

  String? guard(String location,
          {String? pattern, bool signedIn = false, String? moduleKey, Set<String>? enabled}) =>
      guardRoute(
        uri: Uri.parse(location),
        pattern: pattern ?? Uri.parse(location).path,
        signedIn: signedIn,
        publicPatterns: public,
        moduleKey: moduleKey,
        enabledModuleKeys: enabled,
      );

  test('/ goes home when signed in, to Welcome otherwise', () {
    expect(guard('/', signedIn: true), CoreRoutes.home);
    expect(guard('/'), CoreRoutes.welcome);
  });

  test('visitors open public pages, including ones with ids', () {
    expect(guard('/gyms'), isNull);
    expect(guard('/gyms/abc', pattern: '/gyms/:id'), isNull);
    expect(guard(CoreRoutes.registerVenue), isNull);
  });

  test('visitors sign in first for everything else, then come back', () {
    expect(guard('/my-gym'), '/sign-in?next=%2Fmy-gym');
    expect(guard('/gyms/abc/manage/plans', pattern: '/gyms/:id/manage/plans'),
        CoreRoutes.signInFor('/gyms/abc/manage/plans'));
  });

  test('signed-in users skip the sign-in pages, to ?next= when it is ours', () {
    expect(guard('/sign-in', signedIn: true), CoreRoutes.home);
    expect(guard('/sign-in?next=%2Fmy-gym', pattern: '/sign-in', signedIn: true), '/my-gym');
    expect(guard('/sign-in?next=https%3A%2F%2Fevil.example', pattern: '/sign-in', signedIn: true), CoreRoutes.home);
    expect(guard('/verify', signedIn: true), isNull, reason: 'the code page sends them on itself');
  });

  test("a module's pages close while it is turned off", () {
    expect(guard('/gyms', moduleKey: 'gym_membership', enabled: {'ground_booking'}), CoreRoutes.welcome);
    expect(guard('/my-gym', signedIn: true, moduleKey: 'gym_membership', enabled: {'ground_booking'}), CoreRoutes.home);
    expect(guard('/gyms', moduleKey: 'gym_membership', enabled: {'gym_membership'}), isNull);
    expect(guard('/gyms', moduleKey: 'gym_membership'), isNull, reason: 'not known yet: let them in');
  });

  test('safeNext keeps only pages of this app', () {
    expect(safeNext('/gyms/1'), '/gyms/1');
    expect(safeNext('//evil.example'), isNull);
    expect(safeNext('https://evil.example'), isNull);
    expect(safeNext(null), isNull);
  });
}
