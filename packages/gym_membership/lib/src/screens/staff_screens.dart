import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/registered_member.dart';
import '../gym_permissions.dart';
import '../widgets/gym_widgets.dart';

// ─── Memberships & packages ───────────────────────────────────────────────

enum _Show {
  all('All'),
  onSale('On sale'),
  hidden('Hidden');

  const _Show(this.label);
  final String label;
}

/// How a package is doing, from the gym's memberships.
class PlanStats {
  /// Members it covers today.
  final int activeMembers;

  /// Times it was sold (renewals included), and what they paid.
  final int sold;
  final int revenue;

  const PlanStats({required this.activeMembers, required this.sold, required this.revenue});

  static Map<String, PlanStats> of(Iterable<GymPlan> plans, Iterable<GymSubscription> subs, DateTime today) => {
        for (final p in plans)
          p.id: () {
            final mine = subs.where((s) =>
                s.planId == p.id && (s.status == SubscriptionStatus.active || s.status == SubscriptionStatus.expired));
            return PlanStats(
              activeMembers: mine.where((s) => s.isCurrentOn(today)).map((s) => s.memberId).toSet().length,
              sold: mine.length,
              revenue: mine.fold(0, (sum, s) => sum + s.price),
            );
          }(),
      };
}

/// The gym's packages and prices: what the front desk sells, how each one is
/// doing (members on it now, times sold, its share), and putting them on
/// sale or hiding them. Whoever may manage packages adds and changes them.
class PlansScreen extends ConsumerStatefulWidget {
  final String venueId;

  /// Open with the form for a new package (the New package shortcut).
  final bool openNew;

  const PlansScreen({super.key, required this.venueId, this.openNew = false});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  _Show _show = _Show.all;

  @override
  void initState() {
    super.initState();
    if (widget.openNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _edit(null);
      });
    }
  }

  String get _id => widget.venueId;

  @override
  Widget build(BuildContext context) {
    final query = (venueId: _id, all: true);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return GymStaffPage(
      venueId: _id,
      title: 'Memberships & packages',
      permission: GymPermission.plans,
      builder: (context, access) => AppPage(
        title: 'Memberships & packages',
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: OutlinedButton.icon(
                onPressed: () => _edit(null),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add package'),
              ),
            ),
        ],
        floatingActionButton: wide
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add package'),
              ),
        body: AsyncValueView<List<GymPlan>>(
          value: ref.watch(gymPlansProvider(query)),
          onRetry: () => ref.invalidate(gymPlansProvider(query)),
          data: (plans) {
            if (plans.isEmpty) {
              return EmptyState(
                icon: Icons.sell_outlined,
                title: 'Create your first membership package',
                message: 'Add what the front desk sells: Gym, Gym + Aerobics, Personal training... '
                    'Each has a price for its length; the desk sells it for as many months as the member wants.',
                actionLabel: 'Add a package',
                onAction: () => _edit(null),
              );
            }
            final today = BhutanTime.today();
            final subs = ref.watch(gymSubscriptionsProvider(_id)).valueOrNull ?? const <GymSubscription>[];
            final stats = PlanStats.of(plans, subs, today);
            final onSale = plans.where((p) => p.isActive).toList();
            final activeTotal = stats.values.fold(0, (sum, s) => sum + s.activeMembers);
            final best = plans.where((p) => stats[p.id]!.sold > 0).fold<GymPlan?>(
                null, (b, p) => b == null || stats[p.id]!.sold > stats[b.id]!.sold ? p : b);
            final shown = plans.where((p) => switch (_show) {
                  _Show.all => true,
                  _Show.onSale => p.isActive,
                  _Show.hidden => !p.isActive,
                });
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(gymPlansProvider(query));
                ref.invalidate(gymSubscriptionsProvider(_id));
              },
              child: ListView(
                padding: pagePadding(context, bottom: 96),
                children: [
                  LayoutBuilder(
                    builder: (context, c) => ConsoleCells(
                      columns: c.maxWidth >= 900 ? 4 : 2,
                      children: staggered([
                        ConsoleKpi(
                          icon: Icons.sell_rounded,
                          color: BrandColors.orange,
                          value: '${onSale.length}',
                          count: onSale.length,
                          label: 'On sale',
                          note: plans.length == onSale.length ? 'Every package' : '${plans.length - onSale.length} hidden',
                        ),
                        ConsoleKpi(
                          icon: Icons.groups_rounded,
                          color: BrandColors.blue,
                          value: '$activeTotal',
                          count: activeTotal,
                          label: 'Members on a package',
                          note: 'Covered today',
                        ),
                        ConsoleKpi(
                          icon: Icons.workspace_premium_rounded,
                          color: BrandColors.amber,
                          value: best?.name ?? '—',
                          label: 'Best seller',
                          note: best == null ? 'Nothing sold yet' : '${stats[best.id]!.sold} sold',
                        ),
                        ConsoleKpi(
                          icon: Icons.payments_rounded,
                          color: BrandColors.green,
                          value: formatNu(stats.values.fold(0, (sum, s) => sum + s.revenue)),
                          count: stats.values.fold<int>(0, (sum, s) => sum + s.revenue),
                          format: (v) => formatNu(v.round()),
                          label: 'Package sales',
                          note: 'Everything sold, at the price paid',
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<_Show>(
                      showSelectedIcon: false,
                      segments: [
                        for (final s in _Show.values)
                          ButtonSegment(
                            value: s,
                            label: Text('${s.label} ${switch (s) {
                              _Show.all => plans.length,
                              _Show.onSale => onSale.length,
                              _Show.hidden => plans.length - onSale.length,
                            }}'),
                          ),
                      ],
                      selected: {_show},
                      onSelectionChanged: (v) => setState(() => _show = v.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (shown.isEmpty)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No packages here.')))
                  else
                    ResponsiveGrid(
                      minItemWidth: 320,
                      maxColumns: 3,
                      spacing: 16,
                      runSpacing: 16,
                      children: staggered([
                        for (final p in shown)
                          _PackageCard(
                            plan: p,
                            stats: stats[p.id]!,
                            share: activeTotal == 0 ? 0 : stats[p.id]!.activeMembers / activeTotal,
                            best: best?.id == p.id,
                            onEdit: () => _edit(p),
                            onToggle: () => _toggle(p),
                          ),
                      ]),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _refresh() {
    ref.invalidate(gymPlansProvider((venueId: _id, all: true)));
    ref.invalidate(gymPlansProvider((venueId: _id, all: false)));
  }

  Future<void> _edit(GymPlan? plan) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlanSheet(venueId: _id, plan: plan),
    );
    if (saved ?? false) _refresh();
  }

  Future<void> _toggle(GymPlan p) async {
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).savePlan(
            venueId: _id,
            planId: p.id,
            name: p.name,
            description: p.description,
            durationDays: p.durationDays,
            price: p.price,
            isActive: !p.isActive,
          ),
      success: p.isActive ? '${p.name} is hidden: the desk no longer sells it' : '${p.name} is on sale',
    );
    if (ok) _refresh();
  }
}

class _PackageCard extends StatelessWidget {
  final GymPlan plan;
  final PlanStats stats;

  /// Its part of the members on a package today, 0 to 1.
  final double share;
  final bool best;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  const _PackageCard({
    required this.plan,
    required this.stats,
    required this.share,
    required this.best,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final ink = ConsoleInk.of(context);
    final color = plan.isActive ? BrandColors.orange : brand.muted;
    return HoverLift(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: plan.isActive ? 1 : 0.7,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ink.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: best ? BrandColors.orange.withValues(alpha: 0.5) : brand.glassBorder),
            boxShadow: ink.shadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(plan.name, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (best) StatusChip(label: 'Best seller', color: BrandColors.orange, icon: Icons.workspace_premium_rounded),
                  if (!plan.isActive) StatusChip(label: 'Hidden', color: brand.muted, icon: Icons.visibility_off_outlined),
                  PopupMenuButton<String>(
                    tooltip: 'More for ${plan.name}',
                    onSelected: (v) => v == 'edit' ? onEdit() : onToggle(),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_outlined), title: Text('Edit')),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(plan.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          title: Text(plan.isActive ? 'Hide (stop selling)' : 'Put on sale'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: plan.price == 0 ? 'Free' : formatNu(plan.price),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5),
                  ),
                  TextSpan(text: '  / ${formatDuration(plan.durationDays)}', style: TextStyle(color: brand.muted, fontSize: 14)),
                ]),
              ),
              if (plan.description != null && plan.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(plan.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, height: 1.4)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _Fact(icon: Icons.people_alt_outlined, text: '${stats.activeMembers} now'),
                  const SizedBox(width: 16),
                  _Fact(icon: Icons.receipt_long_outlined, text: '${stats.sold} sold'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatNu(stats.revenue),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, color: ink.body),
                    ),
                  ),
                ],
              ),
              ConsoleShareRow(
                color: color,
                label: 'Share of members today',
                value: '${(share * 100).round()}%',
                share: share,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: onToggle,
                      style: TextButton.styleFrom(minimumSize: const Size(0, 42)),
                      child: Text(plan.isActive ? 'Hide' : 'Put on sale'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Fact({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: context.brand.muted),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
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
      success: 'Package saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  /// What the desk will charge, as they type: 'Nu. 1,500 for 1 month · 3
  /// months Nu. 4,500'.
  String? _preview() {
    final days = int.tryParse(_days.text.trim());
    final price = int.tryParse(_price.text.trim());
    if (days == null || days < 1 || price == null) return null;
    final plan = GymPlan(id: '', venueId: '', name: '', durationDays: days, price: price, isActive: true);
    final m = planMonths(plan);
    final three = m <= 3 ? '  ·  3 months ${formatNu(packagePrice(plan, 3))}' : '';
    return '${price == 0 ? 'Free' : formatNu(price)} for ${formatDuration(days)}$three';
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.plan == null ? 'New package' : 'Edit package', style: context.text.titleLarge),
              const SizedBox(height: 4),
              Text('What the front desk sells. They choose how many months when they sell it.',
                  style: TextStyle(color: context.brand.muted)),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name *', hintText: 'Gym, Gym + Aerobics, Personal training...'),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _days,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Days *', helperText: '30 = a month'),
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
                      onChanged: (_) => setState(() {}),
                      validator: (v) => Validators.wholeNumber(v, max: 1000000, what: 'Price'),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: preview == null
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: BrandColors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.sell_outlined, color: BrandColors.orange, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(preview, style: const TextStyle(fontWeight: FontWeight.w700))),
                          ],
                        ),
                      ),
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
                subtitle: const Text('Hidden packages stay on existing memberships'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Save package')),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Payments & income ─────────────────────────────────────────────────────

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

Color methodColor(PaymentMethod m) => switch (m.value) {
      'cash' => BrandColors.green,
      'mbob' => BrandColors.blue,
      'bank' => BrandColors.navy,
      _ => BrandColors.amber,
    };

/// Money received (owners and managers): the last twelve months as bars
/// (tap one to open it), the month's total against the one before, how
/// members paid, and every payment, found by name or reference.
class IncomeScreen extends ConsumerStatefulWidget {
  final String venueId;

  const IncomeScreen({super.key, required this.venueId});

  @override
  ConsumerState<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends ConsumerState<IncomeScreen> {
  late DateTime _month = DateTime(BhutanTime.today().year, BhutanTime.today().month);
  String _search = '';
  PaymentMethod? _method;

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final thisMonth = DateTime(today.year, today.month);
    final months = [for (var i = 11; i >= 0; i--) DateTime(thisMonth.year, thisMonth.month - i)];
    final query = (
      venueId: widget.venueId,
      moduleKey: gymModuleKey,
      from: bhutanMidnightUtc(months.first),
      to: bhutanMidnightUtc(DateTime(thisMonth.year, thisMonth.month + 1)),
    );
    return GymStaffPage(
      venueId: widget.venueId,
      title: 'Payments & income',
      permission: VenuePermission.income,
      builder: (context, access) => AppPage(
        title: 'Payments & income',
        body: AsyncValueView<List<Payment>>(
          value: ref.watch(venuePaymentsProvider(query)),
          onRetry: () => ref.invalidate(venuePaymentsProvider(query)),
          data: (all) {
            final paid = all.where((p) => p.isCompleted).toList();
            DateTime monthOf(Payment p) {
              final d = BhutanTime.toBhutan(p.createdAt);
              return DateTime(d.year, d.month);
            }

            final totals = [for (final m in months) paid.where((p) => monthOf(p) == m).fold(0, (s, p) => s + p.amount)];
            final index = months.indexOf(_month).clamp(0, 11);
            final inMonth = paid.where((p) => monthOf(p) == _month).toList();
            final summary = IncomeSummary.of(inMonth);
            final before = index > 0 ? totals[index - 1] : null;
            final change = before == null || before == 0 ? null : (summary.total - before) / before;
            final yearToDate = [
              for (var i = 0; i < 12; i++)
                if (months[i].year == thisMonth.year) totals[i],
            ].fold(0, (s, v) => s + v);
            final shown = inMonth.where((p) {
              if (_method != null && p.method != _method) return false;
              if (_search.isEmpty) return true;
              final q = _search.toLowerCase();
              return (p.payerName ?? '').toLowerCase().contains(q) || (p.reference ?? '').toLowerCase().contains(q);
            }).toList();
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(venuePaymentsProvider(query)),
              child: ListView(
                padding: pagePadding(context, bottom: 40),
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Previous month',
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: index == 0 ? null : () => setState(() => _month = months[index - 1]),
                      ),
                      Expanded(child: Text(formatMonth(_month), textAlign: TextAlign.center, style: context.text.titleLarge)),
                      IconButton.filledTonal(
                        tooltip: 'Next month',
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: _month == thisMonth ? null : () => setState(() => _month = months[index + 1]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, c) => ConsoleCells(
                      columns: c.maxWidth >= 900 ? 4 : 2,
                      children: staggered([
                        ConsoleKpi(
                          icon: Icons.account_balance_wallet_rounded,
                          color: BrandColors.orange,
                          value: formatNu(summary.total),
                          count: summary.total,
                          format: (v) => formatNu(v.round()),
                          label: 'Received',
                          note: formatMonth(_month),
                          trailing: change == null ? null : _Change(change),
                        ),
                        ConsoleKpi(
                          icon: Icons.receipt_long_rounded,
                          color: BrandColors.blue,
                          value: '${summary.count}',
                          count: summary.count,
                          label: 'Payments',
                          note: summary.count == 0 ? 'None yet' : 'Average ${formatNu((summary.total / summary.count).round())}',
                        ),
                        ConsoleKpi(
                          icon: Icons.history_rounded,
                          color: BrandColors.green,
                          value: before == null ? '—' : formatNu(before),
                          count: before,
                          format: (v) => formatNu(v.round()),
                          label: 'Month before',
                          note: index > 0 ? formatMonth(months[index - 1]) : 'Not in range',
                        ),
                        ConsoleKpi(
                          icon: Icons.calendar_month_rounded,
                          color: const Color(0xFF7C4DFF),
                          value: formatNu(yearToDate),
                          count: yearToDate,
                          format: (v) => formatNu(v.round()),
                          label: 'This year so far',
                          note: '${thisMonth.year}',
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ResponsiveColumns(
                    breakpoint: 1000,
                    flex: (3, 2),
                    first: [
                      FadeSlideIn(
                        child: ConsoleCard(
                          icon: Icons.bar_chart_rounded,
                          title: 'Last 12 months',
                          trailing: Text('Tap a month', style: TextStyle(color: context.brand.muted, fontSize: 12.5)),
                          child: ConsoleBarChart(
                            name: 'Income by month',
                            height: 230,
                            points: [
                              for (var i = 0; i < 12; i++) (label: _monthNames[months[i].month - 1], value: totals[i]),
                            ],
                            format: (v) => compactNu(v),
                            highlight: index,
                            onTap: (i) => setState(() => _month = months[i]),
                          ),
                        ),
                      ),
                    ],
                    second: [
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 80),
                        child: ConsoleCard(
                          icon: Icons.pie_chart_outline_rounded,
                          title: 'How they paid',
                          child: summary.total == 0
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  child: Text('No payments in ${formatMonth(_month)}.', style: TextStyle(color: context.brand.muted)),
                                )
                              : Column(
                                  children: [
                                    for (final m in PaymentMethod.values)
                                      if ((summary.byMethod[m] ?? 0) > 0)
                                        ConsoleShareRow(
                                          color: methodColor(m),
                                          label: m.label,
                                          value: formatNu(summary.byMethod[m]!),
                                          share: summary.byMethod[m]! / summary.total,
                                        ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                  SectionTitle('Payments in ${formatMonth(_month)}',
                      trailing: Text('${shown.length} of ${inMonth.length}', style: TextStyle(color: context.brand.muted))),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 300,
                        child: TextField(
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Name or reference',
                          ),
                          onChanged: (v) => setState(() => _search = v.trim()),
                        ),
                      ),
                      ChoiceChip(label: const Text('All'), selected: _method == null, onSelected: (_) => setState(() => _method = null)),
                      for (final m in PaymentMethod.values)
                        if (summary.byMethod.containsKey(m))
                          ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (shown.isEmpty)
                    SectionCard(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(inMonth.isEmpty ? 'No payments this month.' : 'No payments match.',
                            style: TextStyle(color: context.brand.muted)),
                      ),
                    )
                  else
                    SectionCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [for (final p in shown) _PaymentRow(payment: p)]),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// '+12%' in green, '-8%' in red.
class _Change extends StatelessWidget {
  final double change;

  const _Change(this.change);

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    final color = up ? context.brand.success : context.brand.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 15, color: color),
          const SizedBox(width: 3),
          Text('${up ? '+' : ''}${(change * 100).round()}%',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Payment payment;

  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final color = methodColor(p.method);
    final name = (p.payerName ?? '').trim();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ),
      title: Text(name.isEmpty ? 'Member' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [p.method.label, if (p.reference != null) p.reference!, formatMoment(p.createdAt)].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(formatNu(p.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    );
  }
}
