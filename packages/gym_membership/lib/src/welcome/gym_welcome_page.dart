import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../gym_routes.dart';
import '../widgets/gym_art.dart';
import '../widgets/gym_type.dart';

/// Welcome while gym membership is SportsHub's lead service: the landing page
/// for visitors. A bar over the top; the headline beside a membership card on
/// a phone; what SportsHub does; the services (gyms now, more sports to
/// come); why SportsHub; five steps to start; a last call; the footer. One
/// column at a phone's width; light and dark like the rest of the app.
///
/// Everything it claims is what the app does today: no member counts or
/// quotes until there are real ones.
class GymWelcomePage extends StatefulWidget {
  const GymWelcomePage({super.key});

  @override
  State<GymWelcomePage> createState() => _GymWelcomePageState();
}

class _GymWelcomePageState extends State<GymWelcomePage> {
  final _scroll = ScrollController();
  final _servicesKey = GlobalKey();
  final _aboutKey = GlobalKey();
  final _stepsKey = GlobalKey();
  final _plansKey = GlobalKey();
  final _faqKey = GlobalKey();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.offset > 8;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls [key]'s section up to just under the bar. A section not yet
  /// seen still waits a little low (_Reveal), so it lands a little high once
  /// it rises; the room left above it covers that.
  void _scrollTo(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !_scroll.hasClients) return;
    final barBottom = MediaQuery.paddingOf(context).top + _NavBar.height;
    final target = box.localToGlobal(Offset.zero).dy + _scroll.offset - barBottom - _RevealState.rise - 8;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
    );
  }

  void _toTop() => _scroll.animateTo(0, duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic);
  void _signUp() => context.push(CoreRoutes.signUp);
  void _logIn() => context.push(CoreRoutes.signIn);
  void _findGym() => context.push(GymRoutes.gyms);
  void _registerGym() => context.push(CoreRoutes.registerVenue);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The top's photo, ready before it's seen.
    precacheImage(GymPhoto.provider('hero'), context);
  }

  @override
  Widget build(BuildContext context) {
    return GymType(child: _page(_Layout(MediaQuery.sizeOf(context).width)));
  }

  Widget _page(_Layout layout) {
    return Scaffold(
      backgroundColor: context.brand.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(layout: layout, onGetStarted: _signUp, onExplore: () => _scrollTo(_servicesKey)),
                  _Highlights(layout: layout),
                  _Reveal(child: _Services(key: _servicesKey, layout: layout, onFindGym: _findGym)),
                  _Reveal(child: _About(key: _aboutKey, layout: layout, onKnowMore: () => _scrollTo(_stepsKey))),
                  _Reveal(child: _Steps(key: _stepsKey, layout: layout)),
                  _Reveal(child: _Plans(key: _plansKey, layout: layout, onFindGym: _findGym)),
                  _Reveal(child: _Faq(key: _faqKey, layout: layout)),
                  _Reveal(child: _LastCall(layout: layout, onJoin: _signUp, onRegisterGym: _registerGym)),
                  _Footer(
                    layout: layout,
                    links: [
                      ('Find a gym', _findGym),
                      ('Register your gym', _registerGym),
                      ('How it works', () => _scrollTo(_stepsKey)),
                      ('FAQs', () => _scrollTo(_faqKey)),
                      ('Log in', _logIn),
                      ('Sign up', _signUp),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _NavBar(
              layout: layout,
              scrolled: _scrolled,
              onLogo: _toTop,
              links: [
                ('Services', () => _scrollTo(_servicesKey)),
                ('About', () => _scrollTo(_aboutKey)),
                ('Plans', () => _scrollTo(_plansKey)),
                ('FAQs', () => _scrollTo(_faqKey)),
                ('Find a gym', _findGym),
              ],
              onSearch: _findGym,
              onLogIn: _logIn,
              onSignUp: _signUp,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Layout and colours ────────────────────────────────────────────────────

/// Sizes for the window's [width]: wide (a computer), medium (a tablet or a
/// small window) or narrow (a phone).
class _Layout {
  final double width;

  const _Layout(this.width);

  static const maxContent = 1180.0;

  /// How far What SportsHub does rises into the top, over its wave.
  static const overlap = 56.0;

  bool get wide => width >= 1024;
  bool get medium => width >= 680;

  /// The five steps side by side (one under the other below this).
  bool get stepsInRow => width >= 860;

  double get gutter => wide ? 40 : (medium ? 28 : 20);
  double get section => wide ? 96 : 64;
  double get titleSize => wide ? 44 : (medium ? 38 : 30);
}

/// The page's text colours, for light or dark.
class _Ink {
  final bool dark;

  const _Ink(this.dark);

  factory _Ink.of(BuildContext context) => _Ink(Theme.of(context).brightness == Brightness.dark);

  Color get heading => dark ? Colors.white : BrandColors.navy;
  Color get body => dark ? const Color(0xFFC5CCDA) : const Color(0xFF3A4560);

  /// Behind icons: a pale blue, or a faint white in the dark.
  Color get tint => dark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE6EEFA);
}

/// [child] centred, no wider than the content, with room at the sides.
class _Frame extends StatelessWidget {
  final _Layout layout;
  final Widget child;

  const _Frame({required this.layout, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _Layout.maxContent + layout.gutter * 2),
        child: Padding(padding: EdgeInsets.symmetric(horizontal: layout.gutter), child: child),
      ),
    );
  }
}

/// [children] in [columns] equal columns, the last row centred.
class _Grid extends StatelessWidget {
  final int columns;
  final double spacing;
  final List<Widget> children;

  const _Grid({required this.columns, required this.children, this.spacing = 14});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = ((constraints.maxWidth - spacing * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.center,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

// ─── The bar ───────────────────────────────────────────────────────────────

/// The logo, the sections (in a wide window), search, light or dark, Log in
/// and Sign up, on frosted glass.
class _NavBar extends StatelessWidget {
  static const height = 72.0;

  final _Layout layout;
  final bool scrolled;
  final VoidCallback onLogo;
  final List<(String, VoidCallback)> links;

  /// Searches gyms (Find a gym has the search).
  final VoidCallback onSearch;
  final VoidCallback onLogIn;
  final VoidCallback onSignUp;

  const _NavBar({
    required this.layout,
    required this.scrolled,
    required this.onLogo,
    required this.links,
    required this.onSearch,
    required this.onLogIn,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            // Frosted from the start, so the links stay clear over the
            // top's photo; fully once the page scrolls.
            child: AnimatedOpacity(
              opacity: scrolled ? 1 : 0.85,
              duration: const Duration(milliseconds: 200),
              child: GlassBar(border: Border(bottom: BorderSide(color: context.brand.glassBorder))),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: SizedBox(
            height: height,
            child: _Frame(
              layout: layout,
              child: Row(
                children: [
                  // The logo takes the room left, and shrinks before the
                  // buttons would run off the edge (a small phone, large text).
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        label: 'Back to the top',
                        child: GestureDetector(
                          onTap: onLogo,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SportsHubLogo(height: layout.medium ? 46 : 38, markOnly: !layout.medium),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (layout.wide) ...[
                    for (final (label, onTap) in links)
                      TextButton(
                        onPressed: onTap,
                        style: TextButton.styleFrom(
                          foregroundColor: ink.heading,
                          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        child: Text(label),
                      ),
                    const SizedBox(width: 8),
                  ],
                  if (layout.medium) ...[
                    IconButton(
                      tooltip: 'Search gyms',
                      onPressed: onSearch,
                      color: ink.heading,
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ],
                  ThemeModeButton(color: ink.heading),
                  SizedBox(width: layout.medium ? 8 : 4),
                  _PillButton(label: 'Log in', outlined: true, compact: true, onPressed: onLogIn),
                  const SizedBox(width: 10),
                  _PillButton(label: 'Sign up', compact: true, onPressed: onSignUp),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── The top ───────────────────────────────────────────────────────────────

/// The headline, what SportsHub is, Get Started and Explore Services, and
/// three things that are true of it; a photo of training beside them (under
/// them on a phone) with a membership card and a check-in floating over it;
/// a wave at the foot.
class _Hero extends StatelessWidget {
  final _Layout layout;
  final VoidCallback onGetStarted;
  final VoidCallback onExplore;

  const _Hero({required this.layout, required this.onGetStarted, required this.onExplore});

  /// Behind the words, and what the photo fades into.
  static Color background(bool dark) => dark ? const Color(0xFF0A1734) : const Color(0xFFEEF3FA);

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final bg = background(ink.dark);
    final headlineSize = layout.wide ? 70.0 : (layout.medium ? 56.0 : 42.0);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('GYM MEMBERSHIP PLATFORM', lineAfter: true),
        const SizedBox(height: 18),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Your Fitness\nPartner '),
              TextSpan(text: 'in Bhutan', style: TextStyle(color: ink.dark ? const Color(0xFFFF8A3D) : BrandColors.orange)),
            ],
          ),
          style: TextStyle(
            fontSize: headlineSize,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            height: 1.05,
            letterSpacing: -1.6,
            color: ink.heading,
          ),
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Text(
            'Find a gym near you, join a plan and check in with your phone. '
            'Your membership, payments and visits, all in one place.',
            style: TextStyle(fontSize: layout.wide ? 18.5 : 16.5, height: 1.6, color: ink.body),
          ),
        ),
        const SizedBox(height: 34),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            _PillButton(label: 'Get Started', icon: Icons.arrow_forward_rounded, onPressed: onGetStarted),
            _PillButton(label: 'Explore Services', outlined: true, onPressed: onExplore),
          ],
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            for (final point in const ['Free account', 'Pay in cash or mBoB', 'QR check-in'])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 18, color: BrandColors.orange),
                  const SizedBox(width: 7),
                  Text(point, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink.body)),
                ],
              ),
          ],
        ),
      ],
    );
    final top = MediaQuery.paddingOf(context).top + _NavBar.height;
    return ClipPath(
      clipper: _WaveClipper(),
      child: ColoredBox(
        color: bg,
        child: layout.wide ? _wide(context, words, bg, top) : _narrow(context, words, bg, top),
      ),
    );
  }

  /// The photo fills the right of the window, fading into the words.
  Widget _wide(BuildContext context, Widget words, Color bg, double top) {
    final photoLeft = layout.width * 0.4;
    return Stack(
      children: [
        Positioned(left: -200, top: 40, child: GymGlow(color: BrandColors.blue.withValues(alpha: 0.16), size: 560)),
        Positioned(
          left: photoLeft,
          top: 0,
          right: 0,
          bottom: 0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const GymPhoto('hero', alignment: Alignment(0.15, -0.3)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [bg, bg.withValues(alpha: 0.7), bg.withValues(alpha: 0)],
                    stops: const [0, 0.16, 0.5],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.85)],
                    stops: const [0.72, 1],
                  ),
                ),
              ),
              const IgnorePointer(child: CustomPaint(painter: GymStripesPainter())),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: top + 70, bottom: _Layout.overlap + 130),
          child: _Frame(
            layout: layout,
            child: Row(
              children: [
                Expanded(flex: 11, child: words),
                const SizedBox(width: 40),
                Expanded(
                  flex: 10,
                  child: SizedBox(
                    height: 470,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: const [
                        Positioned(left: 0, bottom: 10, child: _MiniCard()),
                        Positioned(
                          right: 10,
                          bottom: 30,
                          child: _FloatingNote(
                            icon: Icons.check_rounded,
                            iconColor: BrandColors.green,
                            title: 'Checked in',
                            text: 'Today, 6:42 AM',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The words, then the photo as a rounded card with the membership card
  /// and the check-in over its foot.
  Widget _narrow(BuildContext context, Widget words, Color bg, double top) {
    return Stack(
      children: [
        Positioned(right: -160, top: -80, child: GymGlow(color: BrandColors.orange.withValues(alpha: 0.16), size: 420)),
        Padding(
          padding: EdgeInsets.only(top: top + 28, bottom: _Layout.overlap + 92),
          child: _Frame(
            layout: layout,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                words,
                const SizedBox(height: 36),
                SizedBox(
                  height: layout.medium ? 460 : 380,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        bottom: 40,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: const Stack(
                            fit: StackFit.expand,
                            children: [
                              GymPhoto('hero', alignment: Alignment(0.3, -0.4)),
                              IgnorePointer(child: CustomPaint(painter: GymStripesPainter())),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 0,
                        child: Transform.scale(scale: layout.medium ? 1 : 0.86, alignment: Alignment.bottomLeft, child: const _MiniCard()),
                      ),
                      const Positioned(
                        right: 12,
                        top: 16,
                        child: _FloatingNote(
                          icon: Icons.check_rounded,
                          iconColor: BrandColors.green,
                          title: 'Checked in',
                          text: 'Today, 6:42 AM',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The top's foot: low on the left, rising to the right.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 36)
      ..cubicTo(w * 0.28, h + 8, w * 0.58, h - 96, w, h - 70)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) => false;
}

/// A member's card as My gym shows it: the gym, days left and the QR code.
class _MiniCard extends StatelessWidget {
  const _MiniCard();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 330,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xF20A1C45), Color(0xF21F4FA8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 36, offset: const Offset(0, 18))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'Your gym',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: BrandColors.green, borderRadius: BorderRadius.circular(20)),
                        child: const Text(
                          'Active',
                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('1 month plan', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                  const SizedBox(height: 10),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('23', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, height: 1)),
                      SizedBox(width: 6),
                      Flexible(child: Text('days left', style: TextStyle(color: Colors.white70, fontSize: 13))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      value: 0.25,
                      minHeight: 5,
                      color: BrandColors.orange,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                data: 'SPORTSHUB',
                size: 78,
                padding: EdgeInsets.zero,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: BrandColors.navy),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: BrandColors.navy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small card floating over the photo.
class _FloatingNote extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;

  const _FloatingNote({required this.icon, required this.iconColor, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
        decoration: BoxDecoration(
          color: ink.dark ? const Color(0xF216213C) : const Color(0xF7FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.brand.glassBorder),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: ink.dark ? 0.4 : 0.18), blurRadius: 28, offset: const Offset(0, 12)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink.heading)),
                Text(text, style: TextStyle(fontSize: 12, color: context.brand.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades [child] up into place the first time it scrolls into view (at
/// once when the device asks for less motion).
class _Reveal extends StatefulWidget {
  final Widget child;

  const _Reveal({required this.child});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _shown = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shown = true;
      return;
    }
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_shown || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    if (box.localToGlobal(Offset.zero).dy < MediaQuery.sizeOf(context).height * 0.92) {
      _position?.removeListener(_check);
      setState(() => _shown = true);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  /// How far below its place a section waits to rise.
  static const rise = 28.0;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 750);
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: duration,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _shown ? 0 : rise, 0),
        child: widget.child,
      ),
    );
  }
}

// ─── What SportsHub does ───────────────────────────────────────────────────

class _Highlight {
  final IconData icon;
  final String title;
  final String text;

  const _Highlight(this.icon, this.title, this.text);
}

/// What it does, on one card rising into the top's wave.
class _Highlights extends StatelessWidget {
  final _Layout layout;

  const _Highlights({required this.layout});

  static const items = [
    _Highlight(Icons.card_membership_rounded, 'Membership Management', 'Join, renew and see days left'),
    _Highlight(Icons.qr_code_scanner_rounded, 'Attendance Tracking', 'QR check-in at the desk'),
    _Highlight(Icons.payments_outlined, 'Easy Payments', 'Cash, mBoB or bank transfer'),
    _Highlight(Icons.badge_outlined, 'Staff & Roles', 'Owners, managers and front desk'),
    _Highlight(Icons.insights_rounded, 'Business Insights', 'Income and members by month'),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final cells = [for (final item in items) _HighlightCell(item: item)];
    return Transform.translate(
      offset: const Offset(0, -_Layout.overlap),
      child: _Frame(
        layout: layout,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 24, horizontal: layout.wide ? 8 : 16),
          decoration: BoxDecoration(
            color: ink.dark ? const Color(0xFF111A2E) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: brand.glassBorder),
            boxShadow: [
              BoxShadow(
                color: (ink.dark ? Colors.black : BrandColors.navy).withValues(alpha: ink.dark ? 0.4 : 0.09),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: layout.wide
              ? IntrinsicHeight(
                  child: Row(
                    children: [
                      for (var i = 0; i < cells.length; i++) ...[
                        if (i > 0) VerticalDivider(width: 1, color: brand.glassBorder, indent: 4, endIndent: 4),
                        Expanded(child: cells[i]),
                      ],
                    ],
                  ),
                )
              : _Grid(columns: layout.medium ? 3 : 2, spacing: 18, children: cells),
        ),
      ),
    );
  }
}

class _HighlightCell extends StatelessWidget {
  final _Highlight item;

  const _HighlightCell({required this.item});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: ink.tint, borderRadius: BorderRadius.circular(16)),
            child: Icon(item.icon, size: 26, color: BrandColors.orange),
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink.heading, height: 1.25),
          ),
          const SizedBox(height: 4),
          Text(
            item.text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.brand.muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

// ─── Services ──────────────────────────────────────────────────────────────

class _Service {
  final String name;
  final IconData icon;

  /// Its photo in assets/welcome.
  final String photo;

  /// Open now; the rest are coming.
  final bool open;

  const _Service(this.name, this.icon, this.photo, {this.open = false});
}

/// More than a gym: gyms now (they open Find a gym), and the sports coming.
class _Services extends StatelessWidget {
  final _Layout layout;
  final VoidCallback onFindGym;

  const _Services({super.key, required this.layout, required this.onFindGym});

  static const services = [
    _Service('Gym & Fitness', Icons.fitness_center_rounded, 'gym', open: true),
    _Service('Yoga & Wellness', Icons.self_improvement_rounded, 'yoga'),
    _Service('Swimming', Icons.pool_rounded, 'swimming'),
    _Service('Indoor Sports', Icons.sports_basketball_rounded, 'indoor'),
    _Service('Outdoor Sports', Icons.sports_soccer_rounded, 'outdoor'),
    _Service('Racket Sports', Icons.sports_tennis_rounded, 'racket'),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('OUR SERVICES', lineBefore: true),
        const SizedBox(height: 14),
        Text(
          'More Than a Gym',
          style: TextStyle(
            fontSize: layout.titleSize,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -0.8,
            color: ink.heading,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'From fitness to sports, SportsHub brings everything you need under one platform. '
          'Gyms are open now, and more sports are on the way.',
          style: TextStyle(fontSize: 17, height: 1.55, color: ink.body),
        ),
        const SizedBox(height: 28),
        _PillButton(label: 'Find a gym', icon: Icons.arrow_forward_rounded, onPressed: onFindGym),
      ],
    );
    final tiles = _Grid(
      columns: layout.medium ? 3 : 2,
      children: [for (final s in services) _ServiceTile(service: s, onTap: s.open ? onFindGym : null)],
    );
    return Padding(
      padding: EdgeInsets.only(top: layout.section - _Layout.overlap, bottom: layout.section),
      child: _Frame(
        layout: layout,
        child: layout.wide
            ? Row(
                children: [
                  Expanded(flex: 4, child: intro),
                  const SizedBox(width: 48),
                  Expanded(flex: 7, child: tiles),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [intro, const SizedBox(height: 32), tiles],
              ),
      ),
    );
  }
}

/// A service on its photo, darkened at the foot for its name; the photo
/// eases in a little under the pointer.
class _ServiceTile extends StatefulWidget {
  final _Service service;
  final VoidCallback? onTap;

  const _ServiceTile({required this.service, this.onTap});

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final badge = service.open ? 'Open now' : 'Coming soon';
    return Semantics(
      button: widget.onTap != null,
      label: '${service.name}, $badge',
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.28 : 0.14),
                blurRadius: _hover ? 26 : 14,
                offset: Offset(0, _hover ? 14 : 6),
              ),
            ],
          ),
          child: AspectRatio(
            aspectRatio: 1.5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    scale: _hover ? 1.07 : 1,
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    child: GymPhoto(service.photo),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.05),
                          BrandColors.navy.withValues(alpha: 0.35),
                          const Color(0xE6050B1C),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: service.open ? BrandColors.orange : Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(20),
                        border: service.open ? null : Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 14,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(service.icon, size: 30, color: Colors.white),
                        const SizedBox(height: 6),
                        Text(
                          service.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onTap != null)
                    Material(type: MaterialType.transparency, child: InkWell(onTap: widget.onTap)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── About ─────────────────────────────────────────────────────────────────

/// What SportsHub is, with what members get and three facts about it, on a
/// tinted band.
class _About extends StatelessWidget {
  final _Layout layout;
  final VoidCallback onKnowMore;

  const _About({super.key, required this.layout, required this.onKnowMore});

  static const points = ['Easy membership management', 'Real-time attendance', 'Secure, reliable platform'];

  static const facts = [
    (Icons.event_available_rounded, '6 plan lengths', 'Day pass to a year'),
    (Icons.payments_outlined, '3 ways to pay', 'Cash, mBoB or bank'),
    (Icons.location_on_outlined, 'Made for Bhutan', 'Prices in Ngultrum'),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('ABOUT SPORTSHUB', lineBefore: true),
        const SizedBox(height: 14),
        Text(
          'Build a Healthier,\nStronger You',
          style: TextStyle(
            fontSize: layout.titleSize,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -0.8,
            color: ink.heading,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'SportsHub is a fitness platform made for Bhutan. It starts with gyms: find one, join a plan '
          'and check in with your phone. Sports facilities and wellness are on the way.',
          style: TextStyle(fontSize: 16, height: 1.55, color: ink.body),
        ),
        const SizedBox(height: 16),
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Check(point),
          ),
        const SizedBox(height: 16),
        _PillButton(
          label: 'Know More',
          icon: Icons.arrow_forward_rounded,
          color: ink.dark ? BrandColors.blue : BrandColors.navy,
          onPressed: onKnowMore,
        ),
      ],
    );
    final factList = _Grid(
      columns: layout.wide ? 1 : (layout.medium ? 3 : 1),
      spacing: 22,
      children: [
        for (final (icon, value, label) in facts)
          Row(
            children: [
              Icon(icon, size: 32, color: BrandColors.orange),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink.heading)),
                    Text(label, style: TextStyle(fontSize: 13, color: context.brand.muted)),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
    return Container(
      margin: EdgeInsets.only(bottom: layout.section),
      padding: EdgeInsets.symmetric(vertical: layout.section * 0.75),
      color: ink.dark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFEDF2F9),
      child: _Frame(
        layout: layout,
        child: layout.wide
            ? Row(
                children: [
                  const Expanded(flex: 5, child: _AboutArt(height: 300)),
                  const SizedBox(width: 48),
                  Expanded(flex: 5, child: words),
                  const SizedBox(width: 32),
                  Container(width: 1, height: 220, color: context.brand.glassBorder),
                  const SizedBox(width: 32),
                  Expanded(flex: 3, child: factList),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AboutArt(height: layout.medium ? 260 : 200),
                  const SizedBox(height: 32),
                  words,
                  const SizedBox(height: 32),
                  factList,
                ],
              ),
      ),
    );
  }
}

/// A gym's floor on an orange shape, with an orange band across a corner.
class _AboutArt extends StatelessWidget {
  final double height;

  const _AboutArt({required this.height});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -10,
              top: -10,
              right: 40,
              bottom: 30,
              child: DecoratedBox(
                decoration: BoxDecoration(color: BrandColors.orange, borderRadius: BorderRadius.circular(32)),
              ),
            ),
            Positioned.fill(
              left: 6,
              top: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: BrandColors.navy.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 16)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const GymPhoto('about'),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, BrandColors.navy.withValues(alpha: 0.35)],
                          ),
                        ),
                      ),
                      Positioned(
                        right: -40,
                        bottom: -height * 0.5,
                        child: Transform.rotate(
                          angle: 0.6,
                          child: Container(width: 54, height: height * 1.2, color: BrandColors.orange.withValues(alpha: 0.9)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An orange tick and [text].
class _Check extends StatelessWidget {
  final String text;

  const _Check(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.check_rounded, size: 19, color: BrandColors.orange),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 14.5, height: 1.4, color: _Ink.of(context).body))),
      ],
    );
  }
}

// ─── How it works ──────────────────────────────────────────────────────────

class _Step {
  final IconData icon;
  final String title;
  final String text;

  const _Step(this.icon, this.title, this.text);
}

/// Five steps from signing up to training.
class _Steps extends StatelessWidget {
  final _Layout layout;

  const _Steps({super.key, required this.layout});

  static const steps = [
    _Step(Icons.person_add_alt_1_rounded, 'Sign Up', 'Create your account in minutes'),
    _Step(Icons.event_note_rounded, 'Choose a Plan', 'Pick a gym and a membership plan'),
    _Step(Icons.payments_outlined, 'Make Payment', 'Pay the gym in cash or by mBoB'),
    _Step(Icons.qr_code_2_rounded, 'Check In', 'Show your QR code at the desk'),
    _Step(Icons.emoji_events_outlined, 'Achieve Goals', 'Train on, and renew before it ends'),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: layout.section),
      child: _Frame(
        layout: layout,
        child: Column(
          children: [
            const _Eyebrow('HOW IT WORKS', lineBefore: true, lineAfter: true),
            const SizedBox(height: 14),
            Text.rich(
              const TextSpan(
                children: [
                  TextSpan(text: 'Get Started in '),
                  TextSpan(text: '5 Simple Steps', style: TextStyle(color: BrandColors.orange)),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: layout.titleSize,
                fontWeight: FontWeight.w900,
                height: 1.15,
                letterSpacing: -0.8,
                color: ink.heading,
              ),
            ),
            SizedBox(height: layout.stepsInRow ? 52 : 36),
            if (layout.stepsInRow)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < steps.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 28),
                        child: Icon(Icons.arrow_forward_rounded, color: BrandColors.orange, size: 22),
                      ),
                    Expanded(child: _StepColumn(number: i + 1, step: steps[i])),
                  ],
                ],
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [for (var i = 0; i < steps.length; i++) _StepRow(number: i + 1, step: steps[i])],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const _StepIcon({required this.icon, required this.size});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: ink.tint, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.42, color: ink.heading),
    );
  }
}

/// A step under its icon, side by side with the others.
class _StepColumn extends StatelessWidget {
  final int number;
  final _Step step;

  const _StepColumn({required this.number, required this.step});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          _StepIcon(icon: step.icon, size: 78),
          const SizedBox(height: 16),
          Text(
            '$number. ${step.title}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink.heading),
          ),
          const SizedBox(height: 6),
          Text(
            step.text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: context.brand.muted),
          ),
        ],
      ),
    );
  }
}

/// A step beside its icon, one under the other.
class _StepRow extends StatelessWidget {
  final int number;
  final _Step step;

  const _StepRow({required this.number, required this.step});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          _StepIcon(icon: step.icon, size: 58),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number. ${step.title}',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink.heading),
                ),
                const SizedBox(height: 3),
                Text(step.text, style: TextStyle(fontSize: 14, height: 1.4, color: context.brand.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Plans ─────────────────────────────────────────────────────────────────

class _PlanKind {
  final String name;
  final String tagline;
  final String lengths;
  final List<String> points;
  final bool featured;

  const _PlanKind(this.name, this.tagline, this.lengths, this.points, {this.featured = false});
}

/// The plan lengths gyms offer. Each gym sets its own plans and prices, so
/// there are no prices here: Find a gym shows them.
class _Plans extends StatelessWidget {
  final _Layout layout;
  final VoidCallback onFindGym;

  const _Plans({super.key, required this.layout, required this.onFindGym});

  static const kinds = [
    _PlanKind('Short Stay', 'Try a gym first', 'Day pass · 1 week', ['QR check-in from day one', 'No long commitment']),
    _PlanKind(
      'Monthly',
      'The everyday choice',
      '1 month · 3 months',
      ['Reminder 3 days before the end', 'Renew without losing days'],
      featured: true,
    ),
    _PlanKind('Long Term', 'For the committed', '6 months · 1 year', ['Your card and visits in one place', 'Fewer renewals to think of']),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('MEMBERSHIP PLANS', lineBefore: true),
        const SizedBox(height: 14),
        Text(
          'Choose Your\nPerfect Plan',
          style: TextStyle(
            fontSize: layout.titleSize,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -0.8,
            color: ink.heading,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Flexible plans for every fitness goal. Each gym sets its own plans and prices in Ngultrum.',
          style: TextStyle(fontSize: 16, height: 1.55, color: ink.body),
        ),
        const SizedBox(height: 24),
        _PillButton(label: 'See plans at gyms', icon: Icons.arrow_forward_rounded, onPressed: onFindGym),
      ],
    );
    final cards = [for (final k in kinds) _PlanCard(kind: k, onFindGym: onFindGym)];
    return Padding(
      padding: EdgeInsets.only(bottom: layout.section),
      child: _Frame(
        layout: layout,
        child: layout.wide
            ? Row(
                children: [
                  Expanded(flex: 3, child: intro),
                  const SizedBox(width: 40),
                  Expanded(
                    flex: 8,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[
                            if (i > 0) const SizedBox(width: 16),
                            Expanded(child: cards[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  intro,
                  const SizedBox(height: 32),
                  _Grid(columns: layout.medium ? 3 : 1, spacing: 16, children: cards),
                ],
              ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final _PlanKind kind;
  final VoidCallback onFindGym;

  const _PlanCard({required this.kind, required this.onFindGym});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final orangeTint = BrandColors.orange.withValues(alpha: ink.dark ? 0.12 : 0.06);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: kind.featured ? Color.alphaBlend(orangeTint, ink.dark ? const Color(0xFF111A2E) : Colors.white) : null,
        gradient: kind.featured
            ? null
            : LinearGradient(colors: ink.dark ? const [Color(0xFF111A2E), Color(0xFF111A2E)] : const [Colors.white, Colors.white]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kind.featured ? BrandColors.orange : brand.glassBorder, width: kind.featured ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
            color: (ink.dark ? Colors.black : BrandColors.navy).withValues(alpha: ink.dark ? 0.3 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      // Side by side the cards share a height, and the buttons line up at
      // the foot; stacked, each is as tall as it needs.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kind.name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ink.heading)),
              Text(kind.tagline, style: TextStyle(fontSize: 13, color: brand.muted)),
              const SizedBox(height: 16),
              Text(kind.lengths, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: ink.heading)),
              Text('Prices set by each gym', style: TextStyle(fontSize: 12, color: brand.muted)),
              const SizedBox(height: 16),
              for (final point in kind.points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Check(point),
                ),
              const SizedBox(height: 12),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: _PillButton(label: 'Find a gym', compact: true, outlined: !kind.featured, onPressed: onFindGym),
          ),
        ],
      ),
    );
  }
}

// ─── Questions ─────────────────────────────────────────────────────────────

/// What people ask, opening one at a time.
class _Faq extends StatelessWidget {
  final _Layout layout;

  const _Faq({super.key, required this.layout});

  static const questions = [
    (
      'How do I join a gym?',
      'Sign up, open Find a gym and ask to join the plan you want. Pay the gym, and your membership '
          'starts as soon as the staff confirm your payment.',
    ),
    (
      'What payment methods are accepted?',
      'You pay the gym directly: cash, mBoB or bank transfer. The staff record it in SportsHub, with '
          'the journal number for mBoB and transfers.',
    ),
    (
      'When does my membership start and end?',
      "It starts the day your payment is confirmed and runs for the plan's length. Renew early and the "
          'new plan starts the day after the current one ends, so you never lose days.',
    ),
    (
      'How do I check in?',
      'Open My gym and show your QR code at the desk. The staff scan it, or type your member code.',
    ),
    (
      'Can I cancel my membership?',
      'You can cancel a request while it is still waiting for payment. Once a membership is active, '
          'talk to your gym: changes and refunds are up to them.',
    ),
    (
      'How do I put my gym on SportsHub?',
      'Sign up, then Register your venue, choose Gym and add your plans. Once SportsHub has verified '
          'your gym, members can find it and join.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final brand = context.brand;
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Eyebrow('FREQUENTLY ASKED QUESTIONS', lineBefore: true),
        const SizedBox(height: 14),
        Text(
          'Have Questions?',
          style: TextStyle(
            fontSize: layout.titleSize,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -0.8,
            color: ink.heading,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Answers about joining, paying and checking in.',
          style: TextStyle(fontSize: 16, height: 1.55, color: ink.body),
        ),
      ],
    );
    final list = Container(
      decoration: BoxDecoration(
        color: ink.dark ? const Color(0xFF111A2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Column(
          children: [
            for (var i = 0; i < questions.length; i++) ...[
              if (i > 0) Divider(height: 1, color: brand.glassBorder),
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                expandedAlignment: Alignment.centerLeft,
                iconColor: BrandColors.orange,
                collapsedIconColor: ink.heading,
                title: Text(
                  questions[i].$1,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ink.heading),
                ),
                children: [
                  Text(questions[i].$2, style: TextStyle(fontSize: 14.5, height: 1.55, color: ink.body)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: layout.section),
      child: _Frame(
        layout: layout,
        child: layout.wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: intro),
                  const SizedBox(width: 40),
                  Expanded(flex: 7, child: list),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [intro, const SizedBox(height: 28), list],
              ),
      ),
    );
  }
}

// ─── The last call ─────────────────────────────────────────────────────────

/// Join Now on navy, and registering a gym.
class _LastCall extends StatelessWidget {
  final _Layout layout;
  final VoidCallback onJoin;
  final VoidCallback onRegisterGym;

  const _LastCall({required this.layout, required this.onJoin, required this.onRegisterGym});

  @override
  Widget build(BuildContext context) {
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ready to transform your fitness journey?',
          style: TextStyle(
            color: Colors.white,
            fontSize: layout.wide ? 32 : 25,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Join SportsHub today and take the first step towards a healthier you.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 17, height: 1.5),
        ),
      ],
    );
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: layout.medium ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        _PillButton(label: 'Join Now', icon: Icons.arrow_forward_rounded, onPressed: onJoin),
        const SizedBox(height: 6),
        TextButton(
          onPressed: onRegisterGym,
          style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: 0.85)),
          child: const Text('Run a gym? Register it'),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: layout.section * 0.75),
      child: _Frame(
        layout: layout,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A1C45), Color(0xFF15295A)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Stack(
              children: [
                // Snow peaks on the right, the navy deepening to the left
                // under the words.
                const Positioned.fill(child: GymPhoto('mountains', alignment: Alignment(0, -0.2))),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFA0A1C45),
                          const Color(0xE00A1C45),
                          BrandColors.navy.withValues(alpha: layout.medium ? 0.35 : 0.75),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(right: -60, top: -120, child: GymGlow(color: BrandColors.orange.withValues(alpha: 0.3), size: 320)),
                Padding(
                  padding: EdgeInsets.all(layout.wide ? 48 : 28),
                  child: layout.medium
                      ? Row(children: [Expanded(child: words), const SizedBox(width: 28), actions])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [words, const SizedBox(height: 22), actions],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Footer ────────────────────────────────────────────────────────────────

/// On navy: the logo, the links, Bhutan's mountains and the copyright.
class _Footer extends StatelessWidget {
  final _Layout layout;
  final List<(String, VoidCallback)> links;

  const _Footer({required this.layout, required this.links});

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.7);
    final linkRow = Wrap(
      alignment: layout.medium ? WrapAlignment.end : WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < links.length; i++) ...[
          if (i > 0) Text('|', style: TextStyle(color: Colors.white.withValues(alpha: 0.25))),
          TextButton(
            onPressed: links[i].$2,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.85),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
            child: Text(links[i].$1),
          ),
        ],
      ],
    );
    // The logo's navy lettering wants white under it, light theme or dark.
    final logo = DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Theme(data: AppTheme.light, child: const SportsHubLogo(height: 48)),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A1C45), Color(0xFF071229)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: layout.wide ? 130 : 90,
            child: CustomPaint(
              painter: _MountainsPainter(
                far: Colors.white.withValues(alpha: 0.04),
                near: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: layout.wide ? 48 : 36, bottom: 22),
            child: Column(
              children: [
                _Frame(
                  layout: layout,
                  child: layout.medium
                      ? Row(children: [logo, const SizedBox(width: 24), Expanded(child: linkRow)])
                      : Column(children: [logo, const SizedBox(height: 18), linkRow]),
                ),
                SizedBox(height: layout.wide ? 56 : 40),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 18),
                Text(
                  '© ${BhutanTime.today().year} SportsHub. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two ranges of mountains, [far] behind [near].
class _MountainsPainter extends CustomPainter {
  final Color far;
  final Color near;

  const _MountainsPainter({required this.far, required this.near});

  static const _far = [
    (0.0, 0.62), (0.07, 0.34), (0.14, 0.56), (0.23, 0.18), (0.32, 0.5), (0.41, 0.3), (0.5, 0.56),
    (0.6, 0.12), (0.7, 0.46), (0.79, 0.24), (0.89, 0.52), (1.0, 0.3),
  ];
  static const _near = [
    (0.0, 0.82), (0.1, 0.6), (0.2, 0.8), (0.3, 0.54), (0.42, 0.84), (0.55, 0.6), (0.66, 0.86),
    (0.78, 0.62), (0.9, 0.82), (1.0, 0.66),
  ];

  void _range(Canvas canvas, Size size, List<(double, double)> peaks, Color color) {
    final path = Path()..moveTo(0, size.height);
    for (final (x, y) in peaks) {
      path.lineTo(x * size.width, y * size.height);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _range(canvas, size, _far, far);
    _range(canvas, size, _near, near);
  }

  @override
  bool shouldRepaint(_MountainsPainter oldDelegate) => oldDelegate.far != far || oldDelegate.near != near;
}

// ─── Small parts ───────────────────────────────────────────────────────────

/// Small capitals over a title, with orange rules before and/or after.
class _Eyebrow extends StatelessWidget {
  final String text;
  final bool lineBefore;
  final bool lineAfter;

  const _Eyebrow(this.text, {this.lineBefore = false, this.lineAfter = false});

  @override
  Widget build(BuildContext context) {
    final rule = Container(
      width: 34,
      height: 2.5,
      decoration: BoxDecoration(color: BrandColors.orange, borderRadius: BorderRadius.circular(2)),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lineBefore) ...[rule, const SizedBox(width: 10)],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: _Ink.of(context).heading,
            ),
          ),
        ),
        if (lineAfter) ...[const SizedBox(width: 10), rule],
      ],
    );
  }
}

/// A round-ended button: filled with [color] (orange), or [outlined].
class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool outlined;
  final Color color;

  /// Smaller, for the bar.
  final bool compact;

  const _PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.color = BrandColors.orange,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 26, vertical: 18);
    final minimumSize = compact ? const Size(0, 40) : const Size(0, 54);
    final textStyle = (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
        .copyWith(fontSize: compact ? 14 : 16, fontWeight: FontWeight.w700);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 19)],
      ],
    );
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: ink.heading,
          side: BorderSide(color: ink.heading, width: 1.4),
          shape: const StadiumBorder(),
          padding: padding,
          minimumSize: minimumSize,
          textStyle: textStyle,
        ),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          if (!compact) BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          padding: padding,
          minimumSize: minimumSize,
          textStyle: textStyle,
        ),
        child: child,
      ),
    );
  }
}
