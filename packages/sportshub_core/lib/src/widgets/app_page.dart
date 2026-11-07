import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// Every page's frame: a frosted-glass app bar with the page blurred behind
/// it as it scrolls, over SportsHub's soft background. Wide windows (the
/// website) keep the content in a readable column.
///
/// Scrolling bodies should use [pagePadding] so their first and last items
/// clear the bars.
class AppPage extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomBar;

  const AppPage({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    required this.body,
    this.floatingActionButton,
    this.bottomBar,
  });

  static const maxContentWidth = 760.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: GlassAppBar(title: titleWidget ?? (title == null ? null : Text(title!)), actions: actions, leading: leading),
      body: BrandBackdrop(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxContentWidth), child: body),
        ),
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar == null ? null : GlassBar(child: SafeArea(top: false, child: bottomBar!)),
    );
  }
}

/// Room for the bars above and below a scrolling page, plus a gutter.
EdgeInsets pagePadding(BuildContext context, {double horizontal = 16, double top = 12, double bottom = 24}) {
  final insets = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(horizontal, insets.top + top, horizontal, insets.bottom + bottom);
}

/// A translucent app bar that blurs what scrolls under it.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;

  const GlassAppBar({super.key, this.title, this.actions, this.leading});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      actions: [...?actions, const SizedBox(width: 8)],
      flexibleSpace: GlassBar(border: Border(bottom: BorderSide(color: context.brand.glassBorder))),
    );
  }
}

/// Frosted glass: the page behind is blurred and lightened (or darkened).
class GlassBar extends StatelessWidget {
  final Widget? child;
  final BoxBorder? border;

  const GlassBar({super.key, this.child, this.border});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: brand.glass,
            border: border ?? Border(top: BorderSide(color: brand.glassBorder)),
          ),
          child: child ?? const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// The soft background: the page colour with two wide glows, navy-blue and
/// orange, for the glass to blur.
class BrandBackdrop extends StatelessWidget {
  final Widget child;

  const BrandBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DecoratedBox(
      decoration: BoxDecoration(color: brand.background),
      child: Stack(
        children: [
          Positioned(top: -140, right: -120, child: _Glow(color: brand.glowA, size: 420)),
          Positioned(bottom: -160, left: -140, child: _Glow(color: brand.glowB, size: 460)),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
