import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';
import '../widgets/logo.dart';
import '../widgets/motion.dart';

/// What the photo says beside the form: SportsHub's perks in a bar along
/// the foot (signing in), or a welcome with a short list of them (joining).
enum AuthSide { signIn, join }

/// The frame of the sign-in, sign-up, code and password pages: a sports
/// photo across the window with the logo and what SportsHub offers on it,
/// and the form on a white card at the right. On a phone the photo is a
/// banner and the form a sheet under it.
class AuthLayout extends StatelessWidget {
  final AuthSide side;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Where the back button goes. Given, the button always shows (signing in
  /// and up go back to the Welcome page); else it shows only when there is
  /// a page to go back to, and goes there.
  final VoidCallback? onBack;

  const AuthLayout({
    super.key,
    required this.side,
    required this.title,
    this.subtitle,
    required this.children,
    this.onBack,
  });

  /// The photo behind every sign-in page (assets/PHOTO_CREDITS.md): save
  /// another over it to change it.
  static const photo = 'assets/auth/background.jpg';

  /// The photo fills the window from this width; under it, it's a banner.
  static const wideFrom = 900.0;

  /// The card's width on a computer.
  static const cardWidth = 448.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideFrom;
    final backButton = onBack != null
        ? _BackButton(tooltip: 'Back to home', onPressed: onBack!)
        : Navigator.of(context).canPop()
            ? _BackButton(tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop())
            : null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The photo is dark at the top in both layouts.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: wide ? BrandColors.night : context.colors.surface,
        body: _AuthInputs(child: wide ? _wide(context, backButton) : _narrow(context, backButton)),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 30,
            height: 1.15,
            letterSpacing: -0.6,
            fontWeight: FontWeight.w800,
            color: dark ? Colors.white : BrandColors.navy,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500, color: context.brand.muted)),
        ],
        const SizedBox(height: 26),
        ...children,
      ],
    );
  }

  Widget _wide(BuildContext context, Widget? backButton) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        const _Photo(),
        _Wash(side: side),
        const CustomPaint(painter: _WavePainter()),
        SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 28, 28, 32),
                  child: _Showcase(side: side, backButton: backButton),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 48, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const FadeSlideIn(child: _Motto()),
                      const SizedBox(height: 18),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: Container(
                          width: cardWidth,
                          padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(28),
                            border: dark ? Border.all(color: context.brand.glassBorder) : null,
                            boxShadow: const [BoxShadow(color: Color(0x47000000), blurRadius: 50, offset: Offset(0, 24))],
                          ),
                          child: _form(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context, Widget? backButton) {
    final insets = MediaQuery.paddingOf(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: insets.top + 250,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _Photo(),
                const _Wash(side: AuthSide.signIn, banner: true),
                const CustomPaint(painter: _WavePainter(banner: true)),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, insets.top + 8, 16, 80),
                  child: const Center(child: FadeSlideIn(child: SportsHubLogo(height: 112, onDark: true))),
                ),
                if (backButton != null) Positioned(top: insets.top + 8, left: 12, child: backButton),
              ],
            ),
          ),
          // The sheet rises over the foot of the banner.
          Transform.translate(
            offset: const Offset(0, -30),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 30, 20, insets.bottom + 4),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: FadeSlideIn(child: _form(context)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo, cropped to fill; navy if it can't be read.
class _Photo extends StatelessWidget {
  const _Photo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AuthLayout.photo,
      package: SportsHubLogo.package,
      fit: BoxFit.cover,
      alignment: const Alignment(-0.2, -0.6),
      excludeFromSemantics: true,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BrandColors.midnight, BrandColors.night],
          ),
        ),
      ),
    );
  }
}

/// Navy over the photo where words sit on it, so they read on any photo.
class _Wash extends StatelessWidget {
  final AuthSide side;
  final bool banner;

  const _Wash({required this.side, this.banner = false});

  static Color _night(double alpha) => BrandColors.night.withValues(alpha: alpha);

  @override
  Widget build(BuildContext context) {
    final LinearGradient gradient;
    if (banner) {
      gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_night(0.62), _night(0.30), _night(0.55)],
        stops: const [0, 0.55, 1],
      );
    } else if (side == AuthSide.join) {
      // The welcome reads down the left.
      gradient = LinearGradient(
        colors: [_night(0.90), _night(0.62), _night(0.28), _night(0.45)],
        stops: const [0, 0.35, 0.65, 1],
      );
    } else {
      // The logo at the top left; the card's side a little darker.
      gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_night(0.70), _night(0.18), _night(0.50)],
        stops: const [0, 0.48, 1],
      );
    }
    return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
  }
}

/// The orange wave over a navy foot, sweeping from the left down to the
/// right, as on the logo.
class _WavePainter extends CustomPainter {
  final bool banner;

  const _WavePainter({this.banner = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Where the wave meets the left and the right edge.
    final left = h * (banner ? 0.70 : 0.80);
    final right = h * (banner ? 0.86 : 0.90);
    final lift = h * (banner ? 0.10 : 0.07);
    Path wave(double dy) => Path()
      ..moveTo(0, left + dy)
      ..cubicTo(w * 0.32, left - lift + dy, w * 0.60, right + lift * 0.4 + dy, w, right - lift * 0.5 + dy)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      wave(0),
      Paint()
        ..shader = LinearGradient(
          colors: [BrandColors.orange, const Color(0xFFFF8A3D), BrandColors.orange.withValues(alpha: 0.35)],
          stops: const [0, 0.5, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(wave(banner ? 9 : 16), Paint()..color = BrandColors.night.withValues(alpha: 0.94));
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.banner != banner;
}

/// The photo's side on a computer: the logo, and the perks.
class _Showcase extends StatelessWidget {
  final AuthSide side;
  final Widget? backButton;

  const _Showcase({required this.side, required this.backButton});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // A short or narrow window keeps just the logo.
        final room = box.maxHeight >= 560 && box.maxWidth >= 340;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (backButton != null) ...[backButton!, const SizedBox(width: 14)],
                // Smaller when the photo's side is narrow.
                const Flexible(
                  child: FadeSlideIn(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SportsHubLogo(height: 118, onDark: true),
                    ),
                  ),
                ),
              ],
            ),
            if (room && side == AuthSide.join) ...[
              const Spacer(flex: 3),
              const _JoinPitch(),
              const Spacer(flex: 4),
            ] else ...[
              const Spacer(),
              if (room) _PerkBar(wide: box.maxWidth >= 500),
            ],
          ],
        );
      },
    );
  }
}

typedef _Perk = (IconData icon, String label);

/// Signing in: what SportsHub does, along the navy foot.
class _PerkBar extends StatelessWidget {
  final bool wide;

  const _PerkBar({required this.wide});

  static const perks = <_Perk>[
    (Icons.travel_explore_rounded, 'Find\na gym'),
    (Icons.groups_rounded, 'Membership\nmanagement'),
    (Icons.qr_code_scanner_rounded, 'QR\ncheck-in'),
    (Icons.insights_rounded, 'Analytics\n& reports'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      for (final (icon, label) in perks)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600),
            ),
          ],
        ),
    ];
    // One row of four, or two of two where the photo's side is narrow.
    Widget row(List<Widget> cells) => IntrinsicHeight(
          child: Row(
            children: [
              for (final (i, cell) in cells.indexed) ...[
                if (i > 0) VerticalDivider(width: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.18)),
                Expanded(child: cell),
              ],
            ],
          ),
        );
    return FadeSlideIn(
      delay: const Duration(milliseconds: 160),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            decoration: BoxDecoration(
              color: BrandColors.night.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: wide
                ? row(items)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [row(items.sublist(0, 2)), const SizedBox(height: 16), row(items.sublist(2))],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Joining: a welcome, and what an account gives.
class _JoinPitch extends StatelessWidget {
  const _JoinPitch();

  static const perks = <_Perk>[
    (Icons.travel_explore_rounded, 'Find gyms across Bhutan'),
    (Icons.qr_code_2_rounded, 'Your membership card on your phone'),
    (Icons.devices_rounded, 'One account, on the web and in the app'),
  ];

  @override
  Widget build(BuildContext context) {
    const headline = TextStyle(
      fontSize: 54,
      height: 1.02,
      letterSpacing: -1,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      shadows: [Shadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 4))],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: staggered([
        _Slanted(
          child: Text.rich(
            const TextSpan(
              children: [
                TextSpan(text: 'Join\nSports'),
                TextSpan(text: 'Hub', style: TextStyle(color: Color(0xFFFF8A3D))),
              ],
            ),
            style: headline,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 30),
          child: Text(
            'Be part of our sports community',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 20, fontWeight: FontWeight.w500),
          ),
        ),
        for (final (icon, label) in perks)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF8A3D), BrandColors.orange],
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 23),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
      ]),
    );
  }
}

/// 'Stronger Together' above the card, underlined with an orange stroke.
class _Motto extends StatelessWidget {
  const _Motto();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _Slanted(
            child: Text(
              'Stronger Together',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                shadows: [Shadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 3))],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Transform.rotate(
            angle: -0.04,
            child: Container(
              width: 150,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(colors: [BrandColors.orange.withValues(alpha: 0), BrandColors.orange]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Leaning forward, like the logo's lettering.
class _Slanted extends StatelessWidget {
  final Widget child;

  const _Slanted({required this.child});

  @override
  Widget build(BuildContext context) =>
      Transform(transform: Matrix4.skewX(-0.16), alignment: Alignment.bottomLeft, child: child);
}

/// Back, in a frosted circle on the photo.
class _BackButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;

  const _BackButton({required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.22))),
      child: IconButton(
        tooltip: tooltip,
        color: Colors.white,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: onPressed,
      ),
    );
  }
}

/// The card's fields: white, with soft borders, orange when typing in them.
class _AuthInputs extends StatelessWidget {
  final Widget child;

  const _AuthInputs({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final dark = theme.brightness == Brightness.dark;
    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: color, width: width));
    final edge = dark ? brand.glassBorder : const Color(0xFFE1E6EF);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          fillColor: dark ? brand.card : Colors.white,
          prefixIconColor: brand.muted,
          suffixIconColor: brand.muted,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          border: outline(edge),
          enabledBorder: outline(edge),
          focusedBorder: outline(brand.accent, 1.6),
          floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) => TextStyle(
                color: states.contains(WidgetState.error)
                    ? theme.colorScheme.error
                    : states.contains(WidgetState.focused)
                        ? brand.accent
                        : brand.muted,
              )),
        ),
      ),
      child: child,
    );
  }
}

// ─── The card's parts ─────────────────────────────────────────────────────

/// The page's main action: an orange pill, with a spinner while it works.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({super.key, required this.label, this.icon, this.busy = false, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), BrandColors.orange]),
        boxShadow: [
          BoxShadow(
            color: BrandColors.orange.withValues(alpha: 0.38),
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 16.5),
        ),
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 21), const SizedBox(width: 10)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}

/// Another way through: a white button with a soft border.
class AuthSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const AuthSecondaryButton({super.key, required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: dark ? context.brand.card : Colors.white,
        foregroundColor: dark ? Colors.white : BrandColors.navy,
        side: BorderSide(color: dark ? context.brand.glassBorder : const Color(0xFFE1E6EF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w600, fontSize: 15),
      ),
      icon: Icon(icon, size: 21, color: context.brand.accent),
      label: Text(label),
    );
  }
}

/// A line with a word in the middle: 'or'.
class AuthDivider extends StatelessWidget {
  final String text;

  const AuthDivider({super.key, this.text = 'or'});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(text, style: TextStyle(color: context.brand.muted, fontSize: 13.5, fontWeight: FontWeight.w500)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// The card's foot: 'Don't have an account? Register here'.
class AuthSwitchLink extends StatelessWidget {
  final String question;
  final String action;
  final VoidCallback onPressed;

  const AuthSwitchLink({super.key, required this.question, required this.action, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: TextStyle(color: context.brand.muted, fontSize: 14.5)),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: context.brand.accent,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          child: Text(action),
        ),
      ],
    );
  }
}

/// A short note on a soft tint: what happens next.
class AuthNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const AuthNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: context.brand.muted))),
        ],
      ),
    );
  }
}

/// What went wrong, on a soft red.
class AuthError extends StatelessWidget {
  final String text;

  const AuthError(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final danger = context.brand.danger;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: danger, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: danger, fontWeight: FontWeight.w600, height: 1.35))),
        ],
      ),
    );
  }
}
