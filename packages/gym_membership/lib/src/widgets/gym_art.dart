import 'package:flutter/material.dart';
import 'package:sportshub_core/sportshub_core.dart';

// The gym pages' shared art: the Welcome page, the signed-in home.

/// Navy and orange bands sweeping up the right edge, over the photo.
class GymStripesPainter extends CustomPainter {
  const GymStripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Path band(double x1, double x2, double y1, double y2) => Path()
      ..moveTo(w * x1, h)
      ..lineTo(w * x2, h)
      ..lineTo(w, h * y2)
      ..lineTo(w, h * y1)
      ..close();
    canvas.drawPath(band(0.66, 0.78, 0.30, 0.46), Paint()..color = BrandColors.navy.withValues(alpha: 0.88));
    canvas.drawPath(
      band(0.78, 0.84, 0.46, 0.55),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [Color(0xFFFF8A3D), BrandColors.orange],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(GymStripesPainter oldDelegate) => false;
}

/// A soft round light.
class GymGlow extends StatelessWidget {
  final Color color;
  final double size;

  const GymGlow({super.key, required this.color, required this.size});

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

/// One of the gym pages' photos (assets/welcome, credited in
/// assets/PHOTO_CREDITS.md), fading in once loaded; navy if it can't load.
class GymPhoto extends StatelessWidget {
  final String name;
  final Alignment alignment;

  const GymPhoto(this.name, {super.key, this.alignment = Alignment.center});

  static ImageProvider provider(String name) => AssetImage('assets/welcome/$name.jpg', package: 'gym_membership');

  @override
  Widget build(BuildContext context) {
    return Image(
      image: provider(name),
      fit: BoxFit.cover,
      alignment: alignment,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, loadedAtOnce) => loadedAtOnce
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              child: child,
            ),
      errorBuilder: (_, __, ___) => const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [BrandColors.navy, BrandColors.blue])),
      ),
    );
  }
}
