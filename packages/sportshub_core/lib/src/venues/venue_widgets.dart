import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/formatters.dart';
import '../utils/launch.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import 'venue.dart';
import 'venue_repository.dart';

/// A venue in a list: cover photo, name, place and rating.
class VenueCard extends StatelessWidget {
  final Venue venue;
  final IconData placeholderIcon;
  final VoidCallback onTap;
  final Widget? trailing;

  const VenueCard({super.key, required this.venue, required this.onTap, this.placeholderIcon = Icons.storefront_rounded, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 7,
              child: venue.coverPhoto == null
                  ? _PhotoPlaceholder(icon: placeholderIcon)
                  : Image.network(venue.coverPhoto!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _PhotoPlaceholder(icon: placeholderIcon)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(venue.name, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.place_outlined, size: 16, color: context.brand.muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(venue.place,
                                  style: TextStyle(color: context.brand.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            if (venue.ratingCount > 0) ...[
                              const SizedBox(width: 10),
                              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5A623)),
                              Text(' ${venue.ratingAverage!.toStringAsFixed(1)} (${venue.ratingCount})'),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  final IconData icon;

  const _PhotoPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [context.colors.primary.withValues(alpha: 0.85), context.colors.tertiary.withValues(alpha: 0.85)],
        ),
      ),
      child: Center(child: Icon(icon, size: 48, color: Colors.white.withValues(alpha: 0.9))),
    );
  }
}

/// Pending, verified or sent back.
class VerificationChip extends StatelessWidget {
  final String status;

  const VerificationChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return switch (status) {
      VerificationStatus.verified => StatusChip(label: 'Verified', color: brand.success, icon: Icons.verified_rounded),
      VerificationStatus.rejected => StatusChip(label: 'Sent back', color: brand.danger, icon: Icons.undo_rounded),
      _ => StatusChip(label: 'Waiting for verification', color: brand.warning, icon: Icons.hourglass_top_rounded),
    };
  }
}

/// A venue's photos, swiped through.
class VenuePhotoCarousel extends StatefulWidget {
  final List<String> photos;
  final IconData placeholderIcon;

  const VenuePhotoCarousel({super.key, required this.photos, this.placeholderIcon = Icons.storefront_rounded});

  @override
  State<VenuePhotoCarousel> createState() => _VenuePhotoCarouselState();
}

class _VenuePhotoCarouselState extends State<VenuePhotoCarousel> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: photos.isEmpty
            ? _PhotoPlaceholder(icon: widget.placeholderIcon)
            : Stack(
                children: [
                  PageView.builder(
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => Image.network(photos[i], fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _PhotoPlaceholder(icon: widget.placeholderIcon)),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < photos.length; i++)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _page ? 18 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: i == _page ? 1 : 0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Call, WhatsApp and directions, for whichever the venue has.
class VenueContactButtons extends StatelessWidget {
  final Venue venue;

  const VenueContactButtons({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final buttons = [
      if (venue.phone != null)
        OutlinedButton.icon(
          onPressed: () => callPhone(context, venue.phone!),
          icon: const Icon(Icons.call_outlined),
          label: const Text('Call'),
        ),
      if (venue.whatsapp != null)
        OutlinedButton.icon(
          onPressed: () => openWhatsApp(context, venue.whatsapp!),
          icon: const Icon(Icons.chat_outlined),
          label: const Text('WhatsApp'),
        ),
      if (venue.hasLocation)
        OutlinedButton.icon(
          onPressed: () => openDirections(context, venue.latitude!, venue.longitude!),
          icon: const Icon(Icons.directions_outlined),
          label: const Text('Directions'),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }
}

/// Ratings and comments, and writing one (for people who've used the venue).
class ReviewsSection extends ConsumerWidget {
  final Venue venue;

  const ReviewsSection({super.key, required this.venue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    final reviews = ref.watch(venueReviewsProvider(venue.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          venue.ratingCount == 0 ? 'Reviews' : 'Reviews · ${venue.ratingAverage!.toStringAsFixed(1)} ★ (${venue.ratingCount})',
          trailing: TextButton.icon(
            icon: const Icon(Icons.rate_review_outlined, size: 18),
            label: const Text('Write one'),
            onPressed: () => userId == null
                ? context.push(CoreRoutes.signInFor(GoRouterState.of(context).uri.toString()))
                : _write(context, ref, reviews.valueOrNull?.where((r) => r.userId == userId).firstOrNull),
          ),
        ),
        AsyncValueView<List<VenueReview>>(
          value: reviews,
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('No reviews yet.', style: TextStyle(color: context.brand.muted)),
                )
              : Column(
                  children: [
                    for (final r in list.take(10))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SectionCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(r.reviewerName, style: const TextStyle(fontWeight: FontWeight.w700))),
                                  RatingStars(rating: r.rating.toDouble()),
                                ],
                              ),
                              if (r.comment != null && r.comment!.isNotEmpty) ...[const SizedBox(height: 6), Text(r.comment!)],
                              const SizedBox(height: 4),
                              Text(formatDate(r.createdAt), style: context.text.bodySmall?.copyWith(color: context.brand.muted)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _write(BuildContext context, WidgetRef ref, VenueReview? mine) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(venue: venue, mine: mine),
    );
    if (saved ?? false) {
      ref.invalidate(venueReviewsProvider(venue.id));
      ref.invalidate(venueProvider(venue.id));
    }
  }
}

class _ReviewSheet extends ConsumerStatefulWidget {
  final Venue venue;
  final VenueReview? mine;

  const _ReviewSheet({required this.venue, this.mine});

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late int _rating = widget.mine?.rating ?? 0;
  late final _comment = TextEditingController(text: widget.mine?.comment ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(venueRepositoryProvider).saveReview(widget.venue.id, _rating, _comment.text.trim()),
      success: 'Thanks for your review',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Rate ${widget.venue.name}', style: context.text.titleLarge),
          const SizedBox(height: 4),
          Text('Only members who have used it can review it.', style: TextStyle(color: context.brand.muted)),
          const SizedBox(height: 12),
          RatingPicker(value: _rating, onChanged: (v) => setState(() => _rating = v)),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            maxLines: 4,
            minLines: 2,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'What was it like? (optional)'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _rating == 0 || _busy ? null : _save, child: const Text('Post review')),
        ],
      ),
    );
  }
}
