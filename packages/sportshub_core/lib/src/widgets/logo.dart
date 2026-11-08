import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// The SportsHub logo (assets/images/), in two versions: navy lettering for
/// light backgrounds, and white lettering with a brighter blue 'S' for dark
/// ones (the `_on_dark` files), so it sits straight on the navy without a
/// white tile.
class SportsHubLogo extends StatelessWidget {
  final double height;

  /// Just the 'S' with the runner, without the name.
  final bool markOnly;

  /// Whether it sits on something dark: the white-lettered version. Null
  /// follows the theme; true for places that are navy in both themes (the
  /// side menu, the splash screen).
  final bool? onDark;

  const SportsHubLogo({super.key, this.height = 56, this.markOnly = false, this.onDark});

  /// Width over height of the whole logo, and of the mark alone.
  static const aspectRatio = 900 / 482;
  static const markAspectRatio = 600 / 283;

  /// The package the images are in, and the image for each version.
  static const package = 'sportshub_core';
  static String assetFor({required bool markOnly, required bool onDark}) =>
      'assets/images/${markOnly ? 'sportshub_mark' : 'sportshub_logo'}${onDark ? '_on_dark' : ''}.png';

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      assetFor(markOnly: markOnly, onDark: dark),
      package: package,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'SportsHub',
      errorBuilder: (_, __, ___) => Text(
        'SportsHub',
        style: TextStyle(
          fontSize: height * 0.4,
          fontWeight: FontWeight.w900,
          color: dark ? Colors.white : BrandColors.navy,
        ),
      ),
    );
  }
}
