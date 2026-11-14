import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

/// Booking futsal, football, basketball and badminton grounds, and
/// tournaments. For now they run on the separate ground booking website
/// (its own accounts and data), and SportsHub links to it.
///
/// One domain later: the module already owns its paths in SportsHub
/// (/grounds, /tournaments, /register-ground, the same as the booking
/// website's), so links to them work today (they hand over to the website)
/// and will open the module's own screens once they move in here. See
/// README, 'Bringing ground booking in'.
class GroundBookingModule extends SportsHubModule {
  const GroundBookingModule();

  /// The booking website; GROUND_BOOKING_URL in env.json changes it.
  static const siteUrl = String.fromEnvironment('GROUND_BOOKING_URL', defaultValue: 'https://kuzuhelp.com');

  /// A page of the booking website, which uses hash URLs (/#/grounds).
  static Uri page(String path) => Uri.parse('${siteUrl.replaceFirst(RegExp(r'/+$'), '')}/#$path');

  static const grounds = '/grounds';
  static const groundVenue = '/grounds/venue/:id';
  static const tournaments = '/tournaments';
  static const tournament = '/tournaments/:id';
  static const registerGround = '/register-ground';

  @override
  String get key => 'ground_booking';

  @override
  String get name => 'Ground booking';

  @override
  String get description => 'Book futsal, football, basketball and badminton grounds, and follow tournaments.';

  @override
  IconData get icon => Icons.sports_soccer_rounded;

  @override
  List<String> get basePaths => const [grounds, tournaments, registerGround];

  @override
  List<String> get publicPaths => const [grounds, groundVenue, tournaments, tournament, registerGround];

  @override
  List<RouteBase> get routes => [
        for (final path in publicPaths)
          GoRoute(path: path, builder: (_, state) => GroundBookingHandoff(path: state.uri.path)),
      ];

  @override
  List<VenueKind> get venueKinds => [
        VenueKind(
          key: 'ground',
          label: 'Sports ground',
          description: 'Futsal, football, basketball or badminton',
          icon: Icons.stadium_outlined,
          externalRegisterUrl: page(registerGround),
        ),
      ];

  @override
  List<ModuleMenuItem> playerMenuItems() => [
        ModuleMenuItem(
          title: 'Book a ground',
          subtitle: 'Free times at grounds near you',
          icon: Icons.sports_soccer_rounded,
          externalUrl: page(grounds),
        ),
        ModuleMenuItem(
          title: 'Tournaments',
          subtitle: 'Fixtures, tables and results',
          icon: Icons.emoji_events_outlined,
          externalUrl: page(tournaments),
        ),
      ];

  /// Where SportsHub's assistant sends people asking about grounds.
  @override
  Map<String, ModuleMenuItem> get assistantLinks => {
        'grounds': ModuleMenuItem(title: 'Book a ground', icon: Icons.sports_soccer_rounded, externalUrl: page(grounds)),
        'tournaments':
            ModuleMenuItem(title: 'Tournaments', icon: Icons.emoji_events_outlined, externalUrl: page(tournaments)),
      };

  @override
  ServiceNav? navigation(WidgetRef ref, String location) => ServiceNav(
        key: key,
        name: name,
        icon: icon,
        color: BrandColors.blue,
        tagline: 'Futsal · football · basketball · badminton',
        sections: [
          NavSection(items: [
            NavDestination(label: 'Book a ground', icon: Icons.sports_soccer_rounded, externalUrl: page(grounds)),
            NavDestination(label: 'Tournaments', icon: Icons.emoji_events_outlined, externalUrl: page(tournaments)),
          ]),
        ],
        isSetUp: true,
      );
}

/// A ground booking page opened in SportsHub: for now, it hands over to the
/// same page on the booking website.
class GroundBookingHandoff extends StatelessWidget {
  final String path;

  const GroundBookingHandoff({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final tournaments = path.startsWith(GroundBookingModule.tournaments);
    return AppPage(
      title: tournaments ? 'Tournaments' : 'Ground booking',
      body: EmptyState(
        icon: tournaments ? Icons.emoji_events_outlined : Icons.sports_soccer_rounded,
        title: tournaments ? 'Tournaments are on our booking website' : 'Grounds are booked on our booking website',
        message: 'It opens in a new tab. Ground booking is coming into SportsHub soon.',
        actionLabel: 'Open it',
        onAction: () => openExternal(context, GroundBookingModule.page(path)),
      ),
    );
  }
}
