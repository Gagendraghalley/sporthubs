import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/access_repository.dart';
import '../admin/admin_repository.dart';
import '../auth/auth_repository.dart';
import '../notifications/notification_repository.dart';
import '../profiles/profile_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../theme/theme_mode.dart';
import '../utils/launch.dart';
import '../widgets/logo.dart';
import '../widgets/motion.dart';
import 'app_shell.dart';
import 'service_nav.dart';

/// Widths at which the menu shows beside the page; under it, a drawer.
const sideMenuFrom = 1100.0;

/// The side menu's widths: open, and folded to its icons.
const sideMenuWidth = 276.0;
const sideMenuFoldedWidth = 84.0;

/// The platform's frame around every signed-in page: one menu down the side
/// (a drawer on a phone, foldable to icons on a computer), the page beside
/// it.
///
/// The menu is made of services, not features: the platform's own pages
/// (Overview, My services, Notifications), then a section per service, each
/// with its icon, what it's working on (a gym of several) and its pages,
/// then Administration for the SportsHub team, then who is signed in. The
/// section of the page being used opens; the others fold to one line, so
/// twenty services stay one short list.
class PlatformShell extends ConsumerStatefulWidget {
  /// The page's path, for the menu to mark it.
  final String location;
  final Widget child;

  const PlatformShell({super.key, required this.location, required this.child});

  @override
  ConsumerState<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends ConsumerState<PlatformShell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  /// A section opened (or closed, with null) by hand since the last page.
  String? _opened;
  bool _openedByHand = false;

  /// The last service a page was in, kept open on the platform's own pages.
  String? _lastService;

  @override
  void didUpdateWidget(PlatformShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _openedByHand = false;
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final services = serviceNavs(ref, location);
    final admin = adminNav(ref.watch(myAccessProvider).valueOrNull ?? PlatformAccess.none,
        pending: ref.watch(_pendingCountProvider));
    final active = [
      for (final s in services)
        if (s.nav.isOpenAt(location) || s.module.ownsPath(location)) s.nav,
      if (admin != null && admin.isOpenAt(location)) admin,
    ].firstOrNull;
    if (active != null) _lastService = active.key;
    final open = _openedByHand
        ? _opened
        : active?.key ?? _lastService ?? (services.length == 1 ? services.first.nav.key : null);

    final beside = MediaQuery.sizeOf(context).width >= sideMenuFrom;
    final folded = beside && ref.watch(sideMenuCollapsedProvider);
    Widget menu({required bool inDrawer}) => PlatformSidebar(
          location: location,
          services: [for (final s in services) s.nav],
          admin: admin,
          openSection: open,
          inDrawer: inDrawer,
          onToggleSection: (key) => setState(() {
            _openedByHand = true;
            _opened = open == key ? null : key;
          }),
          onFold: inDrawer ? null : () => ref.read(sideMenuCollapsedProvider.notifier).toggle(),
        );

    return Scaffold(
      key: _scaffold,
      backgroundColor: context.brand.background,
      drawer: beside ? null : Drawer(width: 300, child: menu(inDrawer: true)),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (beside)
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: folded ? sideMenuFoldedWidth : sideMenuWidth,
              child: menu(inDrawer: false),
            ),
          Expanded(
            child: AppShellScope(
              openMenu: beside ? null : () => _scaffold.currentState?.openDrawer(),
              service: active,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Venues waiting for the team to verify them, for those who verify.
final _pendingCountProvider = Provider<int>((ref) {
  final access = ref.watch(myAccessProvider).valueOrNull ?? PlatformAccess.none;
  if (!access.can(PlatformPermission.venuesVerify)) return 0;
  return ref.watch(pendingVenuesProvider).valueOrNull?.length ?? 0;
});

/// The SportsHub team's pages, as a section like a service's: what [access]
/// allows. Null for those not on the team.
ServiceNav? adminNav(PlatformAccess access, {int pending = 0}) {
  if (!access.isTeam) return null;
  return ServiceNav(
    key: 'platform_admin',
    name: 'SportsHub admin',
    icon: Icons.admin_panel_settings_rounded,
    color: BrandColors.blue,
    tagline: access.isSuperAdmin ? 'Super admin' : 'SportsHub team',
    homeRoute: CoreRoutes.admin,
    sections: [
      NavSection(items: [
        const NavDestination(label: 'Admin home', icon: Icons.home_work_outlined, route: CoreRoutes.admin, exact: true),
        if (access.can(PlatformPermission.users))
          const NavDestination(label: 'Users', icon: Icons.people_alt_outlined, route: CoreRoutes.adminUsers),
        if (access.can(PlatformPermission.roles))
          const NavDestination(label: 'Roles & permissions', icon: Icons.verified_user_outlined, route: CoreRoutes.adminRoles),
        if (access.can(PlatformPermission.venuesVerify))
          NavDestination(
              label: 'Venues to verify', icon: Icons.fact_check_outlined, route: CoreRoutes.adminVenues, badge: pending),
        if (access.can(PlatformPermission.masters))
          const NavDestination(label: 'Master data', icon: Icons.account_tree_outlined, route: CoreRoutes.adminMasters),
        if (access.can(PlatformPermission.modules))
          const NavDestination(label: 'Services on/off', icon: Icons.toggle_on_outlined, route: CoreRoutes.adminModules),
      ]),
    ],
  );
}

/// The menu itself: the logo, the platform's pages, each service's section,
/// Administration, and who is signed in. Navy in both themes.
class PlatformSidebar extends ConsumerStatefulWidget {
  final String location;
  final List<ServiceNav> services;
  final ServiceNav? admin;

  /// The key of the section that's open.
  final String? openSection;
  final ValueChanged<String> onToggleSection;

  /// In the phone's drawer, which closes before a page opens.
  final bool inDrawer;

  /// Folds the menu to its icons and back; null for no button (a drawer).
  final VoidCallback? onFold;

  const PlatformSidebar({
    super.key,
    required this.location,
    required this.services,
    required this.openSection,
    required this.onToggleSection,
    this.admin,
    this.inDrawer = false,
    this.onFold,
  });

  /// Whether the menu around [context] shows only icons.
  static bool isFolded(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Folded>()?.folded ?? false;

  @override
  ConsumerState<PlatformSidebar> createState() => _PlatformSidebarState();
}

class _PlatformSidebarState extends ConsumerState<PlatformSidebar> {
  /// With many services, a box to find one.
  static const _findFrom = 7;
  String _find = '';

  void _open(String route) {
    if (widget.inDrawer) Navigator.of(context).pop();
    context.go(route);
  }

  void _external(Uri url) {
    if (widget.inDrawer) Navigator.of(context).pop();
    openExternal(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final unread = ref.watch(unreadCountProvider);
    final services = _find.isEmpty
        ? widget.services
        : widget.services.where((s) => s.name.toLowerCase().contains(_find.toLowerCase())).toList();

    Widget section(ServiceNav nav) => ServiceSection(
          nav: nav,
          location: location,
          open: widget.openSection == nav.key,
          onToggle: () => widget.onToggleSection(nav.key),
          onOpen: _open,
          onExternal: _external,
        );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0C2152), BrandColors.night],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        right: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Folded, or folding: icons only, their names as tooltips.
            final folded = constraints.maxWidth < 200;
            final fold = widget.onFold == null ? null : _FoldButton(folded: folded, onPressed: widget.onFold!);
            final logo = SportsHubLogo(height: folded ? 28 : 54, markOnly: folded, onDark: true);
            return _Folded(
              folded: folded,
              child: Padding(
                padding: EdgeInsets.fromLTRB(folded ? 12 : 14, 18, folded ? 12 : 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (folded) ...[
                      Center(child: logo),
                      if (fold != null) ...[const SizedBox(height: 12), Center(child: fold)],
                    ] else
                      Row(
                        children: [
                          Flexible(child: Align(alignment: Alignment.centerLeft, child: logo)),
                          if (fold != null) ...[const SizedBox(width: 8), fold],
                        ],
                      ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          SideNavTile(
                            icon: Icons.space_dashboard_rounded,
                            label: 'Overview',
                            selected: location == CoreRoutes.home,
                            onTap: () => _open(CoreRoutes.home),
                          ),
                          SideNavTile(
                            icon: Icons.apps_rounded,
                            label: 'My services',
                            selected: location == CoreRoutes.services,
                            onTap: () => _open(CoreRoutes.services),
                          ),
                          SideNavTile(
                            icon: Icons.notifications_none_rounded,
                            label: 'Notifications',
                            badge: unread,
                            selected: location == CoreRoutes.notifications,
                            onTap: () => _open(CoreRoutes.notifications),
                          ),
                          if (widget.services.isNotEmpty) ...[
                            SideNavHeading('Services', count: widget.services.length),
                            if (widget.services.length >= _findFrom && !folded) _FindService(onChanged: (v) => setState(() => _find = v)),
                            for (final nav in services) section(nav),
                            if (services.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                                child: Text('No service called "$_find"',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5)),
                              ),
                          ],
                          if (widget.admin != null) ...[
                            const SideNavHeading('Administration'),
                            section(widget.admin!),
                          ],
                        ],
                      ),
                    ),
                    _Me(
                      role: [...widget.services, if (widget.admin != null) widget.admin!]
                          .where((s) => s.isOpenAt(location))
                          .firstOrNull
                          ?.tagline,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Folded extends InheritedWidget {
  final bool folded;

  const _Folded({required this.folded, required super.child});

  @override
  bool updateShouldNotify(_Folded oldWidget) => oldWidget.folded != folded;
}

/// The round button that folds the menu, or opens it out.
class _FoldButton extends StatelessWidget {
  final bool folded;
  final VoidCallback onPressed;

  const _FoldButton({required this.folded, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: folded ? 'Expand menu' : 'Collapse menu',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        foregroundColor: Colors.white.withValues(alpha: 0.85),
        minimumSize: const Size(36, 36),
        fixedSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
      icon: AnimatedRotation(
        turns: folded ? 0.5 : 0,
        duration: const Duration(milliseconds: 240),
        child: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 20),
      ),
    );
  }
}

/// A small heading between the menu's groups ('SERVICES 3'); a rule when
/// it's folded.
class SideNavHeading extends StatelessWidget {
  final String text;
  final int? count;

  const SideNavHeading(this.text, {super.key, this.count});

  @override
  Widget build(BuildContext context) {
    if (PlatformSidebar.isFolded(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
      );
    }
    final style = TextStyle(
        color: Colors.white.withValues(alpha: 0.42), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: style)),
          if (count != null) Text('$count', style: style),
        ],
      ),
    );
  }
}

/// Finding a service by name, when there are many.
class _FindService extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _FindService({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Find a service',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: Colors.white.withValues(alpha: 0.55)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
        ),
      ),
    );
  }
}

/// One line of the menu: an icon and a label, marked when it's the page
/// open (a soft light and a bar in [accent]). Folded, the icon alone.
class SideNavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int badge;

  /// The bar's and icon's colour when it's open: the service's.
  final Color accent;

  /// A service's page, a little smaller and set in under its name.
  final bool nested;
  final bool external;

  const SideNavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
    this.accent = BrandColors.orange,
    this.nested = false,
    this.external = false,
  });

  @override
  State<SideNavTile> createState() => _SideNavTileState();
}

class _SideNavTileState extends State<SideNavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final folded = PlatformSidebar.isFolded(context);
    final selected = widget.selected;
    final text = selected ? Colors.white : Colors.white.withValues(alpha: _hover ? 0.92 : 0.72);
    final iconColor = selected ? widget.accent : text;
    final badge = widget.badge;
    final Widget content;
    if (folded) {
      content = Center(
        child: Badge(
          isLabelVisible: badge > 0,
          backgroundColor: BrandColors.orange,
          smallSize: 8,
          child: Icon(widget.icon, size: 21, color: iconColor),
        ),
      );
    } else {
      content = Row(
        children: [
          Icon(widget.icon, size: widget.nested ? 19 : 21, color: iconColor),
          SizedBox(width: widget.nested ? 12 : 14),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: text,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontSize: widget.nested ? 13.5 : 14.5,
              ),
            ),
          ),
          if (widget.external) Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white.withValues(alpha: 0.45)),
          if (badge > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: BrandColors.orange, borderRadius: BorderRadius.circular(20)),
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
        ],
      );
    }
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.1 : (_hover ? 0.05 : 0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: folded ? 0 : 12, vertical: widget.nested ? 9 : 11),
                  child: content,
                ),
                // The bar down the left of the open page.
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: selected ? 3 : 0,
                    decoration: BoxDecoration(color: widget.accent, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: folded ? (badge > 0 ? '${widget.label}, $badge' : widget.label) : null,
        child: folded ? Tooltip(message: widget.label, preferBelow: false, child: tile) : tile,
      ),
    );
  }
}

/// A service in the menu: its icon, name and the person's role in it; open,
/// what it's working on (with a switcher) and its pages under headings.
/// Folded, its icon, which opens its pages in a menu beside it.
class ServiceSection extends StatelessWidget {
  final ServiceNav nav;
  final String location;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<String> onOpen;
  final ValueChanged<Uri> onExternal;

  const ServiceSection({
    super.key,
    required this.nav,
    required this.location,
    required this.open,
    required this.onToggle,
    required this.onOpen,
    required this.onExternal,
  });

  void _go(NavDestination d) => d.isExternal ? onExternal(d.externalUrl!) : onOpen(d.route!);

  @override
  Widget build(BuildContext context) {
    final active = nav.isOpenAt(location);
    if (PlatformSidebar.isFolded(context)) return _foldedTile(context, active);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ServiceHeader(nav: nav, open: open, active: active, onTap: onToggle),
          Collapsible(
            open: open,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 0, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (nav.scope != null) _ScopeSwitcher(scope: nav.scope!, color: nav.color, onOpen: onOpen),
                  for (final s in nav.sections) ...[
                    if (s.title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                        child: Text(
                          s.title!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    for (final d in s.items)
                      SideNavTile(
                        icon: d.icon,
                        label: d.label,
                        nested: true,
                        external: d.isExternal,
                        badge: d.badge,
                        accent: nav.color,
                        selected: d.isOpenAt(location),
                        onTap: () => _go(d),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Folded: the service's icon; its pages in a menu beside it.
  Widget _foldedTile(BuildContext context, bool active) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: nav.name,
        preferBelow: false,
        child: Builder(
          builder: (context) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _flyout(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(child: ServiceIconTile(icon: nav.icon, color: nav.color, filled: active, size: 38)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _flyout(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(box.size.width + 8, 0), ancestor: overlay);
    final chosen = await showMenu<NavDestination>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx, 0),
      items: [
        PopupMenuItem<NavDestination>(
          enabled: false,
          child: Text(
            nav.scope == null ? nav.name : '${nav.name} · ${nav.scope!.label}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const PopupMenuDivider(),
        for (final d in nav.destinations)
          CheckedPopupMenuItem<NavDestination>(value: d, checked: d.isOpenAt(location), child: Text(d.label)),
      ],
    );
    if (chosen != null) _go(chosen);
  }
}

/// A service's icon on a tile of its colour: solid when it's the one in
/// use.
class ServiceIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool filled;
  final double size;

  const ServiceIconTile({super.key, required this.icon, required this.color, this.filled = false, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: filled ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))] : null,
      ),
      child: Icon(icon, size: size * 0.55, color: filled ? Colors.white : color),
    );
  }
}

class _ServiceHeader extends StatefulWidget {
  final ServiceNav nav;
  final bool open;
  final bool active;
  final VoidCallback onTap;

  const _ServiceHeader({required this.nav, required this.open, required this.active, required this.onTap});

  @override
  State<_ServiceHeader> createState() => _ServiceHeaderState();
}

class _ServiceHeaderState extends State<_ServiceHeader> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final nav = widget.nav;
    return Semantics(
      button: true,
      expanded: widget.open,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: widget.active || widget.open ? 0.06 : (_hover ? 0.04 : 0)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                child: Row(
                  children: [
                    ServiceIconTile(icon: nav.icon, color: nav.color, filled: widget.active),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nav.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5),
                          ),
                          if (nav.tagline != null)
                            Text(
                              nav.tagline!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5),
                            ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: widget.open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(Icons.expand_more_rounded, color: Colors.white.withValues(alpha: 0.6), size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the service is working on (the gym); a menu to switch, and to add
/// another.
class _ScopeSwitcher extends StatelessWidget {
  final ServiceScope scope;
  final Color color;
  final ValueChanged<String> onOpen;

  const _ScopeSwitcher({required this.scope, required this.color, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final several = scope.options.length > 1 || scope.addRoute != null;
    final initials = scope.label.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    final card = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(9)),
            child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scope.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                if (scope.detail != null)
                  Text(scope.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5)),
              ],
            ),
          ),
          if (several) Icon(Icons.unfold_more_rounded, color: Colors.white.withValues(alpha: 0.6), size: 18),
        ],
      ),
    );
    if (!several) return card;
    return PopupMenuButton<String>(
      tooltip: scope.options.length > 1 ? 'Switch' : scope.label,
      position: PopupMenuPosition.under,
      onSelected: (value) => onOpen(value == '+' ? scope.addRoute! : scope.onSelect(value)),
      itemBuilder: (_) => [
        for (final o in scope.options)
          CheckedPopupMenuItem(
            value: o.id,
            checked: o.id == scope.currentId,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: o.detail == null ? null : Text(o.detail!, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        if (scope.addRoute != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: '+',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_business_outlined),
              title: Text(scope.addLabel ?? 'Add another'),
            ),
          ),
        ],
      ],
      child: card,
    );
  }
}

/// A section's pages: they slide open and fold away. Folded, they're gone
/// from the tree (not just hidden), once the fold has finished.
class Collapsible extends StatefulWidget {
  final bool open;
  final Widget child;

  const Collapsible({super.key, required this.open, required this.child});

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: widget.open ? 1 : 0);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

  @override
  void didUpdateWidget(Collapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    if (reduceMotion(context)) {
      _c.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => _c.isDismissed
          ? const SizedBox.shrink()
          : ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _t.value,
                child: Opacity(opacity: _t.value, child: child),
              ),
            ),
      child: widget.child,
    );
  }
}

/// Who is signed in, and a menu: their account, light or dark, sign out.
class _Me extends ConsumerWidget {
  /// Their role in the service in use ('Owner'), if any.
  final String? role;

  const _Me({this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final access = ref.watch(myAccessProvider).valueOrNull;
    final mode = ref.watch(themeModeProvider);
    final name = (profile?.fullName ?? '').trim();
    final email = (profile?.email ?? '').trim();
    final subtitle = role ?? ((access?.isSuperAdmin ?? false) ? 'Super admin' : (email.isEmpty ? 'Signed in' : email));
    final folded = PlatformSidebar.isFolded(context);
    final avatar = CircleAvatar(
      radius: 17,
      backgroundColor: BrandColors.orange,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );

    Future<void> choose(String value) async {
      switch (value) {
        case 'account':
          context.go(CoreRoutes.account);
        case 'light':
          await ref.read(themeModeProvider.notifier).set(ThemeMode.light);
        case 'dark':
          await ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
        case 'system':
          await ref.read(themeModeProvider.notifier).set(ThemeMode.system);
        case 'out':
          await ref.read(authRepositoryProvider).signOut();
          if (context.mounted) context.go(CoreRoutes.welcome);
      }
    }

    final menu = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'account',
        child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.person_outline_rounded), title: Text('Account')),
      ),
      const PopupMenuDivider(),
      for (final (value, label, m) in [('light', 'Light', ThemeMode.light), ('dark', 'Dark', ThemeMode.dark), ('system', 'Match device', ThemeMode.system)])
        CheckedPopupMenuItem(value: value, checked: mode == m, child: Text(label)),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'out',
        child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout_rounded), title: Text('Sign out')),
      ),
    ];

    return PopupMenuButton<String>(
      tooltip: 'Account and settings',
      position: PopupMenuPosition.over,
      offset: const Offset(0, -12),
      onSelected: choose,
      itemBuilder: (_) => menu,
      child: folded
          ? Padding(padding: const EdgeInsets.only(top: 10), child: Center(child: avatar))
          : Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'You' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5)),
                      ],
                    ),
                  ),
                  Icon(Icons.more_vert_rounded, color: Colors.white.withValues(alpha: 0.6), size: 20),
                ],
              ),
            ),
    );
  }
}
