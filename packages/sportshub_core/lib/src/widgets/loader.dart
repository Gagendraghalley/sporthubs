import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// SportsHub's loading spinner, in the colours of the logo's 'S': an orange
/// arc that stretches and shrinks as it chases round a faint ring, and a
/// shorter blue one turning the other way inside it.
///
/// For a page, or a part of one, that is waiting. Small spinners inside
/// buttons stay Flutter's plain one, in the button's colour.
class SportsHubLoader extends StatefulWidget {
  final double size;

  /// What screen readers say.
  final String semanticsLabel;

  const SportsHubLoader({super.key, this.size = 44, this.semanticsLabel = 'Loading'});

  @override
  State<SportsHubLoader> createState() => _SportsHubLoaderState();
}

class _SportsHubLoaderState extends State<SportsHubLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _cycle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel,
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _LoaderPainter(
              cycle: _cycle,
              arc: context.brand.accent,
              inner: context.colors.tertiary,
              track: context.brand.glassBorder,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  final Animation<double> cycle;
  final Color arc;
  final Color inner;
  final Color track;

  _LoaderPainter({required this.cycle, required this.arc, required this.inner, required this.track})
      : super(repaint: cycle);

  static const _turn = 2 * math.pi;
  static const _top = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final t = cycle.value;
    final center = size.center(Offset.zero);
    final stroke = math.max(2.5, size.shortestSide * 0.09);
    final radius = size.shortestSide / 2 - stroke / 2;
    final ring = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    // The orange arc: two turns a cycle, between a quarter and three
    // quarters of the ring long, its back half fading out to the tail.
    final sweep = (0.25 + 0.5 * (0.5 - 0.5 * math.cos(_turn * t))) * _turn;
    final head = _top + 2 * _turn * t;
    final tail = head - sweep;
    canvas.drawArc(
      ring,
      tail,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          endAngle: sweep,
          colors: [arc.withValues(alpha: 0), arc, arc],
          stops: const [0, 0.55, 1],
          transform: GradientRotation(tail),
        ).createShader(ring),
    );
    // A round head (a round cap would also round the faded tail).
    canvas.drawCircle(center + Offset(math.cos(head), math.sin(head)) * radius, stroke / 2, Paint()..color = arc);

    // The blue arc inside: a turn a cycle, the other way. Too fussy small.
    if (size.shortestSide < 28) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.56),
      _top - _turn * t,
      _turn * 0.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.7
        ..strokeCap = StrokeCap.round
        ..color = inner.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_LoaderPainter old) =>
      old.cycle != cycle || old.arc != arc || old.inner != inner || old.track != track;
}
