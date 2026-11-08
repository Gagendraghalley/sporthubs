import 'package:flutter/material.dart';

import 'brand.dart';

/// Light mode: white frosted glass on a soft blue-white background, navy and
/// orange from the logo. Dark mode: the same glass, dark.
abstract final class AppTheme {
  static ThemeData get light => _build(
        Brand.light,
        ColorScheme.fromSeed(
          seedColor: BrandColors.navy,
          primary: BrandColors.navy,
          onPrimary: Colors.white,
          secondary: BrandColors.orange,
          onSecondary: Colors.white,
          tertiary: BrandColors.blue,
          surface: Colors.white,
        ),
      );

  static ThemeData get dark => _build(
        Brand.dark,
        ColorScheme.fromSeed(
          seedColor: BrandColors.navy,
          brightness: Brightness.dark,
          primary: const Color(0xFF9CC2FF),
          onPrimary: BrandColors.navy,
          secondary: const Color(0xFFFF8A3D),
          onSecondary: Colors.black,
          tertiary: const Color(0xFF7FB0F5),
          surface: const Color(0xFF111A2E),
        ),
      );

  static ThemeData _build(Brand brand, ColorScheme colors) {
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
          side: BorderSide(color: brand.glassBorder),
          textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brand.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: brand.glassBorder)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: brand.glassBorder)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: brand.glassBorder),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
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
