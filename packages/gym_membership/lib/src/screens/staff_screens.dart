import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../widgets/gym_widgets.dart';

/// When a membership confirmed today for [memberId] would start: today, or
/// the day after their last paid membership at this gym ends.
DateTime renewalStart(Iterable<GymSubscription> gymSubscriptions, String memberId, DateTime today) {
  DateTime? lastEnd;
  for (final s in gymSubscriptions) {
    if (s.memberId != memberId || s.status != SubscriptionStatus.active || s.endDate == null) continue;
    if (lastEnd == null || s.endDate!.isAfter(lastEnd)) lastEnd = s.endDate;
  }
  if (lastEnd == null || lastEnd.isBefore(today)) return today;
  return lastEnd.add(const Duration(days: 1));
}

/// Members' requests: confirm the payment to activate, or cancel.
class RequestsScreen extends ConsumerWidget {
  final String venueId;

  const RequestsScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Membership requests',
      builder: (context, access) => AppPage(
        title: 'Membership requests',
        body: AsyncValueView<List<GymSubscription>>(
          value: ref.watch(gymSubscriptionsProvider(venueId)),
          onRetry: () => ref.invalidate(gymSubscriptionsProvider(venueId)),
          data: (all) {
            final pending = all.where((s) => s.isPending).toList()..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
            if (pending.isEmpty) {
              return const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No requests waiting',
                message: 'When a member asks to join or renew, it shows here.',
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(gymSubscriptionsProvider(venueId).future),
              child: ListView.separated(
                padding: pagePadding(context),
                itemCount: pending.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _RequestCard(request: pending[i], all: all),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final GymSubscription request;
  final List<GymSubscription> all;

  const _RequestCard({required this.request, required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final renewing = all.any((s) => s.memberId == r.memberId && s.status == SubscriptionStatus.active);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(r.memberDisplayName, style: context.text.titleMedium)),
              if (renewing) StatusChip(label: 'Renewal', color: context.colors.tertiary),
            ],
          ),
          const SizedBox(height: 4),
          Text('${r.planName} · ${formatDuration(r.durationDays)} · ${r.price == 0 ? 'Free' : formatNu(r.price)}'),
          Text('Asked ${formatMoment(r.requestedAt)}${r.memberCode == null ? '' : ' · Code ${r.memberCode}'}',
              style: TextStyle(color: context.brand.muted)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (r.memberPhone != null)
                IconButton.outlined(
                  tooltip: 'Call ${r.memberDisplayName}',
                  onPressed: () => callPhone(context, r.memberPhone!),
                  icon: const Icon(Icons.call_outlined),
                ),
              const Spacer(),
              TextButton(onPressed: () => _cancel(context, ref), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _confirm(context, ref), child: const Text('Confirm payment')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final sure = await confirmAction(
      context,
      title: "Cancel ${request.memberDisplayName}'s request?",
      message: 'They will be told it was cancelled.',
      confirmLabel: 'Cancel request',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymRepositoryProvider).cancelSubscription(request.id));
    if (ok) refreshGym(ref, request.venueId);
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmPaymentSheet(request: request, start: renewalStart(all, request.memberId, BhutanTime.today())),
    );
    if (done ?? false) refreshGym(ref, request.venueId);
  }
}

class _ConfirmPaymentSheet extends ConsumerStatefulWidget {
  final GymSubscription request;
  final DateTime start;

  const _ConfirmPaymentSheet({required this.request, required this.start});

  @override
  ConsumerState<_ConfirmPaymentSheet> createState() => _ConfirmPaymentSheetState();
}

class _ConfirmPaymentSheetState extends ConsumerState<_ConfirmPaymentSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: '${widget.request.price}');
  final _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.mbob;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).activateSubscription(
            widget.request.id,
            amount: int.parse(_amount.text.trim()),
            method: _method,
            reference: _reference.text,
          ),
      success: "${widget.request.memberDisplayName}'s membership is active",
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final end = widget.start.add(Duration(days: r.durationDays - 1));
    final today = BhutanTime.today();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Confirm payment', style: context.text.titleLarge),
            const SizedBox(height: 4),
            Text('${r.memberDisplayName} · ${r.planName}', style: TextStyle(color: context.brand.muted)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Amount received', prefixText: 'Nu. '),
              validator: (v) => Validators.wholeNumber(v, max: 1000000),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _reference,
              decoration: InputDecoration(
                labelText: _method == PaymentMethod.mbob ? 'mBoB journal number' : 'Reference (optional)',
              ),
              validator: (v) => _method == PaymentMethod.mbob && (v ?? '').trim().isEmpty
                  ? 'Enter the journal number from the mBoB message'
                  : null,
            ),
            const SizedBox(height: 14),
            InfoRow(
              icon: Icons.event_available_rounded,
              text: widget.start == today
                  ? 'Starts today, ends ${formatDate(end)}'
                  : 'Starts ${formatDate(widget.start)} (after their current membership), ends ${formatDate(end)}',
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('Activate membership')),
          ],
        ),
      ),
    );
  }
}

enum _MemberFilter { active, ending, expired, all }

/// Everyone with a membership here, found by name or code.
class MembersScreen extends ConsumerStatefulWidget {
  final String venueId;

  const MembersScreen({super.key, required this.venueId});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  _MemberFilter _filter = _MemberFilter.active;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return GymStaffPage(
      venueId: widget.venueId,
      title: 'Members',
      builder: (context, access) => AppPage(
        title: 'Members',
        body: AsyncValueView<List<GymSubscription>>(
          value: ref.watch(gymSubscriptionsProvider(widget.venueId)),
          onRetry: () => ref.invalidate(gymSubscriptionsProvider(widget.venueId)),
          data: (all) {
            final members = _members(all);
            return ListView(
              padding: pagePadding(context),
              children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name or member code'),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final f in _MemberFilter.values)
                      ChoiceChip(
                        label: Text(switch (f) {
                          _MemberFilter.active => 'Active',
                          _MemberFilter.ending => 'Ending in 7 days',
                          _MemberFilter.expired => 'Ended',
                          _MemberFilter.all => 'All',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (members.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nobody here.'))),
                for (final m in members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => _showMember(context, m, all),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.memberDisplayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                Text(
                                  [m.planName, if (m.endDate != null) 'until ${formatDate(m.endDate!)}'].join(' · '),
                                  style: TextStyle(color: context.brand.muted),
                                ),
                              ],
                            ),
                          ),
                          SubscriptionStatusChip(subscription: m),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// One row per member: the membership that matters most now (current,
  /// then upcoming, then the latest).
  List<GymSubscription> _members(List<GymSubscription> all) {
    final today = BhutanTime.today();
    int rank(GymSubscription s) => s.isCurrentOn(today) ? 0 : s.isUpcomingOn(today) ? 1 : s.isPending ? 3 : 2;
    final byMember = <String, GymSubscription>{};
    for (final s in all) {
      final best = byMember[s.memberId];
      if (best == null || rank(s) < rank(best) || (rank(s) == rank(best) && s.requestedAt.isAfter(best.requestedAt))) {
        byMember[s.memberId] = s;
      }
    }
    final rows = byMember.values.where((s) {
      final matches = _search.isEmpty ||
          s.memberDisplayName.toLowerCase().contains(_search) ||
          (s.memberCode?.toLowerCase().contains(_search) ?? false);
      if (!matches) return false;
      return switch (_filter) {
        _MemberFilter.active => s.isCurrentOn(today) || s.isUpcomingOn(today),
        _MemberFilter.ending => s.isCurrentOn(today) && s.daysLeftOn(today) <= 7,
        _MemberFilter.expired => s.status == SubscriptionStatus.expired,
        _MemberFilter.all => true,
      };
    }).toList();
    rows.sort((a, b) => a.memberDisplayName.toLowerCase().compareTo(b.memberDisplayName.toLowerCase()));
    return rows;
  }

  void _showMember(BuildContext context, GymSubscription m, List<GymSubscription> all) {
    final history = all.where((s) => s.memberId == m.memberId).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(m.memberDisplayName, style: context.text.titleLarge),
            if (m.memberCode != null) Text('Member code ${m.memberCode}', style: TextStyle(color: context.brand.muted)),
            if (m.memberPhone != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => callPhone(context, m.memberPhone!),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(m.memberPhone!),
                ),
              ),
            ],
            const SectionTitle('Memberships here'),
            for (final s in history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${s.planName} · ${s.price == 0 ? 'Free' : formatNu(s.price)}'),
                subtitle: Text(s.startDate == null
                    ? 'Asked ${formatMoment(s.requestedAt)}'
                    : '${formatDate(s.startDate!)} to ${formatDate(s.endDate!)}'),
                trailing: SubscriptionStatusChip(subscription: s),
              ),
          ],
        ),
      ),
    );
  }
}

/// The gym's plans and prices; owners and managers add and change them.
class PlansScreen extends ConsumerWidget {
  final String venueId;

  const PlansScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (venueId: venueId, all: true);
    return GymStaffPage(
      venueId: venueId,
      title: 'Plans and prices',
      managersOnly: true,
      builder: (context, access) => AppPage(
        title: 'Plans and prices',
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context, ref, null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add plan'),
        ),
        body: AsyncValueView<List<GymPlan>>(
          value: ref.watch(gymPlansProvider(query)),
          onRetry: () => ref.invalidate(gymPlansProvider(query)),
          data: (plans) => plans.isEmpty
              ? EmptyState(
                  icon: Icons.sell_outlined,
                  title: 'No plans yet',
                  message: 'Add what members can buy: a day pass, monthly, yearly...',
                  actionLabel: 'Add a plan',
                  onAction: () => _edit(context, ref, null),
                )
              : ListView(
                  padding: pagePadding(context, bottom: 96),
                  children: [
                    for (final p in plans)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Opacity(
                          opacity: p.isActive ? 1 : 0.55,
                          child: PlanCard(
                            plan: p,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(p.isActive ? 'On sale' : 'Hidden', style: TextStyle(color: context.brand.muted)),
                                IconButton(
                                  tooltip: 'Edit ${p.name}',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(context, ref, p),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, GymPlan? plan) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlanSheet(venueId: venueId, plan: plan),
    );
    if (saved ?? false) {
      ref.invalidate(gymPlansProvider((venueId: venueId, all: true)));
      ref.invalidate(gymPlansProvider((venueId: venueId, all: false)));
    }
  }
}

class _PlanSheet extends ConsumerStatefulWidget {
  final String venueId;
  final GymPlan? plan;

  const _PlanSheet({required this.venueId, this.plan});

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  static const presets = {'Day pass': 1, '1 week': 7, '1 month': 30, '3 months': 90, '6 months': 180, '1 year': 365};

  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final _description = TextEditingController(text: widget.plan?.description ?? '');
  late final _days = TextEditingController(text: '${widget.plan?.durationDays ?? 30}');
  late final _price = TextEditingController(text: widget.plan == null ? '' : '${widget.plan!.price}');
  late bool _active = widget.plan?.isActive ?? true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _days, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).savePlan(
            venueId: widget.venueId,
            planId: widget.plan?.id,
            name: _name.text,
            description: _description.text,
            durationDays: int.parse(_days.text.trim()),
            price: int.parse(_price.text.trim()),
            isActive: _active,
          ),
      success: 'Plan saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.plan == null ? 'New plan' : 'Edit plan', style: context.text.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name *', hintText: 'Monthly, Student monthly, Day pass...'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in presets.entries)
                    ChoiceChip(
                      label: Text(e.key),
                      selected: _days.text.trim() == '${e.value}',
                      onSelected: (_) => setState(() => _days.text = '${e.value}'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _days,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Days *'),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => Validators.wholeNumber(v, min: 1, max: 1095, what: 'Days'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Price *', prefixText: 'Nu. '),
                      validator: (v) => Validators.wholeNumber(v, max: 1000000, what: 'Price'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _description,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(labelText: "What's included (optional)"),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('On sale'),
                subtitle: const Text('Hidden plans stay on existing memberships'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Save plan')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Money received, month by month (owners and managers).
class IncomeScreen extends ConsumerStatefulWidget {
  final String venueId;

  const IncomeScreen({super.key, required this.venueId});

  @override
  ConsumerState<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends ConsumerState<IncomeScreen> {
  late DateTime _month = DateTime(BhutanTime.today().year, BhutanTime.today().month);

  @override
  Widget build(BuildContext context) {
    final next = DateTime(_month.year, _month.month + 1);
    final query = (
      venueId: widget.venueId,
      moduleKey: gymModuleKey,
      from: bhutanMidnightUtc(_month),
      to: bhutanMidnightUtc(next),
    );
    final thisMonth = DateTime(BhutanTime.today().year, BhutanTime.today().month);
    return GymStaffPage(
      venueId: widget.venueId,
      title: 'Income',
      managersOnly: true,
      builder: (context, access) => AppPage(
        title: 'Income',
        body: ListView(
          padding: pagePadding(context),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                ),
                Expanded(child: Text(formatMonth(_month), textAlign: TextAlign.center, style: context.text.titleMedium)),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _month == thisMonth ? null : () => setState(() => _month = next),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AsyncValueView<List<Payment>>(
              value: ref.watch(venuePaymentsProvider(query)),
              onRetry: () => ref.invalidate(venuePaymentsProvider(query)),
              data: (payments) {
                final summary = IncomeSummary.of(payments);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Received', style: TextStyle(color: context.brand.muted)),
                          Text(formatNu(summary.total), style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                          Text('${summary.count} payment${summary.count == 1 ? '' : 's'}'),
                          if (summary.byMethod.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final e in summary.byMethod.entries)
                                  StatusChip(label: '${e.key.label} ${formatNu(e.value)}', color: context.colors.tertiary),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SectionTitle('Payments'),
                    if (payments.isEmpty) const Text('No payments this month.'),
                    if (payments.isNotEmpty)
                      Card(
                        child: Column(
                          children: [
                            for (final p in payments)
                              ListTile(
                                title: Text(p.payerName ?? 'Member'),
                                subtitle: Text([
                                  p.method.label,
                                  if (p.reference != null) p.reference!,
                                  formatMoment(p.createdAt),
                                ].join(' · ')),
                                trailing: Text(formatNu(p.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
