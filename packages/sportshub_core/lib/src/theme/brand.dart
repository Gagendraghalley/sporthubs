import 'package:flutter/material.dart';

/// The platform's typeface, Plus Jakarta Sans (this package's pubspec): every
/// service's pages, through the theme.
const brandFont = 'packages/sportshub_core/PlusJakartaSans';

/// SportsHub's colours, from the logo: navy 'Sport', orange 'Hub' and the
/// blue of the 'S'.
abstract final class BrandColors {
  static const navy = Color(0xFF0A1C45);
  static const orange = Color(0xFFF86A0C);
  static const blue = Color(0xFF1F6FD6);
  static const green = Color(0xFF1B8A4B);
  static const amber = Color(0xFFB7791F);
  static const red = Color(0xFFC62828);

  /// The deep navy of the side menu and the splash screen, top to bottom.
  static const midnight = Color(0xFF0C2152);
  static const night = Color(0xFF071229);
}

/// The frosted-glass look: translucent bars and cards over a soft
/// background. Read with `context.brand`.
@immutable
class Brand extends ThemeExtension<Brand> {
  /// Behind every page.
  final Color background;

  /// The soft glows on the background.
  final Color glowA;
  final Color glowB;

  /// App bars and the bottom bar: translucent, with the page blurred behind.
  final Color glass;
  final Color glassBorder;

  /// Cards: nearly opaque, so text stays easy to read.
  final Color card;

  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color muted;

  const Brand({
    required this.background,
    required this.glowA,
    required this.glowB,
    required this.glass,
    required this.glassBorder,
    required this.card,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.muted,
  });

  static const light = Brand(
    background: Color(0xFFF3F6FB),
    glowA: Color(0x332F7BE0),
    glowB: Color(0x26F86A0C),
    glass: Color(0xB8FFFFFF),
    glassBorder: Color(0x1F0A1C45),
    card: Color(0xE6FFFFFF),
    accent: BrandColors.orange,
    success: BrandColors.green,
    warning: BrandColors.amber,
    danger: BrandColors.red,
    muted: Color(0xFF5B6478),
  );

  static const dark = Brand(
    background: Color(0xFF070C18),
    glowA: Color(0x332F7BE0),
    glowB: Color(0x1FF86A0C),
    glass: Color(0xB30B1224),
    glassBorder: Color(0x24FFFFFF),
    card: Color(0xE6111A2E),
    accent: Color(0xFFFF8A3D),
    success: Color(0xFF4CC983),
    warning: Color(0xFFE8B04B),
    danger: Color(0xFFFF6B6B),
    muted: Color(0xFF9AA4B8),
  );

  @override
  Brand copyWith({Color? background, Color? glass, Color? card, Color? accent}) => Brand(
        background: background ?? this.background,
        glowA: glowA,
        glowB: glowB,
        glass: glass ?? this.glass,
        glassBorder: glassBorder,
        card: card ?? this.card,
        accent: accent ?? this.accent,
        success: success,
        warning: warning,
        danger: danger,
        muted: muted,
      );

  @override
  Brand lerp(Brand? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return Brand(
      background: mix(background, other.background),
      glowA: mix(glowA, other.glowA),
      glowB: mix(glowB, other.glowB),
      glass: mix(glass, other.glass),
      glassBorder: mix(glassBorder, other.glassBorder),
      card: mix(card, other.card),
      accent: mix(accent, other.accent),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      muted: mix(muted, other.muted),
    );
  }
}

extension BrandContext on BuildContext {
  Brand get brand => Theme.of(this).extension<Brand>() ?? Brand.light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
