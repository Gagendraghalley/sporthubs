import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/brand.dart';
import '../utils/bhutan_time.dart';
import 'motion.dart';

// The dashboard look every service shares: white (or dark) cards with an
// icon and a title, numbers across the top that count up, a line chart
// that draws itself in, a ring, tiles of shortcuts and a footer. Light and
// dark.

/// Text, card and shadow colours, light or dark; mixed while the theme
/// switches, so cards glide from white to navy rather than flash.
class ConsoleInk {
  /// 0 light, 1 dark ([Brand.darkness]).
  final double t;
  final List<BoxShadow> shadow;

  const ConsoleInk._(this.t, this.shadow);

  factory ConsoleInk.of(BuildContext context) {
    final brand = context.brand;
    return ConsoleInk._(brand.darkness, brand.cardShadow);
  }

  bool get dark => t >= 0.5;

  Color _pick(Color light, Color dark) => Color.lerp(light, dark, t)!;

  Color get heading => _pick(LightColors.ink, Colors.white);
  Color get body => _pick(LightColors.body, const Color(0xFFC5CCDA));
  Color get card => _pick(LightColors.card, BrandColors.slateNavy);

  /// Behind tiles and icons: the page's cool grey, or a faint white in the
  /// dark.
  Color get tint => _pick(LightColors.background, Colors.white.withValues(alpha: 0.06));
}

/// How a number moved against the period before, beside it: up in green,
/// down in red, level in grey. Only from real figures on both sides.
class ConsoleTrend extends StatelessWidget {
  final String text;

  /// Up (good), down, or neither.
  final bool? up;
  final String? tooltip;

  const ConsoleTrend({super.key, required this.text, this.up, this.tooltip});

  /// [change] as a share (0.12 is 12% up).
  factory ConsoleTrend.percent(double change, {String? tooltip}) {
    final pct = (change * 100).round();
    return ConsoleTrend(text: '${pct.abs()}%', up: pct == 0 ? null : pct > 0, tooltip: tooltip);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = switch (up) { true => brand.success, false => brand.danger, null => brand.muted };
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (up) { true => Icons.trending_up_rounded, false => Icons.trending_down_rounded, null => Icons.trending_flat_rounded },
            size: 15,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(color: brand.readable(color), fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
    return PopIn(
      delay: const Duration(milliseconds: 500),
      child: tooltip == null ? chip : Tooltip(message: tooltip!, child: chip),
    );
  }
}

/// [children] in [columns] equal columns.
class ConsoleCells extends StatelessWidget {
  final int columns;
  final double spacing;
  final List<Widget> children;

  const ConsoleCells({super.key, required this.columns, required this.children, this.spacing = 16});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = ((constraints.maxWidth - spacing * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

/// A white (or dark) card with an orange icon and a title. With [fill], its
/// [child] takes the height left (the card has one); without, its own.
class ConsoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;
  final bool fill;

  const ConsoleCard(
      {super.key, required this.icon, required this.title, required this.child, this.trailing, this.fill = false});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.brand.glassBorder),
        boxShadow: ink.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: context.brand.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: ink.heading),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          if (fill) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

/// "View all →" in a card's corner.
class ConsoleLink extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const ConsoleLink({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: ConsoleInk.of(context).heading,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFamily: brandFont),
      ),
    );
  }
}

/// A number at the top: its icon in a soft circle, the value, what it is and
/// a note; [trailing] (a trend, say) beside it, or across from the icon in a
/// narrow cell.
class ConsoleKpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String note;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// The number behind [value], to count up to it; [format] writes it
  /// (whole numbers unless given).
  final num? count;
  final String Function(num)? format;

  const ConsoleKpi({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.note,
    this.onTap,
    this.trailing,
    this.count,
    this.format,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return HoverLift(enabled: onTap != null, child: _card(context, ink));
  }

  Widget _card(BuildContext context, ConsoleInk ink) {
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: ink.shadow),
      child: Material(
        color: ink.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.brand.glassBorder),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 200;
                // A paler well in the light, so the icon carries the colour.
                final badge = Container(
                  width: narrow ? 42 : 52,
                  height: narrow ? 42 : 52,
                  decoration: BoxDecoration(color: color.withValues(alpha: ink.dark ? 0.13 : 0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: narrow ? 21 : 25),
                );
                // The trend shrinks, rather than spill, where there's little
                // room (a phone, large text).
                final side = trailing == null
                    ? null
                    : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topRight, child: trailing);
                final numberStyle =
                    TextStyle(fontSize: narrow ? 24 : 27, fontWeight: FontWeight.w800, color: ink.heading, height: 1.1);
                final number = FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: count == null
                      ? Text(value, style: numberStyle)
                      : AnimatedCount(value: count!, format: format ?? AnimatedCount.whole, style: numberStyle),
                );
                final under = [
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink.body),
                  ),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.brand.muted),
                  ),
                ];
                // The top line is one height, trend or none, so the numbers in
                // a row of cells line up and the cells match.
                const top = 50.0;
                if (narrow) {
                  // The icon over the number, the trend across from it.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: top,
                        child: Row(
                          children: [
                            badge,
                            const SizedBox(width: 8),
                            Expanded(child: Align(alignment: Alignment.topRight, child: side ?? const SizedBox())),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      number,
                      ...under,
                    ],
                  );
                }
                // The icon beside the number, the trend at the number's end.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    badge,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: top,
                            child: Row(
                              children: [
                                Expanded(child: number),
                                if (side != null) ...[
                                  const SizedBox(width: 8),
                                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 90), child: side),
                                ],
                              ],
                            ),
                          ),
                          ...under,
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A small smooth line over a soft fill: how [values] went, oldest first.
class ConsoleSparkline extends StatelessWidget {
  final List<num> values;
  final Color color;
  final double width;
  final double height;

  const ConsoleSparkline({super.key, required this.values, required this.color, this.width = 76, this.height = 30});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size(width, height), painter: _SparkPainter(values: values, color: color)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<num> values;
  final Color color;

  _SparkPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    // A fold, not reduce(math.max): [values] may really be a List<int>.
    final top = values.fold<double>(0, (m, v) => math.max(m, v.toDouble()));
    const inset = 3.0;
    final h = size.height - inset * 2;
    final dx = size.width / (values.length - 1);
    final at = [
      for (var i = 0; i < values.length; i++) Offset(dx * i, inset + (top == 0 ? h : h - h * values[i] / top)),
    ];
    final line = _smooth(at);
    final area = Path.from(line)
      ..lineTo(at.last.dx, size.height)
      ..lineTo(at.first.dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// A curve through [at], level at each point.
Path _smooth(List<Offset> at) {
  final path = Path()..moveTo(at.first.dx, at.first.dy);
  for (var i = 1; i < at.length; i++) {
    final mid = (at[i - 1].dx + at[i].dx) / 2;
    path.cubicTo(mid, at[i - 1].dy, mid, at[i].dy, at[i].dx, at[i].dy);
  }
  return path;
}

/// The chart's periods, the chosen one orange.
class ConsoleRangePicker<T> extends StatelessWidget {
  final List<T> values;
  final T value;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  const ConsoleRangePicker(
      {super.key, required this.values, required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final accent = context.brand.accent;
    const style = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, fontFamily: brandFont);
    // Every period the width of the widest, so the orange pill can slide
    // from one to the next.
    final scale = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    var tallest = 0.0;
    for (final r in values) {
      final t = TextPainter(text: TextSpan(text: label(r), style: style), textDirection: TextDirection.ltr, textScaler: scale)
        ..layout();
      if (t.width > widest) widest = t.width;
      if (t.height > tallest) tallest = t.height;
    }
    final cell = (widest + 22).ceilToDouble();
    final at = values.indexOf(value);
    final duration = Motion.of(context, Motion.dropdown);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ink.dark ? Colors.white.withValues(alpha: 0.06) : context.brand.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        width: cell * values.length,
        height: (tallest + 12).ceilToDouble(),
        child: Stack(
          children: [
            if (at >= 0)
              AnimatedPositioned(
                duration: duration,
                curve: Motion.ease,
                left: cell * at,
                top: 0,
                bottom: 0,
                width: cell,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: ink.dark ? null : [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                ),
              ),
            Row(
              children: [
                for (final r in values)
                  Semantics(
                    selected: r == value,
                    button: true,
                    child: InkWell(
                      onTap: () => onChanged(r),
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: cell,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: duration,
                            style: style.copyWith(color: r == value ? Colors.white : ink.body),
                            child: Text(label(r), maxLines: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A smooth orange line over a soft fill, the best point labelled; under
/// the mouse, the nearest point's label and value instead, on a guide line.
class ConsoleLineChart extends StatefulWidget {
  final List<({String label, int value})> points;

  /// The best point's label: 'Nu. 52,000', '3 visits'.
  final String Function(int) format;

  /// Whole steps up the side (visits), not 1.5k (ngultrum).
  final bool whole;

  /// What it is, and what to say with nothing in it, read out.
  final String name;
  final String noneText;

  const ConsoleLineChart({
    super.key,
    required this.points,
    required this.format,
    required this.name,
    required this.noneText,
    this.whole = false,
  });

  @override
  State<ConsoleLineChart> createState() => _ConsoleLineChartState();
}

class _ConsoleLineChartState extends State<ConsoleLineChart> {
  /// The point under the mouse.
  int? _focus;

  void _hover(Offset at, double width) {
    final n = widget.points.length;
    if (n == 0) return;
    final dx = n == 1 ? 0.0 : (width - _LinePainter.right - _LinePainter.left) / (n - 1);
    final i = dx == 0 ? 0 : ((at.dx - _LinePainter.left) / dx).round().clamp(0, n - 1);
    if (i != _focus) setState(() => _focus = i);
  }

  @override
  void didUpdateWidget(ConsoleLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus != null && _focus! >= widget.points.length) _focus = null;
  }

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final points = widget.points;
    final format = widget.format;
    final best = points.fold<({String label, int value})?>(null, (b, p) => b == null || p.value > b.value ? p : b);
    CustomPainter paint(double progress) => _LinePainter(
          points: points,
          format: format,
          whole: widget.whole,
          progress: progress,
          focus: progress >= 1 ? _focus : null,
          label: TextStyle(fontSize: 11.5, color: context.brand.muted, fontFamily: brandFont),
          bubble: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ink.heading, fontFamily: brandFont),
          bubbleColor: ink.card,
          grid: context.brand.glassBorder,
          guide: context.brand.muted.withValues(alpha: 0.45),
          line: context.brand.accent,
        );
    return Semantics(
      label: best == null || best.value == 0
          ? '${widget.name}: ${widget.noneText}'
          : '${widget.name}: highest ${format(best.value)} on ${best.label}',
      child: LayoutBuilder(
        builder: (context, box) => MouseRegion(
          onHover: (e) => _hover(e.localPosition, box.maxWidth),
          onExit: (_) => setState(() => _focus = null),
          // The line draws itself in, left to right, each time the figures
          // change.
          child: reduceMotion(context)
              ? CustomPaint(size: Size.infinite, painter: paint(1))
              : TweenAnimationBuilder<double>(
                  key: ValueKey(Object.hashAll(points.map((p) => Object.hash(p.label, p.value)))),
                  tween: Tween(begin: 0, end: 1),
                  duration: Motion.chart,
                  curve: Motion.ease,
                  builder: (context, t, _) => CustomPaint(size: Size.infinite, painter: paint(t)),
                ),
        ),
      ),
    );
  }
}

/// '0', '750', '1.5k', '20k', '1.2M'.
String compactNu(num v) {
  String trim(double x) => x.toStringAsFixed(x >= 10 || x == x.roundToDouble() ? 0 : 1);
  if (v >= 1000000) return '${trim(v / 1000000)}M';
  if (v >= 1000) return '${trim(v / 1000)}k';
  return '${v.round()}';
}

/// A round step between the chart's 4 gridlines, at least [rough]: 1.5k,
/// 3k, 4.5k rather than 1.3k, 2.5k, 3.8k.
double niceStep(double rough) {
  if (rough <= 0) return 250;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]) {
    if (m * magnitude >= rough) return m * magnitude;
  }
  return 10 * magnitude;
}

class _LinePainter extends CustomPainter {
  /// Room at the left for the amounts, and at the right.
  static const left = 44.0;
  static const right = 10.0;

  final List<({String label, int value})> points;
  final String Function(int) format;
  final bool whole;

  /// How far it has drawn in, 0 to 1.
  final double progress;

  /// The point under the mouse: labelled, on a guide line.
  final int? focus;
  final TextStyle label;
  final TextStyle bubble;
  final Color bubbleColor;
  final Color grid;
  final Color guide;
  final Color line;

  _LinePainter({
    required this.points,
    required this.format,
    required this.whole,
    this.progress = 1,
    this.focus,
    required this.label,
    required this.bubble,
    required this.bubbleColor,
    required this.grid,
    required this.guide,
    required this.line,
  });

  TextPainter _text(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width < 80 || size.height < 60) return;
    final chart = Rect.fromLTRB(left, 34, size.width - right, size.height - 26);
    final most = points.fold<int>(0, (m, p) => math.max(m, p.value));
    // Four gridlines in round steps; a few whole things (visits) get a line
    // each and one spare, so a single visit doesn't sit low on an empty chart.
    final int lines;
    final double top;
    if (whole && most <= 4) {
      lines = most + 1;
      top = most + 1.0;
    } else {
      lines = 4;
      top = 4 * (whole ? niceStep(most / 4).ceilToDouble() : niceStep(most / 4));
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= lines; i++) {
      final y = chart.bottom - chart.height * i / lines;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final t = _text(compactNu(top * i / lines), label);
      t.paint(canvas, Offset(chart.left - 10 - t.width, y - t.height / 2));
    }

    final n = points.length;
    final dx = n == 1 ? 0.0 : chart.width / (n - 1);
    final at = [
      for (var i = 0; i < n; i++) Offset(chart.left + dx * i, chart.bottom - chart.height * points[i].value / top),
    ];
    final full = _smooth(at);
    // Drawn in so far: the line up to [progress] of its length, the fill under
    // it clipped to the same width.
    final drawnTo = chart.left + (at.last.dx - chart.left) * progress;
    final Path path;
    if (progress >= 1) {
      path = full;
    } else {
      path = Path();
      for (final metric in full.computeMetrics()) {
        path.addPath(metric.extractPath(0, metric.length * progress), Offset.zero);
      }
    }
    final area = Path.from(full)
      ..lineTo(at.last.dx, chart.bottom)
      ..lineTo(at.first.dx, chart.bottom)
      ..close();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, drawnTo + 1, size.height));
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.3), line.withValues(alpha: 0)],
        ).createShader(chart),
    );
    canvas.restore();
    // The guide down from the point under the mouse.
    final focused = focus != null && focus! < n ? focus : null;
    if (focused != null) {
      final x = at[focused].dx;
      final dash = Paint()
        ..color = guide
        ..strokeWidth = 1;
      for (var y = chart.top; y < chart.bottom; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, chart.bottom)), dash);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (n <= 13 || focused != null) {
      for (var i = 0; i < n; i++) {
        final o = at[i];
        if (o.dx > drawnTo + 0.5) continue;
        if (n > 13 && i != focused) continue;
        final r = i == focused ? 6.5 : 5.0;
        canvas.drawCircle(o, r, Paint()..color = i == focused ? line : bubbleColor);
        canvas.drawCircle(
          o,
          r,
          Paint()
            ..color = i == focused ? bubbleColor : line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }

    // The point under the mouse, or else the best, labelled above itself.
    var best = 0;
    for (var i = 1; i < n; i++) {
      if (points[i].value > points[best].value) best = i;
    }
    final labelled = focused ?? best;
    if ((focused != null || points[best].value > 0) && at[labelled].dx <= drawnTo + 0.5) {
      final text = focused == null
          ? format(points[labelled].value)
          : '${points[labelled].label} · ${format(points[labelled].value)}';
      final t = _text(text, bubble);
      final w = t.width + 18;
      final h = t.height + 10;
      final boxLeft = (at[labelled].dx - w / 2).clamp(0.0, size.width - w).toDouble();
      final boxTop = math.max(0.0, at[labelled].dy - h - 12);
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(boxLeft, boxTop, w, h), const Radius.circular(9));
      canvas.drawShadow(Path()..addRRect(box), Colors.black, 4, false);
      canvas.drawRRect(box, Paint()..color = bubbleColor);
      canvas.drawRRect(
        box,
        Paint()
          ..color = grid
          ..style = PaintingStyle.stroke,
      );
      t.paint(canvas, Offset(box.left + 9, box.top + 5));
    }

    // Under the line: every label, or every few when they'd crowd.
    final every = math.max(1, (n * 52 / chart.width).ceil());
    for (var i = 0; i < n; i += every) {
      final t = _text(points[i].label, label);
      final x = (at[i].dx - t.width / 2).clamp(0.0, size.width - t.width).toDouble();
      t.paint(canvas, Offset(x, chart.bottom + 8));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points ||
      old.progress != progress ||
      old.focus != focus ||
      old.whole != whole ||
      old.line != line ||
      old.grid != grid ||
      old.guide != guide ||
      old.label != label ||
      old.bubble != bubble ||
      old.bubbleColor != bubbleColor;
}

/// Bars that grow into place, one per point: the [highlight]ed one (else the
/// tallest) in [color] with its value over it, the rest paler. A tooltip on
/// each; tapping one calls [onTap]. Labels under them, every few when
/// they'd crowd.
class ConsoleBarChart extends StatefulWidget {
  final List<({String label, num value})> points;
  final String Function(num) format;
  final Color color;
  final double height;
  final int? highlight;
  final ValueChanged<int>? onTap;

  /// What it shows, read out.
  final String name;

  const ConsoleBarChart({
    super.key,
    required this.points,
    required this.format,
    required this.name,
    this.color = BrandColors.orange,
    this.height = 200,
    this.highlight,
    this.onTap,
  });

  @override
  State<ConsoleBarChart> createState() => _ConsoleBarChartState();
}

class _ConsoleBarChartState extends State<ConsoleBarChart> {
  /// The bar under the mouse: deeper, with its value over it.
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final format = widget.format;
    final color = widget.color;
    final onTap = widget.onTap;
    final name = widget.name;
    final most = points.fold<num>(0, (m, p) => math.max(m, p.value));
    final marked = widget.highlight ?? (most == 0 ? null : points.indexWhere((p) => p.value == most));
    final muted = context.brand.muted;
    final ink = ConsoleInk.of(context);
    final hover = _hover != null && _hover! < points.length ? _hover : null;

    Widget bars(double t) => LayoutBuilder(
          builder: (context, c) {
            final n = points.length;
            final every = math.max(1, (n * 34 / c.maxWidth).ceil());
            final gap = n > 16 ? 3.0 : (n > 8 ? 6.0 : 10.0);
            final area = c.maxHeight - 22 - 20;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: gap / 2),
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hover = i),
                        onExit: (_) => setState(() => _hover = _hover == i ? null : _hover),
                        child: Tooltip(
                        message: '${points[i].label}: ${format(points[i].value)}',
                        child: InkWell(
                          onTap: onTap == null ? null : () => onTap(i),
                          borderRadius: BorderRadius.circular(6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 20,
                                child: (i == hover || (hover == null && i == marked)) && points[i].value > 0
                                    ? FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Opacity(
                                          opacity: t,
                                          child: Text(format(points[i].value),
                                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink.heading)),
                                        ),
                                      )
                                    : null,
                              ),
                              // Lighter bars deepen under the mouse, over a
                              // hover's length.
                              TweenAnimationBuilder<double>(
                                tween: Tween(end: i == hover ? 1 : 0),
                                duration: Motion.of(context, Motion.hover),
                                curve: Motion.ease,
                                builder: (context, h, _) => Container(
                                  height:
                                      most == 0 ? 2 : math.max(points[i].value > 0 ? 3.0 : 2.0, area * points[i].value / most * t),
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                                    gradient: i == marked
                                        ? LinearGradient(
                                            colors: [color, color.withValues(alpha: 0.75 + 0.25 * h)],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter)
                                        : null,
                                    color: i == marked
                                        ? null
                                        : color.withValues(alpha: (points[i].value == 0 ? 0.12 : 0.28) + 0.3 * h),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 22,
                                child: i % every == 0
                                    ? Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Text(points[i].label,
                                            maxLines: 1,
                                            softWrap: false,
                                            overflow: TextOverflow.visible,
                                            style: TextStyle(fontSize: 11, color: muted)),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );

    return Semantics(
      label: marked == null ? '$name: none yet' : '$name: highest ${format(points[marked].value)}, ${points[marked].label}',
      child: SizedBox(
        height: widget.height,
        child: reduceMotion(context)
            ? bars(1)
            : TweenAnimationBuilder<double>(
                key: ValueKey(Object.hashAll(points.map((p) => Object.hash(p.label, p.value)))),
                tween: Tween(begin: 0, end: 1),
                duration: Motion.chart,
                curve: Motion.ease,
                builder: (context, t, _) => bars(t),
              ),
      ),
    );
  }
}

/// A row of a breakdown: a dot of [color], [label], [value], and a bar of
/// its [share] (0 to 1) that grows in.
class ConsoleShareRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final double share;

  const ConsoleShareRow({super.key, required this.color, required this.label, required this.value, required this.share});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: ink.body)),
              ),
              Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: ink.heading)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: share.clamp(0, 1).toDouble()),
              duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ring of [parts] (a count and its colour) with [center] inside; an
/// empty ring with nothing to count.
class ConsoleRing extends StatelessWidget {
  final List<(int, Color)> parts;
  final double size;
  final double stroke;
  final Widget center;

  const ConsoleRing({super.key, required this.parts, required this.center, this.size = 168, this.stroke = 20});

  @override
  Widget build(BuildContext context) {
    CustomPaint ring(double t) => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(parts: parts, empty: context.brand.glassBorder, stroke: stroke, progress: t),
        );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // It sweeps round into place.
          if (reduceMotion(context))
            ring(1)
          else
            TweenAnimationBuilder<double>(
              key: ValueKey(Object.hashAll(parts.map((p) => p.$1))),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => ring(t),
            ),
          center,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final List<(int, Color)> parts;
  final Color empty;
  final double stroke;

  /// How far round it has swept, 0 to 1.
  final double progress;

  _RingPainter({required this.parts, required this.empty, required this.stroke, this.progress = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final total = parts.fold<int>(0, (sum, p) => sum + p.$1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = empty);
    if (total == 0) return;
    final shown = parts.where((p) => p.$1 > 0).length;
    final gap = shown > 1 ? 0.05 : 0.0;
    final end = -math.pi / 2 + 2 * math.pi * progress;
    var start = -math.pi / 2;
    paint.strokeCap = shown == 1 ? StrokeCap.butt : StrokeCap.round;
    for (final (n, color) in parts) {
      if (n == 0) continue;
      final sweep = 2 * math.pi * n / total;
      final drawn = math.min(start + sweep, end) - start;
      if (drawn > 0) {
        canvas.drawArc(rect, start + gap / 2, math.max(drawn - gap, 0.001), false, paint..color = color);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.parts != parts || old.empty != empty || old.stroke != stroke || old.progress != progress;
}

/// A shortcut tile: its icon over its name, on a soft fill.
class ConsoleActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  const ConsoleActionTile({super.key, required this.icon, required this.label, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return HoverLift(
      radius: 14,
      lift: 2,
      child: Material(
        color: ink.tint,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  backgroundColor: context.brand.accent,
                  child: Icon(icon, color: ink.heading, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ink.body, height: 1.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [tiles] three to a row, each row as tall as its tallest tile.
class ConsoleTileGrid extends StatelessWidget {
  final List<Widget> tiles;

  const ConsoleTileGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < tiles.length; row += 3) ...[
          if (row > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = row; i < row + 3; i++) ...[
                  if (i > row) const SizedBox(width: 10),
                  Expanded(child: i < tiles.length ? tiles[i] : const SizedBox()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The wide orange button at a card's foot.
class ConsoleGlowButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const ConsoleGlowButton(
      {super.key, required this.label, required this.onPressed, this.icon = Icons.arrow_forward_rounded});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    final dark = ConsoleInk.of(context).dark;
    return Pressable(
      child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFFF8A3D), accent]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: dark ? 0.32 : 0.24), blurRadius: dark ? 16 : 12, offset: Offset(0, dark ? 6 : 4))
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// An orange pill with an arrow, for dark cards.
class ConsolePillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool small;

  const ConsolePillButton({super.key, required this.label, required this.onPressed, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: context.brand.accent,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        minimumSize: Size(0, small ? 36 : 44),
        padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20, vertical: small ? 8 : 12),
        textStyle: TextStyle(fontSize: small ? 13 : 14.5, fontWeight: FontWeight.w700, fontFamily: brandFont),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, size: small ? 16 : 18),
        ],
      ),
      ),
    );
  }
}

// ─── The footer ────────────────────────────────────────────────────────────

/// © SportsHub, and [links] across (under each other on a phone).
class ConsoleFooter extends StatelessWidget {
  final double gutter;
  final List<(String, VoidCallback)> links;

  const ConsoleFooter({super.key, required this.gutter, required this.links});

  @override
  Widget build(BuildContext context) {
    final muted = context.brand.muted;
    final copyright = Text(
      '© ${BhutanTime.today().year} SportsHub. All rights reserved.',
      style: TextStyle(fontSize: 13, color: muted),
    );
    final linkRow = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < links.length; i++) ...[
          if (i > 0) Text('|', style: TextStyle(color: context.brand.glassBorder)),
          TextButton(
            onPressed: links[i].$2,
            style: TextButton.styleFrom(
              foregroundColor: ConsoleInk.of(context).body,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, fontFamily: brandFont),
            ),
            child: Text(links[i].$1),
          ),
        ],
      ],
    );
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.brand.glassBorder))),
      padding: EdgeInsets.fromLTRB(gutter, 14, gutter, 18),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 760
            ? Row(children: [
                copyright,
                const Spacer(),
                Flexible(flex: 3, child: Align(alignment: Alignment.centerRight, child: linkRow))
              ])
            : Column(children: [linkRow, const SizedBox(height: 6), copyright]),
      ),
    );
  }
}
