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
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 120),
                      child: _PackagesTable(
                        plans: shown.toList(),
                        stats: stats,
                        activeTotal: activeTotal,
                        bestId: best?.id,
                        onEdit: _edit,
                        onToggle: _toggle,
                      ),
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

/// The packages as a table: what it is, its price, members on it now, times
/// sold, what it brought in, its share of today's members, and whether it's
/// on sale; a row opens it to edit, and its menu hides it or puts it back on
/// sale. On a phone the package's cell carries what the hidden columns say.
class _PackagesTable extends StatelessWidget {
  final List<GymPlan> plans;
  final Map<String, PlanStats> stats;
  final int activeTotal;
  final String? bestId;
  final ValueChanged<GymPlan> onEdit;
  final ValueChanged<GymPlan> onToggle;

  const _PackagesTable({
    required this.plans,
    required this.stats,
    required this.activeTotal,
    required this.bestId,
    required this.onEdit,
    required this.onToggle,
  });

  double _share(GymPlan p) => activeTotal == 0 ? 0 : stats[p.id]!.activeMembers / activeTotal;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // '2 now': the number bold, the word quiet.
    Widget count(int n, String word) => Text.rich(
          TextSpan(children: [
            TextSpan(text: '$n', style: TextStyle(fontWeight: FontWeight.w800, color: brand.ink)),
            TextSpan(text: ' $word', style: TextStyle(color: brand.muted)),
          ]),
          maxLines: 1,
        );
    String price(GymPlan p) => p.price == 0 ? 'Free' : formatNu(p.price);
    Widget badges(GymPlan p, {required bool withStatus}) => Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (bestId == p.id) StatusChip(label: 'Best seller', color: brand.accent, icon: Icons.workspace_premium_rounded),
            if (!p.isActive)
              StatusChip(label: 'Hidden', color: brand.muted, icon: Icons.visibility_off_outlined)
            else if (withStatus)
              StatusChip(label: 'On sale', color: brand.success),
          ],
        );
    return DataGrid<GymPlan>(
      rows: plans,
      noun: 'packages',
      rowLabel: (p) => 'Edit ${p.name}',
      dimmed: (p) => !p.isActive,
      onRowTap: onEdit,
      columns: [
        GridColumn(
          key: 'package',
          label: 'Package',
          flex: 4,
          sortBy: (p) => p.name.toLowerCase(),
          cell: (context, p) {
            final s = stats[p.id]!;
            final carry = [
              if (!DataGrid.shows(context, 'price')) '${price(p)} / ${formatDuration(p.durationDays)}',
              if (!DataGrid.shows(context, 'members')) '${s.activeMembers} now · ${s.sold} sold',
            ];
            final description = p.description?.trim() ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                if (description.isNotEmpty)
                  Text(description,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
                if (carry.isNotEmpty)
                  Text(carry.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: brand.body, fontSize: 13, fontWeight: FontWeight.w600)),
                if (!DataGrid.shows(context, 'status') && (bestId == p.id || !p.isActive))
                  Padding(padding: const EdgeInsets.only(top: 4), child: badges(p, withStatus: false)),
              ],
            );
          },
        ),
        GridColumn(
          key: 'price',
          label: 'Price',
          flex: 3,
          showFrom: 640,
          sortBy: (p) => p.price,
          cell: (context, p) => Text.rich(
            TextSpan(children: [
              TextSpan(
                text: price(p),
                style: TextStyle(fontWeight: FontWeight.w800, color: p.isActive ? brand.ink : brand.muted),
              ),
              TextSpan(text: ' / ${formatDuration(p.durationDays)}', style: TextStyle(color: brand.muted, fontSize: 13)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        GridColumn(
          key: 'members',
          label: 'Members',
          flex: 2,
          showFrom: 760,
          sortBy: (p) => stats[p.id]!.activeMembers,
          cell: (context, p) => count(stats[p.id]!.activeMembers, 'now'),
        ),
        GridColumn(
          key: 'sold',
          label: 'Sold',
          flex: 2,
          showFrom: 900,
          sortBy: (p) => stats[p.id]!.sold,
          cell: (context, p) => count(stats[p.id]!.sold, 'sold'),
        ),
        GridColumn(
          key: 'sales',
          label: 'Sales',
          flex: 2,
          showFrom: 1040,
          sortBy: (p) => stats[p.id]!.revenue,
          cell: (context, p) =>
              Text(formatNu(stats[p.id]!.revenue), style: TextStyle(fontWeight: FontWeight.w700, color: brand.body)),
        ),
        GridColumn(
          key: 'share',
          label: 'Share today',
          flex: 3,
          showFrom: 1180,
          sortBy: _share,
          cell: (context, p) {
            final share = _share(p);
            final color = p.isActive ? brand.accent : brand.muted;
            return Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: share),
                      duration: Motion.of(context, Motion.card),
                      curve: Motion.ease,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 38,
                  child: Text('${(share * 100).round()}%',
                      textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w700, color: brand.body)),
                ),
              ],
            );
          },
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 156,
          showFrom: 520,
          sortBy: (p) => '${p.isActive ? 0 : 1}${bestId == p.id ? 0 : 1}',
          cell: (context, p) => badges(p, withStatus: true),
        ),
        GridColumn(
          key: 'more',
          label: '',
          width: 52,
          alignEnd: true,
          cell: (context, p) => PopupMenuButton<String>(
            tooltip: 'More for ${p.name}',
            onSelected: (v) => v == 'edit' ? onEdit(p) : onToggle(p),
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
                  leading: Icon(p.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  title: Text(p.isActive ? 'Hide (stop selling)' : 'Put on sale'),
                ),
              ),
            ],
          ),
        ),
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
                    _PaymentsTable(payments: shown),
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

/// The month's payments as a table: who paid, how, the journal number,
/// when, and how much (the column to sort by size). On a phone the payer's
/// cell carries how and when.
class _PaymentsTable extends StatelessWidget {
  final List<Payment> payments;

  const _PaymentsTable({required this.payments});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    String name(Payment p) => (p.payerName ?? '').trim();
    return DataGrid<Payment>(
      rows: payments,
      noun: 'payments',
      columns: [
        GridColumn(
          key: 'payer',
          label: 'Paid by',
          flex: 4,
          sortBy: (p) => name(p).toLowerCase(),
          cell: (context, p) {
            final color = methodColor(p.method);
            final n = name(p);
            final carry = [
              if (!DataGrid.shows(context, 'method')) p.method.label,
              if (!DataGrid.shows(context, 'reference') && p.reference != null) p.reference!,
              if (!DataGrid.shows(context, 'when')) formatMoment(p.createdAt),
            ];
            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Text(n.isEmpty ? '?' : n[0].toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(n.isEmpty ? 'Member' : n,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                      if (carry.isNotEmpty)
                        Text(carry.join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        GridColumn(
          key: 'method',
          label: 'Method',
          flex: 2,
          showFrom: 600,
          sortBy: (p) => p.method.label,
          cell: (context, p) => StatusChip(label: p.method.label, color: methodColor(p.method)),
        ),
        GridColumn(
          key: 'reference',
          label: 'Journal no.',
          flex: 3,
          showFrom: 960,
          sortBy: (p) => p.reference ?? '',
          cell: (context, p) => Text(
            p.reference ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.reference == null ? brand.muted : brand.body,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        GridColumn(
          key: 'when',
          label: 'When',
          flex: 3,
          showFrom: 760,
          sortBy: (p) => p.createdAt,
          cell: (context, p) => Text(formatMoment(p.createdAt), style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'amount',
          label: 'Amount',
          width: 132,
          alignEnd: true,
          sortBy: (p) => p.amount,
          cell: (context, p) => Text(formatNu(p.amount),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: brand.ink, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ],
    );
  }
}
