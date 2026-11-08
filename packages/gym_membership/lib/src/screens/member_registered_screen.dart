import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/registered_member.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';
import '../widgets/member_card.dart';
import '../widgets/member_photo.dart';
import 'members_screens.dart';

/// Straight after the front desk registers a member: it's done, the package
/// sold and its expiry date, their details to check, and their QR card to
/// download or send on WhatsApp. Then the next member.
class MemberRegisteredScreen extends ConsumerWidget {
  final String venueId;
  final String memberId;

  const MemberRegisteredScreen({super.key, required this.venueId, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Member registered',
      permission: GymPermission.members,
      builder: (context, access) => AsyncValueView<GymMember?>(
        value: ref.watch(gymMemberProvider(memberId)),
        onRetry: () => ref.invalidate(gymMemberProvider(memberId)),
        data: (m) => m == null || m.venueId != venueId
            ? const AppPage(
                title: 'Member registered',
                body: EmptyState(icon: Icons.person_off_outlined, title: 'This member is not registered here'),
              )
            : _Registered(member: m, access: access),
      ),
    );
  }
}

class _Registered extends ConsumerWidget {
  final GymMember member;
  final VenueAccess access;

  const _Registered({required this.member, required this.access});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = member;
    final id = access.venue.id;
    final today = BhutanTime.today();
    final all = ref.watch(gymSubscriptionsProvider(id));
    final subs = membershipsOf(all.valueOrNull ?? const <GymSubscription>[], m.id);
    final until = paidUntil(subs, today);
    // The package sold with the registration: their first.
    final sold = subs.where((s) => s.startDate != null && s.status != SubscriptionStatus.cancelled).lastOrNull;
    final loading = !all.hasValue;

    final banner = _Banner(
      member: m,
      message: loading
          ? 'Member code ${m.code}.'
          : sold == null
              ? "Member code ${m.code}. They can't check in until they have a package."
              : 'Member code ${m.code}. Send them their QR card: they show it at the counter each time they come in.',
    );

    final package = SectionCard(
      padding: const EdgeInsets.all(18),
      child: loading
          ? const Center(child: SportsHubLoader(size: 40, semanticsLabel: 'Loading their package'))
          : sold == null
              ? _NoPackage(onSell: access.can(GymPermission.payments) ? () => context.go(GymRoutes.memberFor(id, m.id)) : null)
              : _PackageSummary(sold: sold, subs: subs, today: today),
    );

    final card = MemberCardPanel(
      gymName: access.venue.name,
      member: m,
      until: until,
      noPackage: packageLine(subs, today),
    );

    final next = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (access.can(GymPermission.register))
          FilledButton.icon(
            onPressed: () => context.go(GymRoutes.registerMemberFor(id)),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Register another'),
          ),
        OutlinedButton.icon(
          onPressed: () => context.go(GymRoutes.memberFor(id, m.id)),
          icon: const Icon(Icons.badge_outlined),
          label: const Text('Open their page'),
        ),
        TextButton(onPressed: () => context.go(GymRoutes.membersFor(id)), child: const Text('All members')),
      ],
    );

    final cardSection = [const SectionTitle('QR member card'), card];
    final rest = [
      const SectionTitle('Package'),
      package,
      const SectionTitle('Their details'),
      if (m.medicalNotes != null) ...[MedicalNotice(m.medicalNotes!), const SizedBox(height: 12)],
      MemberDetailsCard(member: m, withPhone: true),
      const SizedBox(height: 24),
      next,
    ];

    return AppPage(
      title: 'Member registered',
      body: ListView(
        padding: pagePadding(context),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // On a phone the card comes straight after the news: it's what
              // the desk does next.
              if (constraints.maxWidth < 1000) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [banner, ...cardSection, ...rest],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [banner, ...rest]),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cardSection),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Registered: who, with a tick.
class _Banner extends StatelessWidget {
  final GymMember member;
  final String message;

  const _Banner({required this.member, required this.message});

  @override
  Widget build(BuildContext context) {
    final success = context.brand.success;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              MemberPhoto(path: member.photoPath, name: member.fullName, size: 72),
              Positioned(
                right: -6,
                bottom: -6,
                child: Container(
                  decoration: BoxDecoration(color: success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${member.fullName} is registered', style: context.text.titleLarge),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The package: when it starts, its expiry date and what they paid.
class _PackageSummary extends StatelessWidget {
  final GymSubscription sold;
  final List<GymSubscription> subs;
  final DateTime today;

  const _PackageSummary({required this.sold, required this.subs, required this.today});

  @override
  Widget build(BuildContext context) {
    final until = paidUntil(subs, today);
    final ended = sold.endDate!.isBefore(today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(sold.planName, style: context.text.titleMedium)),
            StandingChip(
              standing: standingOf(subs, today),
              daysLeft: until == null ? null : BhutanTime.daysBetween(today, until) + 1,
            ),
          ],
        ),
        const SizedBox(height: 14),
        ResponsiveGrid(
          minItemWidth: 150,
          maxColumns: 3,
          spacing: 12,
          runSpacing: 12,
          equalHeight: false,
          children: [
            _Fact(label: 'Starts', value: formatDate(sold.startDate!)),
            _Fact(label: 'Expiry date', value: formatDate(sold.endDate!), color: ended ? context.brand.danger : context.brand.success),
            _Fact(label: 'Paid', value: sold.price == 0 ? 'Nothing' : formatNu(sold.price)),
          ],
        ),
        if (ended) ...[
          const SizedBox(height: 10),
          const FormHint('This package had already ended: renew it on their page before they come in.'),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Fact({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: (color ?? context.colors.onSurface).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.brand.muted, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
        ],
      ),
    );
  }
}

/// Registered without a package (their role can't take payments, or they
/// pay later).
class _NoPackage extends StatelessWidget {
  final VoidCallback? onSell;

  const _NoPackage({this.onSell});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, color: context.brand.warning),
        const SizedBox(width: 12),
        Expanded(
          child: Text(onSell == null
              ? 'No package yet. Someone who takes payments adds one on their page.'
              : 'No package yet. Sell them one on their page.'),
        ),
        if (onSell != null) ...[
          const SizedBox(width: 12),
          FilledButton.tonal(onPressed: onSell, child: const Text('Sell a package')),
        ],
      ],
    );
  }
}
