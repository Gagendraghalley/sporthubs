import 'package:flutter/material.dart';

/// The SportsHub logo (assets/images/). Its navy lettering needs a light
/// background, so dark mode puts it on a white tile.
class SportsHubLogo extends StatelessWidget {
  final double height;

  /// Just the 'S' with the runner, without the name.
  final bool markOnly;

  const SportsHubLogo({super.key, this.height = 56, this.markOnly = false});

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      markOnly ? 'assets/images/sportshub_mark.png' : 'assets/images/sportshub_logo.png',
      package: 'sportshub_core',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'SportsHub',
      errorBuilder: (_, __, ___) => Text(
        'SportsHub',
        style: TextStyle(fontSize: height * 0.4, fontWeight: FontWeight.w900),
      ),
    );
    if (Theme.of(context).brightness == Brightness.light) return image;
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: image),
    );
  }
}
