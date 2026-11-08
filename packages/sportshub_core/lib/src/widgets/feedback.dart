import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../utils/friendly_error.dart';

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
/// a warning, for a [problem]) beside [message]. The theme slides it in.
SnackBar feedbackBar(String message, {bool problem = false, Color? color}) => SnackBar(
      backgroundColor: problem ? (color ?? BrandColors.red) : BrandColors.navy,
      content: Row(
        children: [
          Icon(problem ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: problem ? Colors.white : const Color(0xFF4CC983), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );

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
  final result = await showDialog<bool>(
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
  return showDialog<String>(
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
