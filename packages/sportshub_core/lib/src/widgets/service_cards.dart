import 'package:flutter/material.dart';

import '../shell/platform_shell.dart';
import '../shell/service_nav.dart';
import '../theme/brand.dart';
import 'motion.dart';

// The pieces every service's card is made of, on Overview and My services:
// the card itself, its numbers, and shortcuts.

/// A service at a glance: its icon and name, a [status], what it has to show
/// ([child]), and the ways in ([actions]). Lifts under the mouse when it
/// opens ([onOpen]).
class ServiceCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name;
  final String? subtitle;
  final Widget? status;
  final Widget? child;
  final List<Widget> actions;
  final VoidCallback? onOpen;

  const ServiceCard({
    super.key,
    required this.icon,
    required this.color,
    required this.name,
    this.subtitle,
    this.status,
    this.child,
    this.actions = const [],
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF111A2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.glassBorder),
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : BrandColors.navy).withValues(alpha: dark ? 0.25 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A thin band of the service's colour along the top.
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.35)]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ServiceIconTile(icon: icon, color: color, filled: true, size: 44),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (subtitle != null)
                                Text(subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: brand.muted, fontSize: 13)),
                            ],
                          ),
                        ),
                        if (status != null) ...[const SizedBox(width: 8), status!],
                      ],
                    ),
                    if (child != null) ...[const SizedBox(height: 18), child!],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return HoverLift(enabled: onOpen != null, child: card);
  }
}

/// A number on a service's card: it counts up, its [label] under it.
class ServiceStat extends StatelessWidget {
  final String label;
  final num value;
  final String Function(num)? format;
  final Color? color;

  const ServiceStat({super.key, required this.label, required this.value, this.format, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedCount(
              value: value,
              format: format ?? AnimatedCount.whole,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.colors.onSurface, height: 1.15),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.brand.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// [stats] side by side, two to four to a row as the card allows.
class ServiceStats extends StatelessWidget {
  final List<Widget> stats;

  const ServiceStats({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 4 : 2;
        final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final s in stats) SizedBox(width: width.floorToDouble(), child: s)],
        );
      },
    );
  }
}

/// A shortcut on Overview: its icon on a tile of the service's [color], what
/// it does, and which service.
class QuickActionTile extends StatelessWidget {
  final ServiceAction action;
  final Color color;
  final String? service;
  final VoidCallback onTap;

  const QuickActionTile({super.key, required this.action, required this.color, required this.onTap, this.service});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return HoverLift(
      radius: 16,
      child: Material(
        color: dark ? const Color(0xFF111A2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: brand.glassBorder)),
            child: Row(
              children: [
                ServiceIconTile(icon: action.icon, color: color, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      if (action.hint != null || service != null)
                        Text(action.hint ?? service!,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 18, color: brand.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
