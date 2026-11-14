import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../router/core_routes.dart';
import '../supabase/supabase_provider.dart';
import '../theme/brand.dart';
import '../venues/venue.dart';
import '../venues/venue_repository.dart';
import '../venues/venue_widgets.dart';
import '../widgets/dashboard_kit.dart';
import '../widgets/motion.dart';
import 'assistant_chat.dart';

// SportsHub's assistant, for anyone, visitors included: what the floating
// Ask AI button opens outside a module's own pages. The ask-sportshub Edge
// Function has Cloudflare Workers AI answer from a guide about SportsHub
// (supabase/functions/ask-sportshub/reply.ts), or say "find gyms in Paro",
// which the app answers itself from the public list of verified venues.

enum PublicAskKind { help, findVenues, other }

/// What SportsHub's assistant answers with.
class PublicReply {
  final PublicAskKind kind;

  /// A few sentences: from the AI (from SportsHub's guide), or written here
  /// for a suggestion.
  final String? answer;

  /// The page that helps most, by its key in the guide: the core's
  /// ([corePages]) or a module's ([SportsHubModule.assistantLinks]).
  final String? page;

  /// For finding venues: what kind ('gym'), and where.
  final String venueType;
  final String? dzongkhag;

  /// Written by the AI (said under it), not here.
  final bool byAi;

  const PublicReply.help(String this.answer, {this.page})
      : kind = PublicAskKind.help,
        venueType = 'gym',
        dzongkhag = null,
        byAi = false;

  const PublicReply.findVenues({this.venueType = 'gym', this.dzongkhag})
      : kind = PublicAskKind.findVenues,
        answer = null,
        page = null,
        byAi = false;

  const PublicReply._(this.kind, {this.answer, this.page, this.venueType = 'gym', this.dzongkhag, this.byAi = true});

  /// The ask-sportshub function's answer; anything else is [PublicAskKind.other].
  factory PublicReply.fromJson(Map<String, dynamic> json) {
    final answer = (json['answer'] as String?)?.trim();
    final hasAnswer = answer != null && answer.isNotEmpty;
    switch (json['kind']) {
      case 'find_venues':
        return PublicReply._(
          PublicAskKind.findVenues,
          venueType: json['venue_type'] as String? ?? 'gym',
          dzongkhag: json['dzongkhag'] as String?,
        );
      case 'help' when hasAnswer || json['page'] is String:
        return PublicReply._(PublicAskKind.help, answer: hasAnswer ? answer : null, page: json['page'] as String?);
      case 'other' when hasAnswer:
        return PublicReply._(PublicAskKind.other, answer: answer);
    }
    return const PublicReply._(PublicAskKind.other, answer: publicAssistantWhatICanDo, byAi: false);
  }

  /// As the function takes it back, in the conversation so far.
  Map<String, dynamic> toJson() => {
        'kind': switch (kind) {
          PublicAskKind.help => 'help',
          PublicAskKind.findVenues => 'find_venues',
          PublicAskKind.other => 'other',
        },
        if (page != null) 'page': page,
        if (kind == PublicAskKind.findVenues) 'venue_type': venueType,
        if (dzongkhag != null) 'dzongkhag': dzongkhag,
      };
}

const publicAssistantWhatICanDo =
    'I answer questions about SportsHub: finding a gym, joining one, putting your gym on SportsHub, and your account.';

/// The core's pages SportsHub's assistant may point to, by the guide's keys.
/// Sign up and sign in only for visitors.
Map<String, ModuleMenuItem> corePages({required bool signedIn}) => {
      if (!signedIn) ...{
        'sign_up': const ModuleMenuItem(title: 'Sign up', icon: Icons.person_add_alt_1_rounded, route: CoreRoutes.signUp),
        'sign_in': const ModuleMenuItem(title: 'Sign in', icon: Icons.login_rounded, route: CoreRoutes.signIn),
      },
      'register_venue': const ModuleMenuItem(
          title: 'Register your venue', icon: Icons.add_business_rounded, route: CoreRoutes.registerVenue),
      if (signedIn)
        'account': const ModuleMenuItem(title: 'Your account', icon: Icons.person_rounded, route: CoreRoutes.account),
    };

// Suggestions: known answers, so the AI isn't asked (and they always work).
const _whatIsIt = PublicReply.help(
  'SportsHub brings gyms, grounds and games across Bhutan into one app, on the web, Android and iOS. '
  'Gyms run their members, packages and check-ins here; booking grounds and tournaments are on the ground '
  'booking website for now.',
);
const _joinGym = PublicReply.help(
  "You don't need an account. Go to a gym on SportsHub: the front desk registers you, sells you a package "
  'for 1 to 24 months and takes your payment (cash, mBoB or bank transfer). Your QR card comes on WhatsApp '
  'or as a download.',
  page: 'gyms',
);
const _checkIn = PublicReply.help(
  'Show your QR card at the counter. The desk can also type your 6-character member code or find you by '
  'your phone number. It works while your package covers that day.',
);
const _ownGym = PublicReply.help(
  'Sign up, then Register your venue, choose Gym and add your packages and prices. The SportsHub team checks '
  'the gym before visitors can see it; then add your staff and start registering members.',
  page: 'register_venue',
);

final publicAssistantRepositoryProvider =
    Provider<PublicAssistantRepository>((ref) => PublicAssistantRepository(ref));

class PublicAssistantRepository {
  PublicAssistantRepository(this._ref);
  final Ref _ref;

  /// SportsHub's assistant's answer to [question]; the last turns of
  /// [history] go along. And how many questions are left today.
  Future<({PublicReply reply, int? left})> ask(String question, List<({String question, PublicReply reply})> history) async {
    final recent = history.length > 3 ? history.sublist(history.length - 3) : history;
    final data = await invokeAssistant(_ref.read(supabaseProvider), 'ask-sportshub', {
      'question': question,
      'history': [for (final t in recent) {'question': t.question, 'reply': t.reply.toJson()}],
    });
    return (reply: PublicReply.fromJson(data), left: (data['left'] as num?)?.toInt());
  }
}

/// The conversation with SportsHub's assistant, kept while the app runs.
final publicAssistantProvider =
    NotifierProvider<PublicAssistantChat, AssistantChat<PublicReply>>(PublicAssistantChat.new);

class PublicAssistantChat extends Notifier<AssistantChat<PublicReply>> with AssistantConversation<PublicReply> {
  @override
  AssistantChat<PublicReply> build() => const AssistantChat();

  @override
  Future<({PublicReply reply, int? left})> answer(String question, List<({String question, PublicReply reply})> before) =>
      ref.read(publicAssistantRepositoryProvider).ask(question, before);
}

/// SportsHub's assistant in the floating panel.
class SportsHubAssistantPanel extends ConsumerWidget {
  const SportsHubAssistantPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(publicAssistantProvider);
    final notifier = ref.read(publicAssistantProvider.notifier);
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <SportsHubModule>[];
    final gyms = modules.any((m) => m.venueKinds.any((k) => k.key == 'gym'));
    AssistantSuggestion suggest(String label, PublicReply reply) =>
        AssistantSuggestion(label, () => notifier.suggest(label, reply));
    final suggestions = [
      suggest('What is SportsHub?', _whatIsIt),
      if (gyms) ...[
        suggest('How do I join a gym?', _joinGym),
        suggest('Gyms in Thimphu', const PublicReply.findVenues(dzongkhag: 'Thimphu')),
        suggest('How do I check in?', _checkIn),
        suggest('Put my gym on SportsHub', _ownGym),
      ],
    ];
    return AssistantPanel(
      title: 'SportsHub assistant',
      subtitle: 'Questions about SportsHub',
      actions: [
        if (chat.turns.isNotEmpty)
          IconButton(
            tooltip: 'Start again',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: chat.busy ? null : notifier.startAgain,
          ),
      ],
      child: AssistantConversationView<PublicReply>(
        compact: true,
        chat: chat,
        hint: 'Ask about SportsHub…',
        note: "Your question goes to Cloudflare's AI: no personal details, please",
        suggestions: suggestions,
        onAsk: notifier.ask,
        onRetry: notifier.retryLast,
        welcome: AssistantWelcome(
          title: 'Hi! Ask me about SportsHub',
          intro: 'Finding a gym, joining one, checking in, putting your gym on SportsHub, or your account: '
              'ask in your own words, in English or Dzongkha.',
          points: const [
            (Icons.bolt_rounded, "Suggestions answer straight away and don't count against today's questions."),
          ],
          suggestions: suggestions,
        ),
        answer: (context, reply) => _PublicAnswer(reply: reply, modules: modules),
      ),
    );
  }
}

/// One of SportsHub's assistant's answers.
class _PublicAnswer extends ConsumerWidget {
  final PublicReply reply;
  final List<SportsHubModule> modules;

  const _PublicAnswer({required this.reply, required this.modules});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.brand.muted;
    if (reply.kind == PublicAskKind.findVenues) return _Venues(reply: reply, modules: modules);
    if (reply.kind == PublicAskKind.other) {
      return ConsoleCard(
        icon: Icons.auto_awesome_rounded,
        title: 'SportsHub assistant',
        child: Text(reply.answer ?? publicAssistantWhatICanDo, style: const TextStyle(height: 1.45)),
      );
    }
    final links = {
      ...corePages(signedIn: ref.watch(currentUserIdProvider) != null),
      for (final m in modules) ...m.assistantLinks,
    };
    final link = links[reply.page];
    return ConsoleCard(
      icon: Icons.lightbulb_outline_rounded,
      title: 'SportsHub',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reply.answer ?? 'Open ${link?.title ?? 'SportsHub'} to see.', style: const TextStyle(height: 1.45)),
          if (link != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => assistantOpen(context, link),
              icon: Icon(link.isExternal ? Icons.open_in_new_rounded : Icons.arrow_forward_rounded, size: 18),
              label: Text(link.title),
            ),
          ],
          if (reply.byAi) ...[
            const SizedBox(height: 10),
            Text("Written by AI from SportsHub's guide.", style: TextStyle(color: muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// "Gyms in Paro": the verified ones, from SportsHub's public list.
class _Venues extends ConsumerWidget {
  final PublicReply reply;
  final List<SportsHubModule> modules;

  const _Venues({required this.reply, required this.modules});

  static const _shown = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.brand.muted;
    SportsHubModule? module;
    VenueKind? kind;
    for (final m in modules) {
      for (final k in m.venueKinds) {
        if (k.key == reply.venueType) (module, kind) = (m, k);
      }
    }
    final what = '${(kind?.label ?? reply.venueType).toLowerCase()}s';
    final where = reply.dzongkhag == null ? 'on SportsHub' : 'in ${reply.dzongkhag}';
    final title = '${what[0].toUpperCase()}${what.substring(1)} $where';
    if (module == null || kind == null) {
      return ConsoleCard(
        icon: Icons.storefront_rounded,
        title: title,
        child: Text('There are no $what on SportsHub yet.', style: TextStyle(color: muted)),
      );
    }
    final query = (type: reply.venueType, dzongkhag: reply.dzongkhag);
    final value = ref.watch(publicVenuesProvider(query));
    final all = module.assistantLinks.entries.where((e) => e.value.route != null).firstOrNull?.value;
    return ConsoleCard(
      icon: kind.icon,
      title: title,
      child: switch (value) {
        AsyncValue(:final List<Venue> value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                value.isEmpty
                    ? 'No $what $where yet.'
                    : value.length == 1
                        ? '1 ${what.substring(0, what.length - 1)} $where.'
                        : '${value.length} $what $where.',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ConsoleInk.of(context).heading),
              ),
              for (final venue in value.take(_shown)) ...[
                const SizedBox(height: 12),
                VenueCard(
                  venue: venue,
                  placeholderIcon: kind.icon,
                  onTap: () {
                    final route = module!.publicVenueRoute(venue);
                    if (route != null) assistantGo(context, route);
                  },
                ),
              ],
              if (all != null && (value.length > _shown || value.isEmpty)) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => assistantOpen(context, all),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(value.isEmpty ? all.title : 'See all ${value.length}'),
                  ),
                ),
              ],
            ],
          ),
        AsyncValue(hasError: true, hasValue: false) => Row(
            children: [
              Expanded(child: Text("The list couldn't load. Check your connection.", style: TextStyle(color: muted))),
              TextButton(onPressed: () => ref.invalidate(publicVenuesProvider(query)), child: const Text('Try again')),
            ],
          ),
        _ => const LoadingSkeleton.rows(),
      },
    );
  }
}
