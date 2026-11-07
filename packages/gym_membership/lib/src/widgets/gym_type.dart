import 'package:flutter/material.dart';

/// Plus Jakarta Sans, declared in this package's pubspec.
const gymFont = 'packages/gym_membership/PlusJakartaSans';

/// [child] in the gym pages' own type (the Welcome page, the dashboard):
/// Plus Jakarta Sans for every text style of the theme.
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
