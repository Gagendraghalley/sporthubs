import 'package:flutter/material.dart';

/// The platform's typeface, Plus Jakarta Sans (this package's pubspec): every
/// service's pages, through the theme.
const brandFont = 'packages/sportshub_core/PlusJakartaSans';

/// SportsHub's colours, from the logo: navy 'Sport', orange 'Hub' and the
/// blue of the 'S'.
abstract final class BrandColors {
  static const navy = Color(0xFF0B1530);
  static const slateNavy = Color(0xFF151F35);
  static const orange = Color(0xFFFF790F);
  static const orangeText = Color(0xFFB54708);
  static const blue = Color(0xFF1F6FD6);
  static const green = Color(0xFF1B8A4B);
  static const amber = Color(0xFFB7791F);
  static const red = Color(0xFFC62828);
  static const mutedSlate = Color(0xFF94A3B8);

  /// The deep navy of the side menu and the splash screen, top to bottom.
  static const midnight = navy;
  static const night = Color(0xFF080F20);
}

/// The light theme's own palette: white cards on a cool grey page, navy and
/// orange from the logo. The dark theme keeps [BrandColors].
abstract final class LightColors {
  /// Behind every page, and a step deeper for bands and wells.
  static const background = Color(0xFFF5F7FB);
  static const backgroundAlt = Color(0xFFEEF2F7);

  /// Cards, the side menu, fields, dialogs.
  static const card = Color(0xFFFFFFFF);

  /// Headings and most text; quieter text.
  static const ink = Color(0xFF17243B);
  static const body = Color(0xFF3A4860);
  static const muted = Color(0xFF64748B);

  /// The brand's navy (filled buttons) and orange (main actions, what's
  /// active).
  static const navy = Color(0xFF142B52);
  static const orange = Color(0xFFF97316);

  /// Orange that reads as text on white (a focused field's label).
  static const orangeText = Color(0xFFC2410C);

  /// Card edges and rules; a field's edge, a little firmer.
  static const border = Color(0xFFE5EAF1);
  static const fieldBorder = Color(0xFFD7DEE8);

  static const success = Color(0xFF159B72);
  static const warning = Color(0xFFD99019);
  static const danger = Color(0xFFDC4545);
}

/// The frosted-glass look: translucent bars and cards over a soft
/// background. Read with `context.brand`.
@immutable
class Brand extends ThemeExtension<Brand> {
  /// Behind every page.
  final Color background;

  /// A step deeper than [background]: bands across a page, wells in a card.
  final Color surfaceAlt;

  /// Behind a table's header row, or nothing.
  final Color subtle;

  /// The soft glows on the background.
  final Color glowA;
  final Color glowB;

  /// App bars and the bottom bar: translucent, with the page blurred behind.
  final Color glass;
  final Color glassBorder;

  /// A field's or an outlined button's edge.
  final Color fieldBorder;

  /// Cards: nearly opaque, so text stays easy to read.
  final Color card;

  /// Under a card: a hairline in the light, a deep shadow in the dark.
  final List<BoxShadow> cardShadow;

  /// Headings, and body text a little quieter.
  final Color ink;
  final Color body;

  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color muted;

  const Brand({
    required this.background,
    required this.surfaceAlt,
    required this.subtle,
    required this.glowA,
    required this.glowB,
    required this.glass,
    required this.glassBorder,
    required this.fieldBorder,
    required this.card,
    required this.cardShadow,
    required this.ink,
    required this.body,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.muted,
  });

  static const light = Brand(
    background: LightColors.background,
    surfaceAlt: LightColors.backgroundAlt,
    subtle: Color(0xFFF8FAFC),
    // Barely there: the page reads as one calm grey.
    glowA: Color(0x0A1F6FD6),
    glowB: Color(0x08F97316),
    glass: Color(0xEBFFFFFF),
    glassBorder: LightColors.border,
    fieldBorder: LightColors.fieldBorder,
    card: LightColors.card,
    cardShadow: [
      BoxShadow(color: Color(0x0A142B52), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0D142B52), blurRadius: 16, spreadRadius: -4, offset: Offset(0, 6)),
    ],
    ink: LightColors.ink,
    body: LightColors.body,
    accent: LightColors.orange,
    success: LightColors.success,
    warning: LightColors.warning,
    danger: LightColors.danger,
    muted: LightColors.muted,
  );

  static const dark = Brand(
    background: BrandColors.navy,
    surfaceAlt: Color(0x0FFFFFFF),
    subtle: Color(0x00000000),
    glowA: Color(0x332F7BE0),
    glowB: Color(0x1FFF790F),
    glass: Color(0xB3151F35),
    glassBorder: Color(0x24FFFFFF),
    fieldBorder: Color(0x24FFFFFF),
    card: Color(0xE6151F35),
    cardShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
    ink: Colors.white,
    body: Color(0xFFC5CCDA),
    accent: BrandColors.orange,
    success: Color(0xFF4CC983),
    warning: Color(0xFFE8B04B),
    danger: Color(0xFFFF6B6B),
    muted: BrandColors.mutedSlate,
  );

  /// How far toward dark: 0 in the light theme, 1 in the dark, in between
  /// while the theme switches (the page's colour is lerped, so this is too).
  double get darkness {
    const from = LightColors.background;
    const to = BrandColors.navy;
    return ((from.r - background.r) / (from.r - to.r)).clamp(0.0, 1.0);
  }

  /// [light] or [dark], or the mix between them mid-switch: colours chosen
  /// for each theme glide rather than snap when it changes.
  Color pick(Color light, Color dark) => Color.lerp(light, dark, darkness)!;

  /// Whether these are the light theme's colours.
  bool get isLight => darkness < 0.5;

  /// [color] as text on a soft tint of itself (a status chip): a shade
  /// deeper in the light, so amber and green stay readable on white.
  Color readable(Color color) => isLight ? Color.lerp(color, ink, 0.34)! : color;

  @override
  Brand copyWith({Color? background, Color? glass, Color? card, Color? accent}) => Brand(
        background: background ?? this.background,
        surfaceAlt: surfaceAlt,
        subtle: subtle,
        glowA: glowA,
        glowB: glowB,
        glass: glass ?? this.glass,
        glassBorder: glassBorder,
        fieldBorder: fieldBorder,
        card: card ?? this.card,
        cardShadow: cardShadow,
        ink: ink,
        body: body,
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
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      subtle: mix(subtle, other.subtle),
      glowA: mix(glowA, other.glowA),
      glowB: mix(glowB, other.glowB),
      glass: mix(glass, other.glass),
      glassBorder: mix(glassBorder, other.glassBorder),
      fieldBorder: mix(fieldBorder, other.fieldBorder),
      card: mix(card, other.card),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? other.cardShadow,
      ink: mix(ink, other.ink),
      body: mix(body, other.body),
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
