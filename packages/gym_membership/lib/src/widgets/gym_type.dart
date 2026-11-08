import 'package:flutter/material.dart';
import 'package:sportshub_core/sportshub_core.dart';

/// The platform's typeface (sportshub_core's brandFont), which the theme
/// already gives every page; kept for the Welcome page and the card picture.
const gymFont = brandFont;

/// [child] in the platform's typeface for every text style of the theme, for
/// pages drawn outside the app's theme (none now; kept so callers keep
/// working).
class GymType extends StatelessWidget {
  final Widget child;

  const GymType({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: gymFont),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: gymFont),
      ),
      child: child,
    );
  }
}
