import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

/// Public information: the verified gyms on SportsHub, by dzongkhag. What
/// the Welcome page's "Find a gym" opens; no account needed.
class GymListScreen extends ConsumerStatefulWidget {
  const GymListScreen({super.key});

  @override
  ConsumerState<GymListScreen> createState() => _GymListScreenState();
}

class _GymListScreenState extends ConsumerState<GymListScreen> {
  String? _dzongkhag;

  @override
  Widget build(BuildContext context) {
    const query = (type: gymVenueType, dzongkhag: null);
    return AppPage(
      title: 'Gyms on SportsHub',
      leading: IconButton(
        tooltip: 'Back to SportsHub home',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.go(CoreRoutes.root),
      ),
      body: AsyncValueView<List<Venue>>(
        value: ref.watch(publicVenuesProvider(query)),
        onRetry: () => ref.invalidate(publicVenuesProvider(query)),
        data: (gyms) {
          final places = {for (final g in gyms) g.dzongkhag}.toList()..sort();
          final shown = _dzongkhag == null ? gyms : gyms.where((g) => g.dzongkhag == _dzongkhag).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(publicVenuesProvider(query).future),
            child: ListView(
              padding: pagePadding(context),
              children: [
                if (places.length > 1) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final place in [null, ...places])
                        ChoiceChip(
                          label: Text(place ?? 'All'),
                          selected: _dzongkhag == place,
                          onSelected: (_) => setState(() => _dzongkhag = place),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (shown.isEmpty)
                  EmptyState(
                    icon: Icons.fitness_center_rounded,
                    title: 'No gyms here yet',
                    message: 'Run a gym? Register it on SportsHub.',
                    actionLabel: 'Register your gym',
                    onAction: () => context.push(CoreRoutes.registerVenue),
                  )
                else
                  ResponsiveGrid(
                    minItemWidth: 320,
                    maxColumns: 4,
                    equalHeight: false,
                    children: [
                      for (final gym in shown)
                        VenueCard(
                          venue: gym,
                          placeholderIcon: Icons.fitness_center_rounded,
                          onTap: () => context.push(GymRoutes.gymFor(gym.id)),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Public information about one gym: photos, where it is, its packages and
/// prices, how to reach it and how to join (at its front desk), reviews.
/// Its staff also get a way into running it.
class GymDetailsScreen extends ConsumerWidget {
  final String venueId;

  const GymDetailsScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venue = ref.watch(venueProvider(venueId));
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final access = signedIn ? ref.watch(venueAccessProvider(venueId)).valueOrNull : null;

    return AppPage(
      title: venue.valueOrNull?.name ?? 'Gym',
      actions: [
        if (access != null)
          TextButton.icon(
            onPressed: () => context.go(GymRoutes.dashboardFor(venueId)),
            icon: const Icon(Icons.space_dashboard_rounded),
            label: const Text('Dashboard'),
          ),
      ],
      body: AsyncValueView<Venue?>(
        value: venue,
        onRetry: () => ref.invalidate(venueProvider(venueId)),
        data: (gym) {
          if (gym == null || gym.type != gymVenueType) {
            return const EmptyState(icon: Icons.search_off_rounded, title: 'This gym is not on SportsHub');
          }
          final plans = ref.watch(gymPlansProvider((venueId: venueId, all: false)));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(venueProvider(venueId));
              ref.invalidate(gymPlansProvider((venueId: venueId, all: false)));
            },
            child: ListView(
              padding: pagePadding(context),
              children: [
                if (!gym.isVerified)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StatusChip(
                      label: 'Not live yet: only its staff can see this page',
                      color: context.brand.warning,
                      icon: Icons.visibility_off_outlined,
                    ),
                  ),
                ResponsiveColumns(
                  flex: (3, 2),
                  first: [
                    VenuePhotoCarousel(photos: gym.photos, placeholderIcon: Icons.fitness_center_rounded),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Text(gym.name, style: context.text.headlineSmall)),
                        if (gym.isVerified) VerificationChip(status: gym.verificationStatus),
                      ],
                    ),
                    const SizedBox(height: 4),
                    InfoRow(icon: Icons.place_outlined, text: [gym.place, if (gym.address != null) gym.address!].join(' · ')),
                    if (gym.ratingCount > 0)
                      Row(children: [
                        RatingStars(rating: gym.ratingAverage!),
                        Text('  ${gym.ratingAverage!.toStringAsFixed(1)} · ${gym.ratingCount} reviews'),
                      ]),
                    const SizedBox(height: 12),
                    VenueContactButtons(venue: gym),
                    if (gym.description != null) ...[
                      const SectionTitle('About'),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(gym.description!)),
                    ],
                    ReviewsSection(venue: gym),
                  ],
                  second: [
                    const SectionTitle('How to join'),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const InfoRow(
                            icon: Icons.storefront_outlined,
                            text: 'Visit the front desk: they register you, take your photo and give you your '
                                'QR member card (on WhatsApp too).',
                          ),
                          const InfoRow(
                            icon: Icons.qr_code_2_rounded,
                            text: 'Show the card at the counter each time you come in.',
                          ),
                          if (gym.paymentInfo != null)
                            InfoRow(icon: Icons.account_balance_wallet_outlined, text: 'How to pay: ${gym.paymentInfo!}'),
                        ],
                      ),
                    ),
                    const SectionTitle('Packages'),
                    AsyncValueView<List<GymPlan>>(
                      value: plans,
                      onRetry: () => ref.invalidate(gymPlansProvider((venueId: venueId, all: false))),
                      data: (list) => list.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text('This gym has not added its packages yet.'),
                            )
                          : Column(
                              children: [
                                for (final plan in list)
                                  Padding(padding: const EdgeInsets.only(bottom: 10), child: PlanCard(plan: plan)),
                              ],
                            ),
                    ),
                    if (gym.cancellationPolicy != null) ...[
                      const SectionTitle('Cancellation and refunds'),
                      SectionCard(child: Text(gym.cancellationPolicy!)),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
