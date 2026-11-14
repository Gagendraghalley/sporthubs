import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../theme/brand.dart';
import '../utils/friendly_error.dart';
import '../utils/launch.dart';
import '../widgets/app_page.dart';
import '../widgets/dashboard_kit.dart';
import '../widgets/motion.dart';
import 'public_assistant.dart';

// Ask AI, the platform's part: the floating button on every page, the panel
// it opens, and the conversation both assistants share: SportsHub's (about
// the platform, for anyone) and a module's own (a gym's, for its staff).
// The AI only chooses what answers a question; the app works the answer out.

// ─── A conversation ────────────────────────────────────────────────────────

/// One question, and what answers it: [reply], or [problem] (why there
/// isn't one).
@immutable
class AssistantTurn<R> {
  const AssistantTurn(this.question, {this.reply, this.problem});

  final String question;
  final R? reply;
  final String? problem;

  bool get waiting => reply == null && problem == null;
}

/// A conversation with an assistant: its questions in order, and how many
/// the person may still ask today, once the AI has said.
@immutable
class AssistantChat<R> {
  const AssistantChat({this.turns = const [], this.left});

  final List<AssistantTurn<R>> turns;
  final int? left;

  /// A question is waiting for its answer.
  bool get busy => turns.isNotEmpty && turns.last.waiting;

  /// The questions answered so far, for the AI to follow on from.
  List<({String question, R reply})> get answered => [
        for (final t in turns)
          if (t.reply case final R reply) (question: t.question, reply: reply),
      ];

  AssistantChat<R> _with(List<AssistantTurn<R>> turns, {int? left}) => AssistantChat(turns: turns, left: left ?? this.left);

  /// [turn] answered: with [reply], or [problem]. Nothing changes if it's no
  /// longer there (they started again).
  AssistantChat<R> _settle(AssistantTurn<R> turn, {R? reply, String? problem, int? left}) => _with([
        for (final t in turns) identical(t, turn) ? AssistantTurn<R>(t.question, reply: reply, problem: problem) : t,
      ], left: left);
}

/// Why a question got no answer, in words to show; with how many questions
/// are left today, when the assistant said.
class AssistantProblem extends StateError {
  AssistantProblem(super.message, {this.left});
  final int? left;
}

/// Calls an assistant's Edge Function [name] with [body]; what it says went
/// wrong becomes an [AssistantProblem].
Future<Map<String, dynamic>> invokeAssistant(SupabaseClient client, String name, Map<String, dynamic> body) async {
  try {
    final response = await client.functions.invoke(name, body: body);
    return (response.data as Map?)?.cast<String, dynamic>() ?? const {};
  } on FunctionException catch (e) {
    final details = e.details;
    if (details is Map && details['error'] is String) {
      throw AssistantProblem(details['error'] as String, left: (details['left'] as num?)?.toInt());
    }
    rethrow;
  }
}

/// What an assistant's notifier does with its conversation: ask (through
/// [answer]), show a suggestion, try the last question again, start again.
/// Its state lives in a provider (a Notifier with this mixin), so it's still
/// there when the panel is opened again, or on the full page.
mixin AssistantConversation<R> {
  /// The notifier's state.
  AssistantChat<R> get state;
  set state(AssistantChat<R> value);

  /// The AI's answer to [question], with [before] (the conversation so far);
  /// and how many questions are left today.
  Future<({R reply, int? left})> answer(String question, List<({String question, R reply})> before);

  Future<void> ask(String text) async {
    final question = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (question.isEmpty || state.busy) return;
    final before = state.answered;
    final turn = AssistantTurn<R>(question);
    state = state._with([...state.turns, turn]);
    try {
      final r = await answer(question, before);
      state = state._settle(turn, reply: r.reply, left: r.left);
    } catch (e) {
      state = state._settle(turn, problem: friendlyError(e), left: e is AssistantProblem ? e.left : null);
    }
  }

  /// A suggestion: its answer is known, so the AI isn't asked.
  void suggest(String label, R reply) {
    if (state.busy) return;
    state = state._with([...state.turns, AssistantTurn<R>(label, reply: reply)]);
  }

  void retryLast() {
    if (state.turns.isEmpty || state.busy) return;
    final last = state.turns.last;
    state = state._with([...state.turns]..removeLast());
    ask(last.question);
  }

  void startAgain() {
    if (!state.busy) state = AssistantChat<R>(left: state.left);
  }
}

// ─── The conversation on screen ────────────────────────────────────────────

/// A question to tap: answered straight away, without the AI.
class AssistantSuggestion {
  const AssistantSuggestion(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
}

/// A conversation: [welcome] before the first question; then each question
/// with what answers it ([answer]) under it, the newest by the box; and
/// [suggestions] over the box once it has started. [compact] in the floating
/// panel; otherwise the body of a page.
class AssistantConversationView<R> extends StatefulWidget {
  final AssistantChat<R> chat;
  final Widget welcome;
  final Widget Function(BuildContext context, R reply) answer;
  final List<AssistantSuggestion> suggestions;
  final ValueChanged<String> onAsk;
  final VoidCallback onRetry;
  final String hint;
  final String note;
  final bool compact;

  const AssistantConversationView({
    super.key,
    required this.chat,
    required this.welcome,
    required this.answer,
    required this.suggestions,
    required this.onAsk,
    required this.onRetry,
    this.hint = 'Ask a question…',
    this.note = 'Only your question goes to the AI',
    this.compact = false,
  });

  @override
  State<AssistantConversationView<R>> createState() => _AssistantConversationViewState<R>();
}

class _AssistantConversationViewState<R> extends State<AssistantConversationView<R>> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant AssistantConversationView<R> old) {
    super.didUpdateWidget(old);
    // A new question: show it (the conversation reads up from the box).
    if (widget.chat.turns.length > old.chat.turns.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        if (reduceMotion(context)) {
          _scroll.jumpTo(0);
        } else {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
        }
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty || widget.chat.busy) return;
    widget.onAsk(text);
    _input.clear();
    if (MediaQuery.sizeOf(context).width >= 900) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final padding = widget.compact
        ? const EdgeInsets.fromLTRB(14, 16, 14, 12)
        : pagePadding(context).copyWith(bottom: 16);
    return Column(
      children: [
        Expanded(
          child: chat.turns.isEmpty
              ? ListView(padding: padding, children: [FadeSlideIn(child: widget.welcome)])
              : ListView(
                  controller: _scroll,
                  reverse: true,
                  padding: padding,
                  children: [
                    for (final t in chat.turns.reversed)
                      FadeSlideIn(
                        key: ObjectKey(t.question.hashCode ^ identityHashCode(t.reply ?? t)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Question(text: t.question),
                              const SizedBox(height: 10),
                              _answerTo(context, t),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        _AskBar(
          controller: _input,
          focus: _focus,
          busy: chat.busy,
          hint: widget.hint,
          note: [
            widget.note,
            if (chat.left case final left?) '$left question${left == 1 ? '' : 's'} left today',
          ].join(' · '),
          suggestions: chat.turns.isEmpty ? const [] : widget.suggestions,
          gutter: widget.compact ? 14 : (MediaQuery.sizeOf(context).width >= 900 ? 28 : 16),
          onSend: _send,
        ),
      ],
    );
  }

  Widget _answerTo(BuildContext context, AssistantTurn<R> t) {
    if (t.waiting) {
      return const ConsoleCard(
        icon: Icons.auto_awesome_rounded,
        title: 'Thinking…',
        child: LoadingSkeleton.rows(semanticsLabel: 'Working out the answer'),
      );
    }
    if (t.problem != null) {
      return ConsoleCard(
        icon: Icons.error_outline_rounded,
        title: "Couldn't answer",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.problem!, style: const TextStyle(height: 1.4)),
            if (identical(t, widget.chat.turns.last)) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      );
    }
    return widget.answer(context, t.reply as R);
  }
}

/// The question box, with suggestions over it once the conversation has
/// started.
class _AskBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final String hint;
  final String note;
  final List<AssistantSuggestion> suggestions;
  final double gutter;
  final ValueChanged<String> onSend;

  const _AskBar({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.hint,
    required this.note,
    required this.suggestions,
    required this.gutter,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return GlassBar(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (suggestions.isNotEmpty) ...[
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final s in suggestions)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.bolt_rounded, size: 16),
                            label: Text(s.label),
                            onPressed: busy ? null : s.onTap,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      maxLength: 300,
                      textInputAction: TextInputAction.send,
                      onSubmitted: busy ? null : onSend,
                      decoration: InputDecoration(
                        hintText: hint,
                        counterText: '',
                        prefixIcon: const Icon(Icons.auto_awesome_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Ask',
                    onPressed: busy ? null : () => onSend(controller.text),
                    icon: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(note, textAlign: TextAlign.center, style: TextStyle(color: context.brand.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// What they asked, on the right.
class _Question extends StatelessWidget {
  final String text;

  const _Question({required this.text});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: ConsoleInk.of(context).heading)),
        ),
      ),
    );
  }
}

/// An assistant's welcome: what it's for, a few lines on how it works, and
/// questions to start with.
class AssistantWelcome extends StatelessWidget {
  final String title;
  final String intro;
  final List<(IconData, String)> points;
  final List<AssistantSuggestion> suggestions;
  final String? examples;

  const AssistantWelcome({
    super.key,
    required this.title,
    required this.intro,
    this.points = const [],
    this.suggestions = const [],
    this.examples,
  });

  @override
  Widget build(BuildContext context) {
    final blue = context.colors.tertiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: [blue.withValues(alpha: 0.10), BrandColors.orange.withValues(alpha: 0.06)]),
            border: Border.all(color: blue.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: blue, size: 26),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                ],
              ),
              const SizedBox(height: 10),
              Text(intro, style: const TextStyle(height: 1.45)),
              for (final (icon, text) in points) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: context.brand.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text, style: TextStyle(color: context.brand.muted, height: 1.4))),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Try', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in suggestions)
                ActionChip(avatar: const Icon(Icons.bolt_rounded, size: 18), label: Text(s.label), onPressed: s.onTap),
            ],
          ),
        ],
        if (examples != null) ...[
          const SizedBox(height: 16),
          Text(examples!, style: TextStyle(color: context.brand.muted, height: 1.45)),
        ],
      ],
    );
  }
}

// ─── The floating button and its panel ─────────────────────────────────────

/// Marks what's inside the floating panel: going to a page closes it.
class AssistantPanelScope extends InheritedWidget {
  const AssistantPanelScope({super.key, required super.child});

  static bool inPanel(BuildContext context) => context.getInheritedWidgetOfExactType<AssistantPanelScope>() != null;

  @override
  bool updateShouldNotify(AssistantPanelScope oldWidget) => false;
}

/// Goes to [route] from an answer: closing the floating panel first, when
/// it's in one.
void assistantGo(BuildContext context, String route) {
  final router = GoRouter.of(context);
  if (AssistantPanelScope.inPanel(context)) Navigator.of(context, rootNavigator: true).pop();
  router.go(route);
}

/// Opens [item] (a page, or a website) from an answer.
Future<void> assistantOpen(BuildContext context, ModuleMenuItem item) async {
  if (item.route != null) return assistantGo(context, item.route!);
  await openExternal(context, item.externalUrl!);
}

/// What the floating button opens: a header (the assistant, and what it's
/// about), then its conversation.
class AssistantPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  const AssistantPanel({super.key, required this.title, this.subtitle, this.actions = const [], required this.child});

  @override
  Widget build(BuildContext context) {
    final inPanel = AssistantPanelScope.inPanel(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [BrandColors.navy, Color(0xFF1B3A7A)]),
          ),
          child: IconButtonTheme(
            data: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Colors.white)),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [BrandColors.orange, Color(0xFFFFA24D)]),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      if (subtitle != null)
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12.5)),
                    ],
                  ),
                ),
                ...actions,
                if (inPanel)
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Opens [panel] from the floating button: beside the page in its corner on
/// a computer, the whole screen on a phone.
Future<void> openAssistant(BuildContext context, Widget panel) {
  final size = MediaQuery.sizeOf(context);
  final scoped = AssistantPanelScope(child: panel);
  if (size.width < 720) {
    return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: context.brand.background,
        body: SafeArea(bottom: false, child: scoped),
      ),
    ));
  }
  final still = reduceMotion(context);
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Close Ask AI',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: still ? Duration.zero : Motion.modal,
    pageBuilder: (context, _, __) => SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 420,
            height: math.min(680, size.height - 40),
            child: Material(
              color: context.brand.background,
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: scoped,
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(curved),
          alignment: Alignment.bottomRight,
          child: child,
        ),
      );
    },
  );
}

/// The floating Ask AI button, a standard floating action button in the
/// brand's orange: "Ask AI" beside its icon on a computer, the icon alone on
/// a phone. No hero, so it never clashes with a page's own button.
class AssistantButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AssistantButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final accent = context.brand.accent;
    const icon = Icon(Icons.auto_awesome_rounded);
    if (!wide) {
      return FloatingActionButton(
        heroTag: null,
        tooltip: 'Ask AI',
        backgroundColor: accent,
        foregroundColor: Colors.white,
        onPressed: onPressed,
        child: icon,
      );
    }
    return FloatingActionButton.extended(
      heroTag: null,
      tooltip: 'Ask AI',
      backgroundColor: accent,
      foregroundColor: Colors.white,
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.1),
      onPressed: onPressed,
      icon: icon,
      label: const Text('Ask AI'),
    );
  }
}

/// The core's pages with a bar of buttons along the bottom: a role's editor.
final _barPages = RegExp(r'^/(manage/[^/]+/roles|admin/roles)/[^/]+$');

/// [child] with the floating Ask AI button in its corner. On a module's
/// pages with an assistant of its own, the button opens that one; elsewhere
/// SportsHub's. Not on pages it would get in the way of.
class AssistantFrame extends ConsumerWidget {
  /// The page's path.
  final String location;
  final Widget child;

  const AssistantFrame({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <SportsHubModule>[];
    if (_barPages.hasMatch(location) || modules.any((m) => m.hidesAssistantButton(location))) return child;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          right: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: FadeSlideIn(
            child: AssistantButton(onPressed: () {
              Widget? panel;
              for (final m in modules) {
                panel = m.buildAssistant(context, location);
                if (panel != null) break;
              }
              openAssistant(context, panel ?? const SportsHubAssistantPanel());
            }),
          ),
        ),
      ],
    );
  }
}
