import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../utils/friendly_error.dart';
import 'motion.dart';

/// Runs [action], then shows [success] (if given) or what went wrong.
/// Returns whether it worked.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  final danger = context.brand.danger;
  try {
    await action();
    if (success != null) messenger.showSnackBar(feedbackBar(success));
    return true;
  } catch (e) {
    messenger.showSnackBar(feedbackBar(friendlyError(e), problem: true, color: danger));
    return false;
  }
}

/// Tells the person how something went, at the foot of the page: a tick (or
/// a warning, for a [problem]) that pops in beside [message]. The theme
/// slides it in.
SnackBar feedbackBar(String message, {bool problem = false, Color? color}) => SnackBar(
      backgroundColor: problem ? (color ?? BrandColors.red) : BrandColors.navy,
      content: Row(
        children: [
          PopIn(
            delay: const Duration(milliseconds: 120),
            child: Icon(problem ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                color: problem ? Colors.white : const Color(0xFF4CC983), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );

/// A dialog that arrives: it fades in as it grows the last few percent and
/// rises a touch; it leaves quicker than it came. Use it as showDialog.
Future<T?> showAppDialog<T>({required BuildContext context, required WidgetBuilder builder, bool barrierDismissible = true}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  // The page's themes (a service's type, say) carried into the dialog, as
  // showDialog does.
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final still = reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: still ? Duration.zero : Motion.modal,
    pageBuilder: (context, _, __) => themes.wrap(SafeArea(child: Builder(builder: builder))),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.ease, reverseCurve: Motion.easeIn);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(curved),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Shows [feedbackBar] on [context]'s page.
void showFeedback(BuildContext context, String message, {bool problem = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(feedbackBar(message, problem: problem, color: context.brand.danger));

/// Asks before doing something; true when they confirm.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Yes',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: context.brand.danger) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a line of text (e.g. why a venue is sent back); null if cancelled.
Future<String?> askText(BuildContext context,
    {required String title, String? hint, String confirmLabel = 'Send', bool required = false}) {
  final controller = TextEditingController();
  return showAppDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (required && text.isEmpty) return;
            Navigator.pop(context, text);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
