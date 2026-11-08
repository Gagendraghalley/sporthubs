import 'package:flutter/material.dart';

import '../theme/brand.dart';

// Motion every service shares: numbers that count up, cards that arrive one
// after another and lift under the mouse, and shimmering shapes where a page
// is still loading. All of it stands still when the device asks for less
// motion (MediaQuery.disableAnimations).

/// Whether the device asks for less motion.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A number that counts up to [value] when it first shows, and glides to a
/// new one when it changes. [format] writes it: `(v) => formatNu(v.round())`.
class AnimatedCount extends StatelessWidget {
  final num value;
  final String Function(num value) format;
  final TextStyle? style;
  final Duration duration;

  const AnimatedCount({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  /// A whole number: 0, 12, 1,250.
  static String whole(num v) => _grouped(v.round());

  static String _grouped(int n) {
    final s = n.abs().toString();
    final out = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final text = format(value);
    if (reduceMotion(context)) return Text(text, style: style);
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Text(v == value.toDouble() ? text : format(v), style: style),
        ),
      ),
    );
  }
}

/// [child] rises a little under the mouse, its shadow deepening: something
/// that opens. [radius] is the child's corners, for the shadow.
class HoverLift extends StatefulWidget {
  final Widget child;
  final double lift;
  final double radius;
  final bool enabled;

  const HoverLift({super.key, required this.child, this.lift = 3, this.radius = 20, this.enabled = true});

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final up = _hover && !reduceMotion(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, up ? -widget.lift : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: [
            BoxShadow(
              color: (dark ? Colors.black : BrandColors.navy).withValues(alpha: up ? (dark ? 0.35 : 0.12) : 0),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

/// [child] fades in and rises into place, [delay] after it first shows.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;

  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 14});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  static const _length = Duration(milliseconds: 420);
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.delay + _length);
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Interval(widget.delay.inMilliseconds / (widget.delay + _length).inMilliseconds, 1, curve: Curves.easeOutCubic),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - _t.value)), child: child),
      ),
    );
  }
}

/// [children] arriving one after another, [step] apart (the first eight;
/// the rest with the eighth).
List<Widget> staggered(Iterable<Widget> children, {Duration step = const Duration(milliseconds: 55)}) {
  var i = 0;
  return [
    for (final c in children) FadeSlideIn(delay: step * (i < 8 ? i++ : 8), child: c),
  ];
}

// ─── Loading ───────────────────────────────────────────────────────────────

/// A soft light sweeping across [child]'s shapes while something loads.
class Shimmer extends StatefulWidget {
  final Widget child;

  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final light = Colors.white.withValues(alpha: dark ? 0.10 : 0.65);
    return AnimatedBuilder(
      animation: _sweep,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.transparent, light, Colors.transparent],
          stops: const [0.35, 0.5, 0.65],
          transform: _Slide(_sweep.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _Slide extends GradientTransform {
  final double t;

  const _Slide(this.t);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// A grey rounded shape where something will be.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({super.key, this.width, required this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Where a page is loading: the shape of what's coming (a heading, a row of
/// tiles, cards) shimmering. [LoadingSkeleton.rows] is a few list rows, for a
/// part of a page. Clipped to a box smaller than itself; safe anywhere (no
/// LayoutBuilder, so inside rows of equal height too).
class LoadingSkeleton extends StatelessWidget {
  final String semanticsLabel;
  final bool _rows;

  const LoadingSkeleton({super.key, this.semanticsLabel = 'Loading'}) : _rows = false;

  /// A few rows of a list.
  const LoadingSkeleton.rows({super.key, this.semanticsLabel = 'Loading'}) : _rows = true;

  @override
  Widget build(BuildContext context) {
    final Widget shape;
    if (_rows) {
      shape = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              const _SkeletonRow(),
            ],
          ],
        ),
      );
    } else {
      final w = MediaQuery.sizeOf(context).width;
      final pad = w >= 900 ? 28.0 : 16.0;
      final tiles = w >= 900 ? 4 : 2;
      shape = Padding(
        padding: EdgeInsets.fromLTRB(pad, MediaQuery.paddingOf(context).top + kToolbarHeight + 24, pad, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 240, height: 28),
            const SizedBox(height: 10),
            const SkeletonBox(width: 300, height: 14),
            const SizedBox(height: 26),
            Row(
              children: [
                for (var i = 0; i < tiles; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  const Expanded(child: SkeletonBox(height: 104, radius: 20)),
                ],
              ],
            ),
            const SizedBox(height: 20),
            const SkeletonBox(height: 240, radius: 20),
            const SizedBox(height: 20),
            const SkeletonBox(height: 140, radius: 20),
          ],
        ),
      );
    }
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Shimmer(
          // Its own height in a list; clipped in a smaller box.
          child: ClipRect(
            child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), primary: false, child: shape),
          ),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SkeletonBox(width: 44, height: 44, radius: 14),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(widthFactor: 0.55, child: SkeletonBox(height: 13, radius: 6)),
              SizedBox(height: 8),
              FractionallySizedBox(widthFactor: 0.35, child: SkeletonBox(height: 11, radius: 6)),
            ],
          ),
        ),
      ],
    );
  }
}
