import 'package:flutter/material.dart';

import 'brand.dart';

/// Light mode: white cards with soft edges on a cool grey page, navy for
/// buttons and orange for the main action and what's active (LightColors).
/// Dark mode: frosted glass on navy.
abstract final class AppTheme {
  static ThemeData get light => _build(
        Brand.light,
        // Every role set by hand: a scheme from the seed alone tints the
        // surfaces lilac, which fights the navy and orange.
        ColorScheme.fromSeed(
          seedColor: LightColors.navy,
          primary: LightColors.navy,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFE6ECF6),
          onPrimaryContainer: LightColors.navy,
          secondary: LightColors.orange,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFFFEDDF),
          onSecondaryContainer: const Color(0xFF9A3A0B),
          tertiary: BrandColors.blue,
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFE3EDFB),
          onTertiaryContainer: const Color(0xFF0F3F86),
          error: LightColors.danger,
          onError: Colors.white,
          errorContainer: const Color(0xFFFDECEC),
          onErrorContainer: const Color(0xFF8E1F1F),
          surface: LightColors.card,
          onSurface: LightColors.ink,
          onSurfaceVariant: LightColors.muted,
          surfaceDim: const Color(0xFFE7ECF3),
          surfaceBright: LightColors.card,
          surfaceContainerLowest: LightColors.card,
          surfaceContainerLow: const Color(0xFFF8FAFC),
          surfaceContainer: const Color(0xFFF3F6FA),
          surfaceContainerHigh: LightColors.backgroundAlt,
          surfaceContainerHighest: const Color(0xFFE7ECF3),
          outline: const Color(0xFFC3CCD9),
          outlineVariant: LightColors.border,
          inverseSurface: LightColors.ink,
          onInverseSurface: LightColors.background,
          inversePrimary: const Color(0xFFFFB27A),
          surfaceTint: Colors.transparent,
        ),
      );

  static ThemeData get dark => _build(
        Brand.dark,
        ColorScheme.fromSeed(
          seedColor: BrandColors.navy,
          brightness: Brightness.dark,
          primary: BrandColors.orange,
          onPrimary: BrandColors.navy,
          secondary: const Color(0xFF9CC2FF),
          onSecondary: BrandColors.navy,
          tertiary: const Color(0xFF7FB0F5),
          surface: BrandColors.slateNavy,
        ),
      );

  static ThemeData _build(Brand brand, ColorScheme colors) {
    // What follows `light ?` is the light theme's own; the other side is what
    // the dark theme has always had, so it stays as it is.
    final light = colors.brightness == Brightness.light;
    final radius = BorderRadius.circular(16);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: brandFont,
      scaffoldBackgroundColor: brand.background,
      extensions: [brand],
      // Pages fade in and rise a little, on every platform: moving between
      // services and pages feels like one app.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: SoftRiseTransitionsBuilder(),
        TargetPlatform.iOS: SoftRiseTransitionsBuilder(),
        TargetPlatform.macOS: SoftRiseTransitionsBuilder(),
        TargetPlatform.windows: SoftRiseTransitionsBuilder(),
        TargetPlatform.linux: SoftRiseTransitionsBuilder(),
        TargetPlatform.fuchsia: SoftRiseTransitionsBuilder(),
      }),
    );
    OutlineInputBorder field(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: color, width: width));
    bool on(Set<WidgetState> states) => states.contains(WidgetState.selected);
    // Bar icons a little quieter than the title, in the light.
    const barIcons = IconThemeData(color: Color(0xFF475569));
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: colors.onSurface,
        iconTheme: light ? barIcons : null,
        actionsIconTheme: light ? barIcons : null,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: colors.onSurface),
      ),
      cardTheme: CardThemeData(
        color: brand.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: brand.glassBorder)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          // White on the grey page, so it reads as a button and not a hole.
          backgroundColor: light ? LightColors.card : null,
          side: BorderSide(color: brand.fieldBorder),
          textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brand.card,
        border: field(brand.fieldBorder),
        enabledBorder: field(brand.fieldBorder),
        // Light: orange where they're typing, as on the sign-in card.
        focusedBorder: light ? field(brand.accent, 1.6) : field(colors.primary, 2),
        hintStyle: light ? const TextStyle(color: Color(0xFF94A3B8)) : null,
        prefixIconColor: light ? brand.muted : null,
        suffixIconColor: light ? brand.muted : null,
        floatingLabelStyle: light
            ? WidgetStateTextStyle.resolveWith((states) => TextStyle(
                  color: states.contains(WidgetState.error)
                      ? colors.error
                      : states.contains(WidgetState.focused)
                          ? LightColors.orangeText
                          : brand.muted,
                ))
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: light
            ? WidgetStateBorderSide.resolveWith((states) =>
                BorderSide(color: on(states) ? brand.accent.withValues(alpha: 0.45) : brand.fieldBorder))
            : BorderSide(color: brand.glassBorder),
        backgroundColor: light ? LightColors.card : null,
        checkmarkColor: light ? colors.onSecondaryContainer : null,
      ),
      segmentedButtonTheme: light
          ? SegmentedButtonThemeData(
              style: SegmentedButton.styleFrom(
                backgroundColor: LightColors.card,
                foregroundColor: brand.body,
                selectedBackgroundColor: colors.secondaryContainer,
                selectedForegroundColor: colors.onSecondaryContainer,
                side: BorderSide(color: brand.fieldBorder),
              ),
            )
          : base.segmentedButtonTheme,
      switchTheme: light
          ? SwitchThemeData(
              trackColor: WidgetStateProperty.resolveWith((s) => on(s) ? brand.accent : colors.surfaceContainerHighest),
              thumbColor: WidgetStateProperty.resolveWith((s) => on(s) ? Colors.white : const Color(0xFF94A3B8)),
              trackOutlineColor: WidgetStateProperty.resolveWith((s) => on(s) ? Colors.transparent : brand.fieldBorder),
            )
          : base.switchTheme,
      checkboxTheme: light
          ? CheckboxThemeData(
              fillColor: WidgetStateProperty.resolveWith((s) => on(s) ? brand.accent : null),
              checkColor: const WidgetStatePropertyAll(Colors.white),
              side: const BorderSide(color: Color(0xFFB4BFCE), width: 1.6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            )
          : base.checkboxTheme,
      progressIndicatorTheme: light
          ? ProgressIndicatorThemeData(color: brand.accent, linearTrackColor: brand.surfaceAlt)
          : base.progressIndicatorTheme,
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: light ? const Color(0xFFCBD5E1) : null,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: light ? LightColors.navy.withValues(alpha: 0.35) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: light ? BorderSide(color: brand.glassBorder) : BorderSide.none,
        ),
      ),
      datePickerTheme: light
          ? DatePickerThemeData(
              backgroundColor: LightColors.card,
              surfaceTintColor: Colors.transparent,
              headerForegroundColor: brand.ink,
              dividerColor: brand.glassBorder,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            )
          : base.datePickerTheme,
      drawerTheme: light
          ? const DrawerThemeData(backgroundColor: LightColors.card, surfaceTintColor: Colors.transparent)
          : base.drawerTheme,
      menuTheme: light
          ? MenuThemeData(
              style: MenuStyle(
                backgroundColor: const WidgetStatePropertyAll(LightColors.card),
                surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
                elevation: const WidgetStatePropertyAll(8),
                shadowColor: WidgetStatePropertyAll(LightColors.navy.withValues(alpha: 0.3)),
                side: WidgetStatePropertyAll(BorderSide(color: brand.glassBorder)),
              ),
            )
          : base.menuTheme,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w600, color: Colors.white),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(color: BrandColors.night.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontFamily: brandFont, color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: light ? LightColors.navy.withValues(alpha: 0.3) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: brand.glassBorder)),
      ),
      dividerTheme: DividerThemeData(color: brand.glassBorder, space: 1),
    );
  }
}

/// A page comes in by fading and rising 12 pixels; the page under it stays
/// put. Short (260 ms), so it reads as smooth rather than slow.
class SoftRiseTransitionsBuilder extends PageTransitionsBuilder {
  const SoftRiseTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
