import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/member_qr.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

/// Verified gyms, by dzongkhag. Open to visitors.
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
    final signedIn = ref.watch(currentUserIdProvider) != null;
    return AppPage(
      title: 'Find a gym',
      actions: [
        if (signedIn)
          IconButton(
            tooltip: 'My gym',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () => context.push(GymRoutes.myGym),
          ),
      ],
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
                if (places.length > 1)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final place in [null, ...places])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(place ?? 'All'),
                              selected: _dzongkhag == place,
                              onSelected: (_) => setState(() => _dzongkhag = place),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  EmptyState(
                    icon: Icons.fitness_center_rounded,
                    title: 'No gyms here yet',
                    message: 'Run a gym? Register it and members can join from their phones.',
                    actionLabel: 'Register your gym',
                    onAction: () => context.push(CoreRoutes.registerVenue),
                  ),
                for (final gym in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: VenueCard(
                      venue: gym,
                      placeholderIcon: Icons.fitness_center_rounded,
                      onTap: () => context.push(GymRoutes.gymFor(gym.id)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A gym's page: photos, plans and prices, how to pay, reviews; joining or
/// renewing a plan.
class GymDetailsScreen extends ConsumerWidget {
  final String venueId;

  const GymDetailsScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venue = ref.watch(venueProvider(venueId));
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final mine = signedIn
        ? (ref.watch(mySubscriptionsProvider).valueOrNull ?? const <GymSubscription>[])
            .where((s) => s.venueId == venueId)
            .toList()
        : const <GymSubscription>[];
    final access = signedIn ? ref.watch(venueAccessProvider(venueId)).valueOrNull : null;
    final today = BhutanTime.today();
    final pending = mine.where((s) => s.isPending).firstOrNull;
    final current = mine.where((s) => s.isCurrentOn(today) || s.isUpcomingOn(today)).toList()
      ..sort((a, b) => b.endDate!.compareTo(a.endDate!));

    return AppPage(
      title: venue.valueOrNull?.name ?? 'Gym',
      actions: [
        if (access != null)
          TextButton.icon(
            onPressed: () => context.push(CoreRoutes.venueManageFor(venueId)),
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: const Text('Manage'),
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
              ref.invalidate(mySubscriptionsProvider);
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
                for (final s in current)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: MenuTile(
                      icon: Icons.verified_user_outlined,
                      iconColor: context.brand.success,
                      title: s.isUpcomingOn(today) ? 'Renewed: ${s.planName}' : "You're a member: ${s.planName}",
                      subtitle: '${formatDate(s.startDate!)} to ${formatDate(s.endDate!)}',
                      trailing: SubscriptionStatusChip(subscription: s),
                      onTap: () => context.push(GymRoutes.myGym),
                    ),
                  ),
                if (pending != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _PendingRequestCard(subscription: pending, paymentInfo: gym.paymentInfo),
                  ),
                const SectionTitle('Membership plans'),
                AsyncValueView<List<GymPlan>>(
                  value: plans,
                  onRetry: () => ref.invalidate(gymPlansProvider((venueId: venueId, all: false))),
                  data: (list) => list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('This gym has not added its plans yet.'),
                        )
                      : Column(
                          children: [
                            for (final plan in list)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: PlanCard(
                                  plan: plan,
                                  actionLabel: current.isEmpty ? 'Join' : 'Renew',
                                  onAction: pending != null || !gym.isVerified
                                      ? null
                                      : () => _join(context, ref, gym, plan, renewing: current.isNotEmpty),
                                ),
                              ),
                          ],
                        ),
                ),
                if (gym.paymentInfo != null) ...[
                  const SectionTitle('How to pay'),
                  SectionCard(child: InfoRow(icon: Icons.account_balance_wallet_outlined, text: gym.paymentInfo!)),
                ],
                if (gym.cancellationPolicy != null) ...[
                  const SectionTitle('Cancellation and refunds'),
                  SectionCard(child: Text(gym.cancellationPolicy!)),
                ],
                ReviewsSection(venue: gym),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref, Venue gym, GymPlan plan, {required bool renewing}) async {
    if (ref.read(currentUserIdProvider) == null) {
      context.push(CoreRoutes.signInFor(GymRoutes.gymFor(gym.id)));
      return;
    }
    final sure = await confirmAction(
      context,
      title: '${renewing ? 'Renew with' : 'Join'} ${plan.name}?',
      message: '${plan.price == 0 ? 'Free' : formatNu(plan.price)} for ${formatDuration(plan.durationDays)}.\n\n'
          'Pay ${gym.name} by mBoB or cash. Their staff activate your membership once they have the payment'
          '${renewing ? ', and it starts when your current one ends' : ''}.',
      confirmLabel: 'Send request',
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).requestSubscription(plan.id),
      success: 'Request sent to ${gym.name}',
    );
    if (ok) ref.invalidate(mySubscriptionsProvider);
  }
}

class _PendingRequestCard extends ConsumerWidget {
  final GymSubscription subscription;
  final String? paymentInfo;

  const _PendingRequestCard({required this.subscription, this.paymentInfo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = subscription;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Your request: ${s.planName}', style: context.text.titleMedium)),
              SubscriptionStatusChip(subscription: s),
            ],
          ),
          const SizedBox(height: 8),
          Text('Pay ${s.price == 0 ? 'nothing' : formatNu(s.price)} to the gym. Their staff activate your membership '
              "once they have it; you'll get a notification."),
          if (paymentInfo != null) ...[const SizedBox(height: 6), Text(paymentInfo!, style: const TextStyle(fontWeight: FontWeight.w600))],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _cancel(context, ref),
              child: const Text('Cancel request'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final sure = await confirmAction(context, title: 'Cancel this request?', confirmLabel: 'Cancel request', cancelLabel: 'Keep it');
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymRepositoryProvider).cancelSubscription(subscription.id));
    if (ok) ref.invalidate(mySubscriptionsProvider);
  }
}

/// The member's page: their card (QR code and member code), memberships at
/// every gym, requests, history and recent check-ins.
class MyGymScreen extends ConsumerWidget {
  const MyGymScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final checkIns = ref.watch(myCheckInsProvider).valueOrNull ?? const <GymCheckIn>[];
    final today = BhutanTime.today();
    return AppPage(
      title: 'My gym',
      body: AsyncValueView<List<GymSubscription>>(
        value: ref.watch(mySubscriptionsProvider),
        onRetry: () => ref.invalidate(mySubscriptionsProvider),
        data: (subs) {
          final now = subs.where((s) => s.isCurrentOn(today) || s.isUpcomingOn(today) || s.isPending).toList();
          final history = subs.where((s) => !now.contains(s)).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(mySubscriptionsProvider);
              ref.invalidate(myCheckInsProvider);
            },
            child: ListView(
              padding: pagePadding(context),
              children: [
                if (profile != null) MemberCard(memberId: profile.id, name: profile.displayName, code: profile.memberCode),
                const SectionTitle('Memberships'),
                if (now.isEmpty)
                  SectionCard(
                    child: Column(
                      children: [
                        const Text("You don't have a membership right now."),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => context.push(GymRoutes.gyms),
                          icon: const Icon(Icons.fitness_center_rounded),
                          label: const Text('Find a gym'),
                        ),
                      ],
                    ),
                  ),
                for (final s in now)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: _MembershipCard(subscription: s)),
                if (checkIns.isNotEmpty) ...[
                  const SectionTitle('Recent check-ins'),
                  Card(
                    child: Column(
                      children: [
                        for (final c in checkIns.take(10))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.login_rounded),
                            title: Text(c.gymName ?? 'Gym'),
                            trailing: Text(formatMoment(c.checkedInAt)),
                          ),
                      ],
                    ),
                  ),
                ],
                if (history.isNotEmpty) ...[
                  const SectionTitle('History'),
                  for (final s in history)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: _MembershipCard(subscription: s)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The member's card: a QR code the gym's staff scan at check-in, and the
/// code they can type instead.
class MemberCard extends StatelessWidget {
  final String memberId;
  final String name;
  final String code;

  const MemberCard({super.key, required this.memberId, required this.name, required this.code});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [BrandColors.navy, BrandColors.blue], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center_rounded, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('SportsHub member', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Text(name, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(
                data: MemberQr.encode(memberId),
                size: 200,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
                semanticsLabel: 'Your member QR code',
              ),
            ),
            const SizedBox(height: 14),
            Text(
              code,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6),
            ),
            const SizedBox(height: 4),
            Text(
              'Show this at the front desk, or tell them your code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipCard extends ConsumerWidget {
  final GymSubscription subscription;

  const _MembershipCard({required this.subscription});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = subscription;
    final today = BhutanTime.today();
    return SectionCard(
      onTap: () => context.push(GymRoutes.gymFor(s.venueId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.gymName ?? 'Gym', style: context.text.titleMedium)),
              SubscriptionStatusChip(subscription: s),
            ],
          ),
          const SizedBox(height: 4),
          Text('${s.planName} · ${formatDuration(s.durationDays)} · ${s.price == 0 ? 'Free' : formatNu(s.price)}',
              style: TextStyle(color: context.brand.muted)),
          if (s.startDate != null) ...[
            const SizedBox(height: 4),
            Text('${formatDate(s.startDate!)} to ${formatDate(s.endDate!)}'),
          ],
          if (s.isCurrentOn(today)) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: s.progressOn(today), minHeight: 6, color: context.brand.accent),
            ),
          ],
          if (s.isPending) ...[
            const SizedBox(height: 6),
            const Text('Pay the gym; their staff activate it once they have the payment.'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final sure = await confirmAction(context,
                      title: 'Cancel this request?', confirmLabel: 'Cancel request', cancelLabel: 'Keep it');
                  if (!sure || !context.mounted) return;
                  final ok = await runAction(context, () => ref.read(gymRepositoryProvider).cancelSubscription(s.id));
                  if (ok) ref.invalidate(mySubscriptionsProvider);
                },
                child: const Text('Cancel request'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
