import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';
import 'logo.dart';

/// The splash screen: the white-lettered logo in the middle of the side
/// menu's navy, a slim orange bar running under it. Shown while the app gets
/// ready (the modules load at start), in both themes.
///
/// Before Flutter starts, the launch screens show the same logo at the same
/// size and place, so the handover doesn't jump. Keep them in step:
/// - web/index.html (#splash) and web/splash/
/// - Android: res/drawable*/launch_background.xml, res/values*-v31/styles.xml
/// - iOS: Runner/Base.lproj/LaunchScreen.storyboard, LaunchImage
class SportsHubSplash extends StatelessWidget {
  const SportsHubSplash({super.key});

  /// The logo's width: 240 on a phone, 320 on anything bigger. Its middle is
  /// the screen's middle.
  static double logoWidthFor(Size screen) => screen.shortestSide >= 600 ? 320 : 240;

  /// From the logo's foot to the bar.
  static const barGap = 36.0;

  static final _logo = AssetImage(
    SportsHubLogo.assetFor(markOnly: false, onDark: true),
    package: SportsHubLogo.package,
  );

  /// Reads the logo ahead of the first frame (main, before runApp), so the
  /// splash shows it at once rather than blinking in after the launch
  /// screen. Never takes more than a few seconds, and never fails.
  static Future<void> precacheLogo() {
    final done = Completer<void>();
    final stream = _logo.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish() {
      if (!done.isCompleted) done.complete();
      stream.removeListener(listener);
    }

    listener = ImageStreamListener((_, __) => finish(), onError: (_, __) => finish());
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  @override
  Widget build(BuildContext context) {
    final width = logoWidthFor(MediaQuery.sizeOf(context));
    final height = width / SportsHubLogo.aspectRatio;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BrandColors.midnight, BrandColors.night],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Image(image: _logo, fit: BoxFit.contain, semanticLabel: 'SportsHub'),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: box.maxHeight / 2 + height / 2 + barGap,
                child: Center(child: _RunningBar(width: width / 2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The splash's bar: an orange streak running along a faint track.
class _RunningBar extends StatefulWidget {
  final double width;

  const _RunningBar({required this.width});

  @override
  State<_RunningBar> createState() => _RunningBarState();
}

class _RunningBarState extends State<_RunningBar> with SingleTickerProviderStateMixin {
  late final AnimationController _run =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final Animation<double> _eased = CurvedAnimation(parent: _run, curve: Curves.easeInOutCubic);

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.width * 0.4;
    return Semantics(
      label: 'Loading',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          width: widget.width,
          height: 4,
          child: ColoredBox(
            color: Colors.white.withValues(alpha: 0.12),
            child: AnimatedBuilder(
              animation: _eased,
              builder: (context, child) => Stack(
                children: [
                  // From just off the left to just off the right.
                  Positioned(
                    left: -streak + (widget.width + streak) * _eased.value,
                    top: 0,
                    bottom: 0,
                    width: streak,
                    child: child!,
                  ),
                ],
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                  gradient: LinearGradient(
                    colors: [Color(0x00FF8A3D), Color(0xFFFF8A3D), BrandColors.orange],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [SportsHubSplash] until [ready], then the page [builder] makes, faded in.
/// Once ready, the page updates in place like any other.
class SplashGate extends StatelessWidget {
  final bool ready;
  final WidgetBuilder builder;

  const SplashGate({super.key, required this.ready, required this.builder});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
      child: ready
          ? KeyedSubtree(key: const ValueKey('page'), child: builder(context))
          : const SportsHubSplash(key: ValueKey('splash')),
    );
  }
}
