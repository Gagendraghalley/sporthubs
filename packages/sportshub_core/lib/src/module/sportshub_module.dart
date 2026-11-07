import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/core_routes.dart';
import '../utils/launch.dart';
import '../venues/venue.dart';

/// What every SportsHub module (ground booking, gym membership, later
/// coaching, events...) gives the app. Modules depend only on
/// sportshub_core, never on each other; the app lists them in main.dart.
///
/// Adding a module = a package implementing this + one line in main.dart +
/// one migration (its tables, and its row in app_modules).
abstract class SportsHubModule {
  const SportsHubModule();

  /// Matches app_modules.key, where admins turn the module on and off.
  String get key;
  String get name;
  String get description;
  IconData get icon;

  /// The paths the module's pages live under, e.g. ['/gyms', '/my-gym'].
  /// While the module is turned off, the router sends these home.
  List<String> get basePaths => const [];

  /// The module's pages.
  List<RouteBase> get routes => const [];

  /// Route patterns visitors can open without signing in, e.g.
  /// ['/gyms', '/gyms/:id'].
  List<String> get publicPaths => const [];

  /// The kinds of venue it serves, offered on 'Register your venue'.
  List<VenueKind> get venueKinds => const [];

  /// For players and members: what the module offers them.
  List<ModuleMenuItem> playerMenuItems() => const [];

  /// For someone running [venue] (one of this module's [venueKinds]) as
  /// [role] (VenueRole): the pages that run it.
  List<ModuleMenuItem> managerMenuItems(Venue venue, String role) => const [];

  /// The module's section on the home page; null for a plain one made from
  /// [name] and [playerMenuItems].
  Widget? buildHomeSection(BuildContext context) => null;

  /// The whole signed-in home, when this module is the first enabled one
  /// that has one (the app's lead service); null for none. With none, home
  /// is the plain one: a section per module, Run a venue and admin.
  Widget? buildHome(BuildContext context) => null;

  /// The whole Welcome page for visitors, when this module is the first
  /// enabled one that has one (the app's lead service); null for none. With
  /// none, Welcome is the plain one: the logo, sign-up and sign-in.
  Widget? buildWelcome(BuildContext context) => null;

  /// Where someone running [venue] lands from Your venues: the module's own
  /// console (e.g. a gym's dashboard); null for the venue's Manage page.
  String? managerHomeRoute(Venue venue) => null;

  /// Shown above [managerMenuItems] on a venue's Manage page (e.g. today's
  /// numbers); null for nothing.
  Widget? buildManagerSection(BuildContext context, Venue venue, String role) => null;

  /// Whether [path] is one of this module's pages.
  bool ownsPath(String path) => basePaths.any((base) => path == base || path.startsWith('$base/'));

  /// Whether this module runs venues of [venueType].
  bool servesVenueType(String venueType) => venueKinds.any((k) => k.key == venueType && k.externalRegisterUrl == null);
}

/// Where someone running [venue] lands: the console of the module that runs
/// it ([SportsHubModule.managerHomeRoute]), or else the venue's Manage page.
String venueHomeRoute(Iterable<SportsHubModule> modules, Venue venue) {
  for (final m in modules) {
    if (m.servesVenueType(venue.type)) return m.managerHomeRoute(venue) ?? CoreRoutes.venueManageFor(venue.id);
  }
  return CoreRoutes.venueManageFor(venue.id);
}

/// A kind of venue a module serves (venue_types.key), e.g. 'gym'.
class VenueKind {
  final String key;
  final String label;
  final String description;
  final IconData icon;

  /// Registered somewhere else (e.g. grounds, on the ground booking
  /// website): 'Register your venue' opens this instead of the form.
  final Uri? externalRegisterUrl;

  const VenueKind({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    this.externalRegisterUrl,
  });
}

/// A menu entry: a page in the app ([route]) or a website ([externalUrl]).
class ModuleMenuItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? route;
  final Uri? externalUrl;

  const ModuleMenuItem({required this.title, required this.icon, this.subtitle, this.route, this.externalUrl})
      : assert((route == null) != (externalUrl == null), 'Give a route or an externalUrl');

  bool get isExternal => externalUrl != null;

  Future<void> open(BuildContext context) async {
    if (route != null) {
      context.push(route!);
    } else {
      await openExternal(context, externalUrl!);
    }
  }
}
