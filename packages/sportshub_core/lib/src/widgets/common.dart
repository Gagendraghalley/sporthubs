import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/brand.dart';
import '../utils/friendly_error.dart';
import 'motion.dart';

/// Loading (the shape of the page, shimmering), error (with Try again) and
/// data, for an [AsyncValue]; the data fades in.
class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  /// While it loads: a page's shape unless given ([LoadingSkeleton.rows] for
  /// a list inside a page).
  final Widget? loading;

  const AsyncValueView({super.key, required this.value, required this.data, this.onRetry, this.loading});

  @override
  Widget build(BuildContext context) {
    final content = value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (item) => KeyedSubtree(key: const ValueKey('async-data'), child: data(item)),
      loading: () => KeyedSubtree(key: const ValueKey('async-loading'), child: loading ?? const LoadingSkeleton()),
      error: (e, _) => KeyedSubtree(
        key: const ValueKey('async-error'),
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load this',
          message: friendlyError(e),
          actionLabel: onRetry == null ? null : 'Try again',
          onAction: onRetry,
        ),
      ),
    );
    if (reduceMotion(context)) return content;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: content,
    );
  }
}

/// A friendly message where a list or page has nothing to show.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    final blue = context.colors.tertiary;
    return Center(
      child: FadeSlideIn(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Two soft rings around the icon.
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [blue.withValues(alpha: 0.12), blue.withValues(alpha: 0.02)]),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [accent.withValues(alpha: 0.18), blue.withValues(alpha: 0.18)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(icon, size: 34, color: context.colors.primary),
                  ),
                ),
                const SizedBox(height: 18),
                Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    style: context.text.bodyMedium?.copyWith(color: context.brand.muted, height: 1.45),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    iconAlignment: IconAlignment.end,
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small coloured label: 'Active', 'Pending', 'Verified'.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusChip({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// A heading above a group on a page, with an optional action at the end.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: context.text.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A card with padding: the building block of every page.
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    // One that opens lifts under the mouse.
    return onTap == null ? card : HoverLift(radius: 16, child: card);
  }
}

/// A tappable row in a card: icon, title, subtitle and a chevron.
class MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;

  const MenuTile({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? context.colors.primary;
    final end = trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right_rounded));
    // A Row, not a ListTile: a ListTile measures a wrapping subtitle as if it
    // had the whole width, so in an equal-height ResponsiveGrid the card came
    // out too short and the second line spilled out of it.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (end != null) ...[const SizedBox(width: 12), end],
            ],
          ),
        ),
      ),
    );
  }
}

/// A number with its label, for dashboards.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const StatTile({super.key, required this.label, required this.value, required this.icon, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return SectionCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c),
          const SizedBox(height: 10),
          Text(value, style: context.text.headlineSmall?.copyWith(color: c)),
          const SizedBox(height: 2),
          Text(label, style: context.text.bodySmall?.copyWith(color: context.brand.muted), maxLines: 2),
        ],
      ),
    );
  }
}

/// A row of label and value, for details.
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const InfoRow({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.brand.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
