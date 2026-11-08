import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notifications_screen.dart';
import '../shell/account_menu.dart';
import '../shell/app_shell.dart';
import '../shell/service_nav.dart';
import '../theme/brand.dart';

/// Every page's frame: a frosted-glass app bar with the page blurred behind
/// it as it scrolls, over SportsHub's soft background. The content uses the
/// window's width (up to [wideWidth], so very wide screens stay readable);
/// pages lay themselves out for it with [ResponsiveGrid] and
/// [ResponsiveColumns]. Short forms pass [maxWidth] = [readableWidth].
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

  /// How wide the content may grow: [wideWidth] unless given.
  final double? maxWidth;

  const AppPage({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    required this.body,
    this.floatingActionButton,
    this.bottomBar,
    this.maxWidth,
  });

  /// Most pages: the whole window, up to this.
  static const wideWidth = 1600.0;

  /// A short form or a page of text: a column that's comfortable to read.
  static const readableWidth = 760.0;

  @override
  Widget build(BuildContext context) {
    // In the app's frame on a phone, a page with nothing to go back to opens
    // the menu from its bar. In the frame (signed in), the bar ends with
    // their notifications and account.
    final scope = AppShellScope.maybeOf(context);
    final openMenu = scope?.openMenu;
    final service = scope?.service;
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;
    final lead = leading ??
        (openMenu != null && !canGoBack
            ? IconButton(tooltip: 'Menu', icon: const Icon(Icons.menu_rounded), onPressed: openMenu)
            : null);
    // A service's page: its name over the title, and its shortcuts.
    final Widget? heading = titleWidget ??
        (title == null
            ? null
            : service == null
                ? Text(title!)
                : _ServiceTitle(service: service, title: title!));
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: GlassAppBar(
        title: heading,
        actions: [
          ...?actions,
          if (service != null && service.actions.isNotEmpty) ServiceActionsButton(service: service),
          if (scope != null) ...[const SizedBox(width: 4), const NotificationBell(), const AccountButton()],
        ],
        leading: lead,
      ),
      body: BrandBackdrop(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth ?? wideWidth), child: body),
        ),
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar == null ? null : GlassBar(child: SafeArea(top: false, child: bottomBar!)),
    );
  }
}

/// A service page's title: the service's name small above it, by a dot of
/// its colour.
class _ServiceTitle extends StatelessWidget {
  final ServiceNav service;
  final String title;

  const _ServiceTitle({required this.service, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: service.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                service.scope == null ? service.name : '${service.name} · ${service.scope!.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.brand.muted, letterSpacing: 0.2),
              ),
            ),
          ],
        ),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// New: the shortcuts of the service the page belongs to (Register member,
/// Check in...). A labelled button on a computer, an icon on a phone.
class ServiceActionsButton extends StatelessWidget {
  final ServiceNav service;

  const ServiceActionsButton({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: context.brand.glassBorder)),
        ),
      ),
      menuChildren: [
        for (final a in service.actions)
          MenuItemButton(
            leadingIcon: Icon(a.icon, size: 20, color: service.color),
            onPressed: () => GoRouter.of(context).go(a.route),
            child: Padding(padding: const EdgeInsets.only(right: 16), child: Text(a.label)),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        if (!wide) {
          return IconButton(tooltip: 'New', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: toggle);
        }
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: FilledButton.icon(
            onPressed: toggle,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('New'),
          ),
        );
      },
    );
  }
}

/// Room for the bars above and below a scrolling page, plus a gutter.
///
/// Works from either side of the [AppPage]: a screen building one has a
/// [context] above its Scaffold, whose padding doesn't count the app bar yet;
/// a widget inside the body already has the app bar in its padding.
/// The gutter grows on wide windows (28) from a phone's (16), unless
/// [horizontal] is given.
EdgeInsets pagePadding(BuildContext context, {double? horizontal, double top = 12, double bottom = 24}) {
  final insets = MediaQuery.paddingOf(context);
  final appBar = context.findAncestorWidgetOfExactType<AppPage>() == null ? kToolbarHeight : 0.0;
  final gutter = horizontal ?? (MediaQuery.sizeOf(context).width >= 900 ? 28.0 : 16.0);
  return EdgeInsets.fromLTRB(gutter, insets.top + appBar + top, gutter, insets.bottom + bottom);
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
