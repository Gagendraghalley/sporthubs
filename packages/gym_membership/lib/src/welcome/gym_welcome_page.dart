import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../gym_routes.dart';
import '../widgets/gym_art.dart';
import '../widgets/gym_type.dart';

/// The landing page for visitors, with a multi-sport introduction and service
/// links supplied by the modules enabled for this installation.
///
/// Everything it claims is what the app does today: no member counts or
/// quotes until there are real ones.
class GymWelcomePage extends ConsumerStatefulWidget {
  const GymWelcomePage({super.key});

  @override
  ConsumerState<GymWelcomePage> createState() => _GymWelcomePageState();
}

class _GymWelcomePageState extends ConsumerState<GymWelcomePage> {
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
    // The sport photos, ready before the top's slides sweep them in.
    for (final slide in _slides) {
      precacheImage(GymPhoto.provider(slide.photo), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GymType(child: _page(_Layout(MediaQuery.sizeOf(context).width)));
  }

  Widget _page(_Layout layout) {
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <SportsHubModule>[];
    final appModules = ref.watch(appModulesProvider).valueOrNull ?? const <AppModuleRow>[];
    final enabledKeys = appModules.where((module) => module.isEnabled).map((module) => module.key).toSet();
    final serviceLinks = modules
        .where((module) => enabledKeys.contains(module.key))
        .expand((module) => module.playerMenuItems())
        .where((item) => item.isExternal)
        .toList();

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
                  _Hero(
                    layout: layout,
                    scroll: _scroll,
                    onGetStarted: _signUp,
                    onExplore: () => _scrollTo(_servicesKey),
                  ),
                  _Highlights(layout: layout),
                  _Reveal(
                    child: _Services(
                      key: _servicesKey,
                      layout: layout,
                      serviceLinks: serviceLinks,
                      onFindGym: _findGym,
                    ),
                  ),
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

/// The page's colours, for light or dark; mixed while the theme switches,
/// so bands and cards glide rather than flash.
class _Ink {
  /// 0 light, 1 dark ([Brand.darkness]).
  final double t;

  const _Ink(this.t);

  factory _Ink.of(BuildContext context) => _Ink(context.brand.darkness);

  bool get dark => t >= 0.5;

  Color pick(Color light, Color dark) => Color.lerp(light, dark, t)!;

  Color get heading => pick(LightColors.ink, Colors.white);
  Color get body => pick(LightColors.body, const Color(0xFFC5CCDA));

  /// Behind icons: a cool pale grey-blue, or a faint white in the dark.
  Color get tint => pick(const Color(0xFFEAF0F8), Colors.white.withValues(alpha: 0.08));

  /// A card on the page.
  Color get card => pick(LightColors.card, BrandColors.slateNavy);

  /// Under a card: a soft navy haze in the light, a deep shadow in the dark.
  List<BoxShadow> shadow({double light = 0.07, double dark = 0.3, double blur = 24, double dy = 10}) => [
        BoxShadow(
          color: pick(LightColors.navy.withValues(alpha: light), Colors.black.withValues(alpha: dark)),
          blurRadius: blur,
          spreadRadius: this.dark ? 0 : -4,
          offset: Offset(0, dy),
        ),
      ];
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
                          textStyle: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
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
/// three things that are true of it, beside a slide show of sports filling
/// the right of the window (a card under them on a phone); a membership card
/// and a check-in float over it, and a wave runs along the foot.
///
/// The slides move like 108.bt's opening scene: each sport sweeps in from
/// the right behind the page's navy and orange bands, drifts slowly closer
/// while it shows, then gives way to the next.
class _Hero extends StatefulWidget {
  final _Layout layout;
  final VoidCallback onGetStarted;
  final VoidCallback onExplore;

  /// The page's scroll: the photos drift up a little slower than the page
  /// and lean in (a gentle depth), and rest once the top is out of sight.
  final ScrollController scroll;

  const _Hero({required this.layout, required this.onGetStarted, required this.onExplore, required this.scroll});

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with TickerProviderStateMixin {
  late final _SlideShow _show = _SlideShow(this);

  _Layout get layout => widget.layout;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_Hero old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_onScroll);
      widget.scroll.addListener(_onScroll);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Starts the slides the first time; stills them, or sets them going,
    // when Reduce motion changes.
    _show.setStill(reduceMotion(context));
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    _show.dispose();
    super.dispose();
  }

  /// The slides rest while the top is scrolled out of sight.
  void _onScroll() {
    if (!widget.scroll.hasClients) return;
    final box = context.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 800.0;
    _show.setVisible(widget.scroll.offset < height - 40);
  }

  /// [child] moved by a share of the scroll, and leaning in by [zoom] as it
  /// goes, while the top is on screen.
  Widget _parallax(BuildContext context, Widget child, {double rate = 0.12, double zoom = 0}) {
    if (reduceMotion(context)) return child;
    return AnimatedBuilder(
      animation: widget.scroll,
      child: child,
      builder: (context, child) {
        final offset = widget.scroll.hasClients ? widget.scroll.offset.clamp(0.0, 900.0) : 0.0;
        return Transform.translate(
          offset: Offset(0, offset * rate),
          child: Transform.scale(scale: 1 + zoom * offset / 900, child: child),
        );
      },
    );
  }

  /// [child], swiped left for the next sport or right for the one before.
  Widget _swipe(Widget child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -150) _show.next();
          if (velocity > 150) _show.previous();
        },
        child: child,
      );

  /// The sample card and the check-in note: they arrive after the photos,
  /// then float a little, out of step, and settle.
  static Widget _card(Widget child, {required int order}) => FadeSlideIn(
        delay: Duration(milliseconds: 520 + 140 * order),
        offset: 26,
        child: GentleFloat(phase: order * 0.35, distance: order == 0 ? 7 : 5, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    // Behind the words, and what the photo fades into.
    final bg = ink.pick(LightColors.backgroundAlt, BrandColors.navy);
    final headlineSize = layout.wide ? 70.0 : (layout.medium ? 56.0 : 42.0);
    final headline = TextStyle(
      fontSize: headlineSize,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      height: 1.05,
      letterSpacing: -1.6,
      color: ink.heading,
    );
    // The headline arrives a line at a time, then what it is, the buttons and
    // the facts: one short cascade on arrival, then still.
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: staggered(step: const Duration(milliseconds: 90), offset: 18, [
        const Padding(padding: EdgeInsets.only(bottom: 18), child: _Eyebrow('SPORTS & FITNESS PLATFORM', lineAfter: true)),
        Text('One Platform.', style: headline),
        Text('Every Sport.', style: headline),
        Text('Endless Possibilities.',
            style: headline.copyWith(color: ink.dark ? BrandColors.orange : LightColors.orangeText)),
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 34),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Text(
              'Discover gyms, manage memberships and track visits in SportsHub. '
              'Connected sports services help bring facilities and activities across Bhutan together.',
              style: TextStyle(fontSize: layout.wide ? 18.5 : 16.5, height: 1.6, color: ink.body),
            ),
          ),
        ),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            _PillButton(label: 'Get Started', icon: Icons.arrow_forward_rounded, onPressed: widget.onGetStarted),
            _PillButton(label: 'Explore Services', outlined: true, onPressed: widget.onExplore),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 30),
          child: Wrap(
            spacing: 22,
            runSpacing: 10,
            children: [
              for (final point in const ['Made for Bhutan', 'Gym memberships live', 'Built for every sport'])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: context.brand.accent),
                    const SizedBox(width: 7),
                    Text(point, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink.body)),
                  ],
                ),
            ],
          ),
        ),
      ]),
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

  /// The slides fill the right of the window, fading into the words, with
  /// the way between them on glass under the cards. The whole window, like
  /// a stage (never shorter than what's on it).
  Widget _wide(BuildContext context, Widget words, Color bg, double top) {
    final photoLeft = layout.width * 0.4;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height.clamp(0.0, 1080.0)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              left: -200,
              top: 40,
              child: GymGlow(color: BrandColors.blue.withValues(alpha: _Ink.of(context).dark ? 0.16 : 0.08), size: 560)),
          Positioned(
            left: photoLeft,
            top: 0,
            right: 0,
            bottom: 0,
            child: _swipe(
              Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(child: _parallax(context, _SlideStage(show: _show), zoom: 0.06)),
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
                      height: 440,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(left: 0, bottom: 10, child: _card(const _MiniCard(), order: 0)),
                          Positioned(
                            right: 10,
                            bottom: 30,
                            child: _card(
                              const _FloatingNote(
                                icon: Icons.check_rounded,
                                iconColor: BrandColors.green,
                                title: 'Checked in',
                                text: 'Today, 6:42 AM',
                              ),
                              order: 1,
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
          Positioned(
            left: 0,
            right: 0,
            bottom: _Layout.overlap + 62,
            child: _Frame(
              layout: layout,
              child: Row(
                children: [
                  const Spacer(flex: 11),
                  const SizedBox(width: 40),
                  Expanded(
                    flex: 10,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FadeSlideIn(
                        delay: const Duration(milliseconds: 900),
                        child: _SlideControls(show: _show),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The words, then the slides as a rounded card (swiped between, the way
  /// between them over its top) with the membership card and the check-in
  /// over it.
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
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _swipe(_SlideStage(show: _show)),
                              // A shade under the ticks and the sport's name,
                              // so they read over any photo.
                              const IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Color(0x8C081428), Color(0x00081428)],
                                      stops: [0, 0.4],
                                    ),
                                  ),
                                ),
                              ),
                              const IgnorePointer(child: CustomPaint(painter: GymStripesPainter())),
                              Positioned(
                                top: 8,
                                left: 14,
                                right: 12,
                                child: _SlideControls(show: _show, compact: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 0,
                        child: Transform.scale(
                            scale: layout.medium ? 1 : 0.86,
                            alignment: Alignment.bottomLeft,
                            child: _card(const _MiniCard(), order: 0)),
                      ),
                      Positioned(
                        right: 12,
                        top: 88,
                        child: _card(
                          const _FloatingNote(
                            icon: Icons.check_rounded,
                            iconColor: BrandColors.green,
                            title: 'Checked in',
                            text: 'Today, 6:42 AM',
                          ),
                          order: 1,
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

// ─── The top's slides ──────────────────────────────────────────────────────

/// One sport in the top's slide show, from the sports photography already
/// in the app (local, so the page never waits on an image service).
class _Slide {
  /// Its photo in assets/welcome.
  final String photo;
  final String name;

  /// What the photo keeps in view as it fills its space.
  final Alignment alignment;

  /// Where it slowly draws closer to (the ball, the player).
  final Alignment focus;

  const _Slide(this.photo, this.name, {this.alignment = Alignment.center, this.focus = Alignment.center});
}

const _slides = [
  _Slide('outdoor', 'Football',
      alignment: Alignment(0.55, 0), focus: Alignment(0.45, -0.35)),
  _Slide('indoor', 'Basketball',
      alignment: Alignment(-0.3, 0), focus: Alignment(-0.1, -0.5)),
  _Slide('racket', 'Tennis', focus: Alignment(0, 0.1)),
  _Slide('swimming', 'Swimming'),
  _Slide('hero', 'Strength', focus: Alignment(-0.1, -0.5)),
  _Slide('yoga', 'Yoga', focus: Alignment(0, -0.2)),
];

/// A photo on the stage: [reveal] sweeps it in; [life] draws it closer
/// while it shows (and on while the next sweeps over it).
class _SlideLayer {
  final int serial;
  final _Slide slide;
  final AnimationController reveal;
  final AnimationController life;

  _SlideLayer({required this.serial, required this.slide, required this.reveal, required this.life});

  void stop() {
    reveal.stop();
    life.stop();
  }

  void dispose() {
    reveal.dispose();
    life.dispose();
  }
}

/// The top's slide show: which sport is showing, the photos still sweeping
/// in over it, and the clock that moves it on. It plays every sport twice
/// and then rests (Play starts it again), rests while the top is out of
/// sight, and stands still when motion is reduced (the arrows and ticks
/// still change sport, at once).
class _SlideShow extends ChangeNotifier {
  _SlideShow(this._vsync) {
    _clock = AnimationController(vsync: _vsync, duration: dwell)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });
  }

  /// How long each sport shows, from when it starts to sweep in.
  static const dwell = Duration(milliseconds: 6500);

  /// How long a photo takes to sweep in.
  static const sweep = Duration(milliseconds: 1150);

  /// Times through every sport before the show rests.
  static const rounds = 2;

  final TickerProvider _vsync;
  late final AnimationController _clock;
  Timer? _intro;

  /// The photos on the stage, bottom first; the top one may still be
  /// sweeping in.
  final layers = <_SlideLayer>[];

  /// The sport showing (or sweeping in).
  int index = 0;

  /// Whether it moves on by itself (Pause stops it).
  bool playing = false;

  bool _started = false;
  bool _still = false;
  bool _visible = true;
  int _serial = 0;
  int _advances = 0;

  /// How far through its time the showing sport is, 0 to 1.
  Animation<double> get progress => _clock;

  /// Motion is reduced: no clock, no sweeping, no drift.
  bool get still => _still;

  bool get _moving => playing && _visible && !_still;

  /// Starts the show (sweeping the first sport in, a moment after the page
  /// arrives), or stills it or sets it going when [still] changes.
  void setStill(bool still) {
    if (_started && still == _still) return;
    final first = !_started;
    _started = true;
    _still = still;
    playing = !still;
    if (first) {
      _show(0, delay: still ? null : const Duration(milliseconds: 250));
      return;
    }
    if (still) {
      _intro?.cancel();
      _pause();
      if (layers.isNotEmpty) layers.last.reveal.value = 1;
    } else {
      _resume();
    }
    notifyListeners();
  }

  /// Rests the show while the top is out of sight.
  void setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    visible ? _resume() : _pause();
  }

  void go(int slide) {
    if (slide == index && layers.isNotEmpty) return;
    _show(slide);
  }

  void next() => go((index + 1) % _slides.length);
  void previous() => go((index - 1 + _slides.length) % _slides.length);

  /// Pause, or Play (from the start of a round when it had rested).
  void toggle() {
    if (_still) return;
    playing = !playing;
    if (playing) {
      if (_advances >= _slides.length * rounds) _advances = 0;
      _resume();
    } else {
      _pause();
    }
    notifyListeners();
  }

  /// Puts [slide] on top, to sweep in over the one showing.
  void _show(int slide, {Duration? delay}) {
    index = slide;
    final layer = _SlideLayer(
      serial: _serial++,
      slide: _slides[slide],
      reveal: AnimationController(vsync: _vsync, duration: sweep),
      life: AnimationController(vsync: _vsync, duration: dwell + sweep),
    );
    layer.reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed) _settled(layer);
    });
    layers.add(layer);
    _clock.value = 0;
    if (_still) {
      layer.reveal.value = 1;
    } else if (delay != null) {
      _intro = Timer(delay, () => _begin(layer));
    } else {
      _begin(layer);
    }
    notifyListeners();
  }

  void _begin(_SlideLayer layer) {
    if (_still) return;
    layer.reveal.forward();
    if (_moving) {
      layer.life.forward();
      _clock.forward();
    }
  }

  /// [layer] covers the stage: the photos under it go.
  void _settled(_SlideLayer layer) {
    final at = layers.indexOf(layer);
    if (at <= 0) return;
    final gone = layers.sublist(0, at);
    layers.removeRange(0, at);
    for (final old in gone) {
      old.stop();
    }
    notifyListeners();
    // Once the stage has rebuilt without them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final old in gone) {
        old.dispose();
      }
    });
  }

  void _advance() {
    _advances++;
    if (_advances >= _slides.length * rounds) playing = false;
    _show((index + 1) % _slides.length);
  }

  void _pause() {
    _clock.stop();
    for (final layer in layers) {
      layer.life.stop();
    }
  }

  void _resume() {
    if (!_moving) return;
    for (final layer in layers) {
      if (layer.reveal.value > 0 && !layer.life.isCompleted) layer.life.forward();
    }
    if (layers.isNotEmpty && layers.last.reveal.value > 0) _clock.forward();
  }

  @override
  void dispose() {
    _intro?.cancel();
    _clock.dispose();
    for (final layer in layers) {
      layer.dispose();
    }
    super.dispose();
  }
}

/// The slide show's photos, filling their space: each new one sweeps in
/// from the right behind a navy and an orange band (the page's stripes),
/// pushing the one under it aside and into shade, then draws slowly closer
/// while it shows.
class _SlideStage extends StatelessWidget {
  final _SlideShow show;

  const _SlideStage({required this.show});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: show,
        builder: (context, _) {
          final layers = show.layers;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < layers.length; i++)
                _SlideLayerView(
                  key: ValueKey(layers[i].serial),
                  layer: layers[i],
                  cover: i + 1 < layers.length ? layers[i + 1].reveal : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SlideLayerView extends StatelessWidget {
  final _SlideLayer layer;

  /// The next photo sweeping in over this one, if any.
  final Animation<double>? cover;

  const _SlideLayerView({super.key, required this.layer, this.cover});

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final over = cover;
    final photo = GymPhoto(layer.slide.photo, alignment: layer.slide.alignment);
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: Listenable.merge([layer.reveal, layer.life, if (over != null) over]),
        child: photo,
        builder: (context, photo) {
          final shown = still ? 1.0 : Motion.easeInOut.transform(layer.reveal.value);
          final covered = still || over == null ? 0.0 : Motion.easeInOut.transform(over.value);
          // It slides in a little as it sweeps, and aside as the next one
          // does; a hair larger than its space, so the slide never shows an
          // edge.
          final dx = box.maxWidth * (0.04 * (1 - shown) - 0.03 * covered);
          final image = still
              ? photo!
              : Transform.translate(
                  offset: Offset(dx, 0),
                  child: Transform.scale(
                    scale: 1.04,
                    child: Transform.scale(
                      scale: 1 + 0.05 * layer.life.value,
                      alignment: layer.slide.focus,
                      child: photo,
                    ),
                  ),
                );
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipPath(
                clipper: _SweepClipper(shown),
                clipBehavior: shown >= 1 ? Clip.none : Clip.antiAlias,
                child: image,
              ),
              if (covered > 0) IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.3 * covered))),
              if (shown > 0 && shown < 1) IgnorePointer(child: CustomPaint(painter: _SweepBandsPainter(shown))),
            ],
          );
        },
      ),
    );
  }
}

/// Where a sweeping photo's edge is, [shown] of the way across [size]: its
/// top and its foot, leaning like the page's stripes. Off to the right at
/// 0, off to the left (bands and all) at 1.
(double, double) _sweepEdge(Size size, double shown) {
  final slant = size.height * 0.45;
  const bands = _SweepBandsPainter.width;
  final top = (size.width + slant + bands) * (1 - shown) - bands * shown;
  return (top, top - slant);
}

/// The part of the stage a sweeping photo has covered.
class _SweepClipper extends CustomClipper<Path> {
  final double shown;

  const _SweepClipper(this.shown);

  @override
  Path getClip(Size size) {
    if (shown >= 1) return Path()..addRect(Offset.zero & size);
    final (top, foot) = _sweepEdge(size, shown);
    final right = top > size.width ? top : size.width;
    return Path()
      ..moveTo(top, 0)
      ..lineTo(right, 0)
      ..lineTo(right, size.height)
      ..lineTo(foot, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_SweepClipper oldClipper) => oldClipper.shown != shown;
}

/// The navy and orange bands leading a sweeping photo's edge.
class _SweepBandsPainter extends CustomPainter {
  static const orange = 12.0;
  static const navy = 30.0;
  static const width = orange + navy;

  final double shown;

  const _SweepBandsPainter(this.shown);

  @override
  void paint(Canvas canvas, Size size) {
    final (top, foot) = _sweepEdge(size, shown);
    final h = size.height;
    // From and to, leftward of the edge.
    Path band(double from, double to) => Path()
      ..moveTo(top - to, 0)
      ..lineTo(top - from, 0)
      ..lineTo(foot - from, h)
      ..lineTo(foot - to, h)
      ..close();
    canvas.drawPath(band(orange, width), Paint()..color = BrandColors.navy.withValues(alpha: 0.92));
    // A pixel over the photo's edge, so no seam shows between.
    canvas.drawPath(band(-1, orange), Paint()..color = BrandColors.orange);
  }

  @override
  bool shouldRepaint(_SweepBandsPainter oldDelegate) => oldDelegate.shown != shown;
}

/// Which sport is showing and the way between them, on polished glass under
/// the photos: its number and name set like a scoreboard, a slim track whose
/// segment for the sport showing stretches out (tap one to see that sport),
/// the sport before and after, and beside them Pause, ringed by the time
/// the sport has left. A gleam crosses the glass as each sport arrives. Over
/// the photo's top on a phone ([compact]), where a swipe moves between them.
class _SlideControls extends StatelessWidget {
  final _SlideShow show;
  final bool compact;

  const _SlideControls({required this.show, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: show,
      builder: (context, _) => compact ? _compact(context) : _panel(context),
    );
  }

  Widget _panel(BuildContext context) {
    final panel = _Glass(
      radius: 30,
      gleam: show.index,
      child: SizedBox(
        height: 60,
        child: LayoutBuilder(
          builder: (context, box) {
            // The track needs room; in a narrow window the name takes it.
            final roomy = box.maxWidth >= 420;
            return Row(
              children: [
                const SizedBox(width: 24),
                _SlideNumber(index: show.index),
                const _FadedRule(height: 30),
                if (roomy) ...[
                  SizedBox(width: 112, child: _SlideName(index: show.index)),
                  const SizedBox(width: 4),
                  Expanded(child: _SlideTrack(show: show)),
                  const SizedBox(width: 18),
                ] else ...[
                  Expanded(child: _SlideName(index: show.index)),
                  const SizedBox(width: 10),
                ],
                _arrow(context, Icons.arrow_back_rounded, 'Previous sport', show.previous),
                const SizedBox(width: 6),
                _arrow(context, Icons.arrow_forward_rounded, 'Next sport', show.next),
                const SizedBox(width: 10),
              ],
            );
          },
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Row(
        children: [
          Expanded(child: panel),
          if (!show.still) ...[const SizedBox(width: 12), _pause(context, size: 60, onPhoto: false)],
        ],
      ),
    );
  }

  Widget _compact(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SlideTrack(show: show, onPhoto: true),
        Row(
          children: [
            _SlideNumber(index: show.index, onPhoto: true),
            const _FadedRule(height: 22, onPhoto: true, gap: 12),
            Expanded(child: _SlideName(index: show.index, onPhoto: true)),
            if (!show.still) _pause(context, size: 40, onPhoto: true),
          ],
        ),
      ],
    );
  }

  /// A faint hairline circle that warms to orange under the mouse.
  Widget _arrow(BuildContext context, IconData icon, String tooltip, VoidCallback onPressed) {
    final ink = _Ink.of(context);
    final hairline = ink.pick(LightColors.navy.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.16));
    final rest = ink.heading.withValues(alpha: 0.78);
    bool lit(Set<WidgetState> states) => states.contains(WidgetState.hovered) || states.contains(WidgetState.focused);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.square(40)),
        minimumSize: const WidgetStatePropertyAll(Size.square(40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(CircleBorder()),
        side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(color: lit(states) ? BrandColors.orange.withValues(alpha: 0.7) : hairline)),
        foregroundColor: WidgetStateProperty.resolveWith((states) => lit(states) ? BrandColors.orange : rest),
        backgroundColor: WidgetStateProperty.resolveWith((states) => lit(states)
            ? BrandColors.orange.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: ink.dark ? 0.04 : 0.35)),
        overlayColor: WidgetStatePropertyAll(BrandColors.orange.withValues(alpha: 0.1)),
      ),
    );
  }

  /// Pause (or Play) on its own glass, ringed by how much of the showing
  /// sport's time has gone.
  Widget _pause(BuildContext context, {required double size, required bool onPhoto}) {
    final ink = _Ink.of(context);
    final face = Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(onPhoto ? 3 : 5),
            child: AnimatedBuilder(
              animation: show.progress,
              builder: (context, _) => CustomPaint(
                painter: _RingPainter(
                  value: show.progress.value,
                  track: onPhoto
                      ? Colors.white.withValues(alpha: 0.28)
                      : ink.pick(LightColors.navy.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.12)),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: show.toggle,
          tooltip: show.playing ? 'Pause the slides' : 'Play the slides',
          icon: Icon(show.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: size * 0.38),
          style: IconButton.styleFrom(
            foregroundColor: onPhoto ? Colors.white : ink.heading.withValues(alpha: 0.85),
            hoverColor: BrandColors.orange.withValues(alpha: 0.1),
            fixedSize: Size.square(size),
            minimumSize: Size.square(size),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    return _Glass(
      radius: size / 2,
      onPhoto: onPhoto,
      gleam: show.index,
      gleamDelay: const Duration(milliseconds: 260),
      child: face,
    );
  }
}

/// The track's and the ring's orange: full where it leads, fading to peach
/// behind.
const _peach = Color(0xFFFFC29B);

/// Polished glass: what's behind it blurred under a soft, see-through wash
/// (deep navy in the dark; clear over a photo), light pooled on its upper
/// half, a rim catching the light along its top, and a soft, wide shadow.
/// When [gleam] changes a streak of light crosses it.
class _Glass extends StatelessWidget {
  final double radius;
  final Widget child;

  /// Over a photo: clearer, with a brighter rim.
  final bool onPhoto;

  /// What sends a gleam across it when it changes; none when null.
  final Object? gleam;
  final Duration gleamDelay;

  const _Glass({
    required this.radius,
    required this.child,
    this.onPhoto = false,
    this.gleam,
    this.gleamDelay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final corners = BorderRadius.circular(radius);
    // An amount for light or dark, mixed while the theme switches.
    double mix(double light, double dark) => light + (dark - light) * ink.t;
    final (List<Color> wash, double sheen, Color rimTop, Color rimFoot, double shine) = onPhoto
        ? (
            [Colors.white.withValues(alpha: 0.24), Colors.white.withValues(alpha: 0.06)],
            0.32,
            Colors.white.withValues(alpha: 0.75),
            Colors.white.withValues(alpha: 0.08),
            0.45,
          )
        : (
            [
              ink.pick(Colors.white.withValues(alpha: 0.72), const Color(0xB31E2D4F)),
              ink.pick(Colors.white.withValues(alpha: 0.48), const Color(0x990B1630)),
            ],
            mix(0.8, 0.12),
            Colors.white.withValues(alpha: mix(1, 0.4)),
            Colors.white.withValues(alpha: mix(0.3, 0.05)),
            mix(0.7, 0.18),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: [
          BoxShadow(
            color: onPhoto
                ? Colors.black.withValues(alpha: 0.18)
                : ink.pick(LightColors.navy.withValues(alpha: 0.13), Colors.black.withValues(alpha: 0.42)),
            blurRadius: onPhoto ? 18 : 44,
            spreadRadius: -8,
            offset: Offset(0, onPhoto ? 8 : 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: CustomPaint(
            foregroundPainter: _RimPainter(radius: radius, top: rimTop, foot: rimFoot),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: wash),
              ),
              child: Stack(
                children: [
                  // Light pooled on the upper half, as on polished glass.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white.withValues(alpha: sheen), Colors.white.withValues(alpha: 0)],
                            stops: const [0, 0.55],
                          ),
                        ),
                      ),
                    ),
                  ),
                  child,
                  if (gleam != null)
                    Positioned.fill(
                      child: _Gleam(trigger: gleam!, delay: gleamDelay, color: Colors.white.withValues(alpha: shine)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glass's rim: bright along the top where it catches the light,
/// fading away toward the foot.
class _RimPainter extends CustomPainter {
  final double radius;
  final Color top;
  final Color foot;

  const _RimPainter({required this.radius, required this.top, required this.foot});

  @override
  void paint(Canvas canvas, Size size) {
    const width = 1.2;
    final rim = RRect.fromRectAndRadius((Offset.zero & size).deflate(width / 2), Radius.circular(radius - width / 2));
    canvas.drawRRect(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, foot],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.top != top || oldDelegate.foot != foot;
}

/// A streak of light that crosses once, leaning like the stripes: when it
/// first shows (a moment after the glass arrives) and each time [trigger]
/// changes. Nothing when motion is reduced.
class _Gleam extends StatefulWidget {
  final Object trigger;
  final Duration delay;
  final Color color;

  const _Gleam({required this.trigger, required this.color, this.delay = Duration.zero});

  @override
  State<_Gleam> createState() => _GleamState();
}

class _GleamState extends State<_Gleam> with SingleTickerProviderStateMixin {
  static const _cross = Duration(milliseconds: 1100);

  late final AnimationController _c = AnimationController(vsync: this, duration: widget.delay + _cross);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.delay.inMilliseconds / (widget.delay + _cross).inMilliseconds, 1, curve: Motion.easeInOut),
  );
  Timer? _first;

  @override
  void initState() {
    super.initState();
    // After the glass has risen into place.
    _first = Timer(const Duration(milliseconds: 1400), _shine);
  }

  @override
  void didUpdateWidget(_Gleam old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _shine();
  }

  void _shine() {
    if (!mounted || reduceMotion(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _first?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) => CustomPaint(painter: _GleamPainter(t: _t.value, color: widget.color)),
      ),
    );
  }
}

class _GleamPainter extends CustomPainter {
  final double t;
  final Color color;

  const _GleamPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final h = size.height;
    final band = math.max(44.0, size.width * 0.14);
    final lean = h * 0.7;
    // From wholly off the left to wholly off the right.
    final left = -band - lean + (size.width + band + lean) * t;
    final streak = Path()
      ..moveTo(left + lean, 0)
      ..lineTo(left + lean + band, 0)
      ..lineTo(left + band, h)
      ..lineTo(left, h)
      ..close();
    canvas.drawPath(
      streak,
      Paint()
        ..shader = LinearGradient(colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)])
            .createShader(Rect.fromLTWH(left, 0, band + lean, h)),
    );
  }

  @override
  bool shouldRepaint(_GleamPainter oldDelegate) => oldDelegate.t != t || oldDelegate.color != color;
}

/// A thin upright rule that fades away at both ends.
class _FadedRule extends StatelessWidget {
  final double height;
  final double gap;

  /// White over a photo, rather than on the glass.
  final bool onPhoto;

  const _FadedRule({required this.height, this.gap = 16, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final line = onPhoto
        ? Colors.white.withValues(alpha: 0.55)
        : ink.pick(LightColors.navy.withValues(alpha: 0.2), Colors.white.withValues(alpha: 0.24));
    return Container(
      width: 1,
      height: height,
      margin: EdgeInsets.symmetric(horizontal: gap),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0), line, line.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// A thin ring, filled clockwise from the top by [value]: orange at its
/// head, fading to peach behind.
class _RingPainter extends CustomPainter {
  static const stroke = 2.0;

  final double value;
  final Color track;

  const _RingPainter({required this.value, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawOval(rect, line..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      // Its own paint: the track's faint colour would dim the gradient.
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: const [_peach, BrandColors.orange],
          stops: [0, value.clamp(0.01, 1.0)],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.value != value || oldDelegate.track != track;
}

/// The showing sport's number, large and slanted like the headline and
/// fading downward, out of how many, small: "02 /06". The number rolls over
/// as the sport changes.
class _SlideNumber extends StatelessWidget {
  final int index;

  /// White over a photo, rather than on the glass.
  final bool onPhoto;

  const _SlideNumber({required this.index, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    String two(int n) => n.toString().padLeft(2, '0');
    final ink0 = onPhoto ? Colors.white : ink.heading;
    final fade = [ink0, ink0.withValues(alpha: onPhoto ? 0.6 : 0.38)];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        _Roll(
          index: index,
          child: ShaderMask(
            key: ValueKey(index),
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: fade,
            ).createShader(bounds),
            // Room for the slant: an italic figure leans past its own box
            // at the top right, where the roll's clip and the fade would
            // cut it off.
            child: Padding(
              padding: EdgeInsets.only(right: onPhoto ? 5 : 7),
              child: Text(
                two(index + 1),
                style: TextStyle(
                  fontSize: onPhoto ? 22 : 28,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -0.6,
                  height: 1.1,
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        Text(
          '/${two(_slides.length)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: onPhoto ? Colors.white.withValues(alpha: 0.7) : context.brand.muted.withValues(alpha: 0.8),
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: onPhoto ? const [Shadow(color: Color(0x80000000), blurRadius: 10)] : null,
          ),
        ),
      ],
    );
  }
}

/// The showing sport's name in spaced capitals, rolling over as it changes.
class _SlideName extends StatelessWidget {
  final int index;

  /// White over a photo, rather than on the glass.
  final bool onPhoto;

  const _SlideName({required this.index, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    return _Roll(
      index: index,
      duration: const Duration(milliseconds: 720),
      child: Text(
        _slides[index].name.toUpperCase(),
        key: ValueKey(index),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: onPhoto ? 12 : 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.8,
          height: 1.2,
          color: onPhoto ? Colors.white : ink.heading.withValues(alpha: 0.82),
          shadows: onPhoto ? const [Shadow(color: Color(0x80000000), blurRadius: 10)] : null,
        ),
      ),
    );
  }
}

/// [child] (keyed by [index]) rolls up into place as the one before slips
/// away upward, gone by halfway so the two never show at once; at once when
/// motion is reduced.
class _Roll extends StatelessWidget {
  final int index;
  final Duration duration;
  final Widget child;

  const _Roll({required this.index, required this.child, this.duration = const Duration(milliseconds: 640)});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return AnimatedSwitcher(
      duration: duration,
      // A new builder each time, so the one leaving goes up, not back down.
      transitionBuilder: (child, animation) {
        final entering = child.key == ValueKey(index);
        final rise = Tween(begin: Offset(0, entering ? 0.9 : -0.9), end: Offset.zero)
            .chain(CurveTween(curve: Motion.ease));
        return ClipRect(
          child: SlideTransition(
            position: animation.drive(rise),
            child: FadeTransition(opacity: animation.drive(CurveTween(curve: const Interval(0.5, 1))), child: child),
          ),
        );
      },
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

/// A slim track, a segment for each sport: the one showing stretches out,
/// glowing orange fading to peach, as the others draw in; tap a segment to
/// see that sport.
class _SlideTrack extends StatelessWidget {
  final _SlideShow show;

  /// Over a photo, rather than on the glass.
  final bool onPhoto;

  const _SlideTrack({required this.show, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(context);
    final rest = onPhoto
        ? Colors.white.withValues(alpha: 0.38)
        : ink.pick(LightColors.navy.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.16));
    final duration = Motion.of(context, const Duration(milliseconds: 520));
    const gap = 4.0;
    return LayoutBuilder(
      builder: (context, box) {
        // The one showing is three shares wide, the rest one each.
        final share = ((box.maxWidth - gap * (_slides.length - 1)) / (_slides.length + 2)).clamp(0.0, 400.0);
        return Row(
          children: [
            for (var i = 0; i < _slides.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Semantics(
                button: true,
                selected: i == show.index,
                label: 'Show ${_slides[i].name}, ${i + 1} of ${_slides.length}',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => show.go(i),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Motion.ease,
                      width: share * (i == show.index ? 3 : 1),
                      height: 28,
                      alignment: Alignment.center,
                      child: AnimatedContainer(
                        duration: duration,
                        curve: Motion.ease,
                        height: i == show.index ? 3 : 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: i == show.index ? const [_peach, BrandColors.orange] : [rest, rest],
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: BrandColors.orange.withValues(alpha: i == show.index ? 0.35 : 0),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
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

/// An illustrative member card; its sample QR is not a real member credential.
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
            colors: [Color(0xF20B1530), Color(0xF21F4FA8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 36, offset: const Offset(0, 18))
          ],
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
                          'Example member card',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: BrandColors.blue, borderRadius: BorderRadius.circular(20)),
                        child: const Text(
                          'Sample',
                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Gym membership', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                  const SizedBox(height: 10),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 25),
                      SizedBox(width: 6),
                      Flexible(
                          child: Text('QR check-in preview', style: TextStyle(color: Colors.white70, fontSize: 13))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                data: 'EXAMPLE ONLY',
                size: 78,
                padding: EdgeInsets.zero,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: BrandColors.navy),
                dataModuleStyle:
                    const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: BrandColors.navy),
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
            BoxShadow(
                color: Colors.black.withValues(alpha: ink.dark ? 0.4 : 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12)),
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
    return _Revealed(
      shown: _shown,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: duration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _shown ? 0 : rise, 0),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Whether the section around has scrolled into view, for what's in it.
class _Revealed extends InheritedWidget {
  final bool shown;

  const _Revealed({required this.shown, required super.child});

  /// Shown, or not in a section that waits (it shows at once).
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Revealed>()?.shown ?? true;

  @override
  bool updateShouldNotify(_Revealed old) => old.shown != shown;
}

/// One of a section's cards: it rises into place [order] beats after the
/// section comes into view, so a row of cards arrives one after another.
class _RevealItem extends StatefulWidget {
  final int order;
  final Widget child;

  const _RevealItem({required this.order, required this.child});

  @override
  State<_RevealItem> createState() => _RevealItemState();
}

class _RevealItemState extends State<_RevealItem> with SingleTickerProviderStateMixin {
  static const _beat = Duration(milliseconds: 80);
  late final Duration _delay = _beat * widget.order.clamp(0, 8) + const Duration(milliseconds: 150);
  late final AnimationController _c = AnimationController(vsync: this, duration: _delay + Motion.card);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(_delay.inMilliseconds / (_delay + Motion.card).inMilliseconds, 1, curve: Motion.ease),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (_Revealed.of(context) && !_c.isAnimating && !_c.isCompleted) {
      _c.forward();
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
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, 24 * (1 - _t.value)), child: child),
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
    final cells = [
      for (final (i, item) in items.indexed) _RevealItem(order: i + 2, child: _HighlightCell(item: item)),
    ];
    return Transform.translate(
      offset: const Offset(0, -_Layout.overlap),
      child: _Frame(
        layout: layout,
        child: FadeSlideIn(
          delay: const Duration(milliseconds: 200),
          child: Container(
          padding: EdgeInsets.symmetric(vertical: 24, horizontal: layout.wide ? 8 : 16),
          decoration: BoxDecoration(
            color: ink.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: brand.glassBorder),
            boxShadow: ink.shadow(light: 0.08, dark: 0.4, blur: 32, dy: 14),
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
      ),
    );
  }
}

/// What SportsHub does, one thing: under the mouse its icon's well warms to
/// orange and lifts a little.
class _HighlightCell extends StatefulWidget {
  final _Highlight item;

  const _HighlightCell({required this.item});

  @override
  State<_HighlightCell> createState() => _HighlightCellState();
}

class _HighlightCellState extends State<_HighlightCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ink = _Ink.of(context);
    final accent = context.brand.accent;
    final hover = _hover && !reduceMotion(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          AnimatedContainer(
            duration: Motion.hover,
            curve: Motion.ease,
            width: 52,
            height: 52,
            transform: Matrix4.translationValues(0, hover ? -3 : 0, 0),
            decoration: BoxDecoration(
              color: hover ? accent.withValues(alpha: 0.14) : ink.tint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(item.icon, size: 26, color: accent),
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

/// Services currently available in SportsHub and links contributed by the
/// enabled service modules.
class _Services extends StatelessWidget {
  final _Layout layout;
  final List<ModuleMenuItem> serviceLinks;
  final VoidCallback onFindGym;

  const _Services({super.key, required this.layout, required this.serviceLinks, required this.onFindGym});

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
          'Explore Sports & Services',
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
          serviceLinks.isEmpty
              ? 'Manage gym memberships and check-ins in SportsHub. The platform is built to connect more sports and facilities across Bhutan.'
              : 'Manage gym memberships and check-ins in SportsHub. Ground booking and tournaments open on their existing service for now.',
          style: TextStyle(fontSize: 17, height: 1.55, color: ink.body),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _PillButton(label: 'Find a gym', icon: Icons.arrow_forward_rounded, onPressed: onFindGym),
            for (final link in serviceLinks)
              _PillButton(
                label: link.title,
                icon: link.icon,
                outlined: true,
                onPressed: () => link.open(context),
              ),
          ],
        ),
      ],
    );
    final tiles = _Grid(
      columns: layout.medium ? 3 : 2,
      children: [
        for (final (i, s) in services.indexed)
          _RevealItem(order: i, child: _ServiceTile(service: s, onTap: s.open ? onFindGym : null)),
      ],
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
    final ink = _Ink.of(context);
    final hover = _hover && !reduceMotion(context);
    // In the light, a navy haze under the photo rather than a grey smudge.
    final shade = ink.pick(LightColors.navy, Colors.black);
    return Semantics(
      button: widget.onTap != null,
      label: '${service.name}, $badge',
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: AnimatedContainer(
          duration: Motion.hover,
          curve: Motion.ease,
          transform: Matrix4.translationValues(0, hover ? -4 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: shade.withValues(alpha: hover ? (ink.dark ? 0.28 : 0.2) : (ink.dark ? 0.14 : 0.1)),
                blurRadius: hover ? 26 : 14,
                spreadRadius: ink.dark ? 0 : -2,
                offset: Offset(0, hover ? 14 : 6),
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
                    scale: hover ? 1.07 : 1,
                    duration: const Duration(milliseconds: 600),
                    curve: Motion.ease,
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
                  AnimatedPositioned(
                    duration: Motion.hover,
                    curve: Motion.ease,
                    left: 10,
                    right: 10,
                    bottom: hover ? 18 : 14,
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
          'The Digital Home for\nSports & Fitness',
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
          'SportsHub connects people, facilities and sports services through one platform built for Bhutan. '
          'Gym memberships are managed here, while enabled sports services connect members to their existing tools.',
          style: TextStyle(fontSize: 16, height: 1.55, color: ink.body),
        ),
        const SizedBox(height: 16),
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Check(point),
          ),
        const SizedBox(height: 16),
        // Navy in the light, blue in the dark; white words on either (they
        // were navy on navy in the light, so the button read as empty).
        _PillButton(
          label: 'Know More',
          icon: Icons.arrow_forward_rounded,
          color: ink.dark ? BrandColors.blue : LightColors.navy,
          foreground: ink.dark ? BrandColors.navy : Colors.white,
          onPressed: onKnowMore,
        ),
      ],
    );
    final factList = _Grid(
      columns: layout.wide ? 1 : (layout.medium ? 3 : 1),
      spacing: 22,
      children: [
        for (final (i, (icon, value, label)) in facts.indexed)
          _RevealItem(
            order: i + 2,
            child: Row(
            children: [
              Icon(icon, size: 32, color: context.brand.accent),
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
          ),
      ],
    );
    return Container(
      margin: EdgeInsets.only(bottom: layout.section),
      padding: EdgeInsets.symmetric(vertical: layout.section * 0.75),
      color: ink.pick(LightColors.backgroundAlt, Colors.white.withValues(alpha: 0.03)),
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
                    BoxShadow(
                        color: BrandColors.navy.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 16)),
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
                          child: Container(
                              width: 54, height: height * 1.2, color: BrandColors.orange.withValues(alpha: 0.9)),
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
              TextSpan(
                children: [
                  const TextSpan(text: 'Get Started in '),
                  // On the light page, the orange that reads as text.
                  TextSpan(
                      text: '5 Simple Steps',
                      style: TextStyle(color: ink.dark ? BrandColors.orange : LightColors.orangeText)),
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
                  // Each step, then the arrow to the next, in turn: the
                  // journey reads left to right as it arrives.
                  for (var i = 0; i < steps.length; i++) ...[
                    if (i > 0)
                      _RevealItem(
                        order: i * 2 - 1,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 28),
                          child: Icon(Icons.arrow_forward_rounded, color: context.brand.accent, size: 22),
                        ),
                      ),
                    Expanded(child: _RevealItem(order: i * 2, child: _StepColumn(number: i + 1, step: steps[i]))),
                  ],
                ],
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      _RevealItem(order: i, child: _StepRow(number: i + 1, step: steps[i])),
                  ],
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
    _PlanKind('Long Term', 'For the committed', '6 months · 1 year',
        ['Your card and visits in one place', 'Fewer renewals to think of']),
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
    final cards = [
      for (final (i, k) in kinds.indexed)
        _RevealItem(order: i + 1, child: HoverLift(radius: 20, lift: 4, child: _PlanCard(kind: k, onFindGym: onFindGym))),
    ];
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
    final orangeTint = brand.accent.withValues(alpha: ink.dark ? 0.12 : 0.05);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: kind.featured ? Color.alphaBlend(orangeTint, ink.card) : ink.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kind.featured ? brand.accent : brand.glassBorder, width: kind.featured ? 1.6 : 1),
        boxShadow: ink.shadow(light: kind.featured ? 0.1 : 0.06),
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

  // As the gyms work today: the front desk registers members (no account
  // needed). SportsHub's assistant answers from the same facts
  // (supabase/functions/ask-sportshub/reply.ts): change both together.
  static const questions = [
    (
      'How do I join a gym?',
      "You don't need a SportsHub account. Go to the gym: the front desk registers you (your details and a "
          'photo), sells you a package for 1 to 24 months and takes your payment. Your QR card comes on '
          'WhatsApp or as a download.',
    ),
    (
      'What payment methods are accepted?',
      'You pay the gym directly: cash, mBoB or bank transfer. The desk records it in SportsHub, with the '
          'journal number for mBoB and transfers.',
    ),
    (
      'When does my membership start and end?',
      'It starts on the day you join and ends on the same date that many months later: join on 8 November '
          'for 3 months and it ends on 8 February, and you can still come that day. Renew early and the new '
          'package starts the day the current one ends, so you never lose days.',
    ),
    (
      'How do I check in?',
      'Show your QR card at the counter. The staff scan it, or type your 6-character member code or your '
          'phone number. It works while your package covers that day.',
    ),
    (
      'What if I lose my card?',
      'Ask the front desk for a new card. Your old one stops working, so nobody else can use it.',
    ),
    (
      'Can I cancel my membership?',
      'Talk to your gym: changes and refunds are up to them.',
    ),
    (
      'How do I put my gym on SportsHub?',
      'Sign up, then Register your venue, choose Gym and add your packages and prices. Once the SportsHub '
          'team has verified your gym, add your staff and start registering members at the front desk.',
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
        color: ink.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.glassBorder),
        boxShadow: ink.dark ? null : ink.shadow(light: 0.05, blur: 18, dy: 6),
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
                colors: [BrandColors.navy, BrandColors.slateNavy],
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
                Positioned(
                    right: -60, top: -120, child: GymGlow(color: BrandColors.orange.withValues(alpha: 0.3), size: 320)),
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
    // The white-lettered logo, straight on the footer's navy, light theme
    // or dark.
    const logo = SportsHubLogo(height: 60, onDark: true);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [BrandColors.navy, BrandColors.night],
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
    (0.0, 0.62),
    (0.07, 0.34),
    (0.14, 0.56),
    (0.23, 0.18),
    (0.32, 0.5),
    (0.41, 0.3),
    (0.5, 0.56),
    (0.6, 0.12),
    (0.7, 0.46),
    (0.79, 0.24),
    (0.89, 0.52),
    (1.0, 0.3),
  ];
  static const _near = [
    (0.0, 0.82),
    (0.1, 0.6),
    (0.2, 0.8),
    (0.3, 0.54),
    (0.42, 0.84),
    (0.55, 0.6),
    (0.66, 0.86),
    (0.78, 0.62),
    (0.9, 0.82),
    (1.0, 0.66),
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

/// A round-ended button: filled with [color] (the brand's orange unless
/// given) in [foreground] (navy unless given), or [outlined]. It gives a
/// little under a press, and its arrow nudges forward under the mouse.
class _PillButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool outlined;
  final Color? color;
  final Color foreground;

  /// Smaller, for the bar.
  final bool compact;

  const _PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.color,
    this.foreground = BrandColors.navy,
    this.compact = false,
  });

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(child: _button(context)),
    );
  }

  Widget _button(BuildContext context) {
    final label = widget.label;
    final onPressed = widget.onPressed;
    final icon = widget.icon;
    final outlined = widget.outlined;
    final compact = widget.compact;
    final color = widget.color ?? context.brand.accent;
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
        if (icon != null) ...[
          const SizedBox(width: 8),
          AnimatedSlide(
            offset: Offset(_hover && !reduceMotion(context) ? 0.2 : 0, 0),
            duration: Motion.hover,
            curve: Motion.ease,
            child: Icon(icon, size: 19),
          ),
        ],
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
          if (!compact)
            BoxShadow(
                color: color.withValues(alpha: ink.dark ? 0.35 : 0.26), blurRadius: ink.dark ? 20 : 16, offset: const Offset(0, 8)),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: widget.foreground,
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
