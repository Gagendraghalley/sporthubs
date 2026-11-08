import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/registered_member.dart';

/// Selling a package at the desk: which of the gym's packages, for how many
/// months, when it ends (worked out), what they paid and how. Inside a
/// [Form]: its fields check themselves when the form is validated.
class PackageFields extends ConsumerStatefulWidget {
  final String venueId;

  /// The day the package starts: the date of joining, or the day after the
  /// current package ends.
  final DateTime start;

  /// The sale, or null while no package is chosen.
  final ValueChanged<PackageSale?> onChanged;

  const PackageFields({super.key, required this.venueId, required this.start, required this.onChanged});

  @override
  ConsumerState<PackageFields> createState() => _PackageFieldsState();
}

class _PackageFieldsState extends ConsumerState<PackageFields> {
  GymPlan? _plan;
  int _months = 1;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  /// Until staff type their own amount, it follows the package and months.
  bool _amountTouched = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _emit() {
    final plan = _plan;
    widget.onChanged(plan == null
        ? null
        : PackageSale(
            plan: plan,
            months: _months,
            amount: int.tryParse(_amount.text.trim()) ?? 0,
            method: _method,
            reference: _reference.text,
          ));
  }

  void _choose(GymPlan? plan, {int? months}) {
    setState(() {
      _plan = plan;
      _months = months ?? (plan == null ? 1 : defaultMonths(plan));
      if (plan != null && !_amountTouched) _amount.text = '${packagePrice(plan, _months)}';
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(gymPlansProvider((venueId: widget.venueId, all: false)));
    final list = plans.valueOrNull ?? const <GymPlan>[];
    final plan = _plan;
    final end = packageEnd(widget.start, _months);
    final today = BhutanTime.today();
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plans.hasValue && list.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: FormHint('This gym has no packages on sale yet. Add them under Plans & prices.'),
          ),
        DropdownButtonFormField<String>(
          initialValue: plan?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Package *'),
          items: [
            for (final p in list)
              DropdownMenuItem(
                value: p.id,
                child: Text('${p.name} · ${p.price == 0 ? 'Free' : formatNu(p.price)} / ${formatDuration(p.durationDays)}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) => _choose(list.where((p) => p.id == id).firstOrNull),
          validator: (id) => id == null ? 'Choose the package' : null,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('months-${plan?.id}'),
                initialValue: _months,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Signed for *'),
                items: [
                  for (final m in packageMonthOptions) DropdownMenuItem(value: m, child: Text(m == 1 ? '1 month' : '$m months')),
                ],
                onChanged: plan == null ? null : (m) => _choose(plan, months: m),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Expiry date', helperText: 'Worked out for you'),
                child: Text(
                  plan == null ? '—' : formatDate(end),
                  style: TextStyle(fontWeight: FontWeight.w700, color: plan != null && end.isBefore(today) ? context.brand.danger : null),
                ),
              ),
            ),
          ],
        ),
        if (plan != null && end.isBefore(today))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: FormHint('This package has already ended: they will show as an old member until they renew.'),
          ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Amount received',
            prefixText: 'Nu. ',
            helperText: plan == null ? null : 'Suggested from the package price: ${formatNu(packagePrice(plan, _months))}',
          ),
          onChanged: (_) {
            _amountTouched = true;
            setState(() {});
            _emit();
          },
          validator: (v) => plan == null ? null : Validators.wholeNumber(v, max: 1000000),
        ),
        if (amount > 0) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in PaymentMethod.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: _method == m,
                  onSelected: (_) {
                    setState(() => _method = m);
                    _emit();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _reference,
            decoration: InputDecoration(
              labelText: _method == PaymentMethod.mbob ? 'mBoB journal number' : 'Reference (optional)',
            ),
            onChanged: (_) => _emit(),
            validator: (v) => _method == PaymentMethod.mbob && (v ?? '').trim().isEmpty
                ? 'Enter the journal number from the mBoB message'
                : null,
          ),
        ],
      ],
    );
  }
}

/// A date in a form: tap to pick it from a calendar.
class DateField extends FormField<DateTime> {
  DateField({
    super.key,
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    required DateTime firstDate,
    required DateTime lastDate,
    bool required = false,
    bool clearable = false,
  }) : super(
          initialValue: value,
          validator: required ? (v) => v == null ? 'Choose the date' : null : null,
          builder: (state) {
            final context = state.context;
            Future<void> pick() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: state.value ?? (lastDate.isBefore(DateTime.now()) ? lastDate : DateTime.now()),
                firstDate: firstDate,
                lastDate: lastDate,
              );
              if (picked == null) return;
              final day = DateTime(picked.year, picked.month, picked.day);
              state.didChange(day);
              onChanged(day);
            }

            return InkWell(
              onTap: pick,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: required ? '$label *' : label,
                  errorText: state.errorText,
                  suffixIcon: clearable && state.value != null
                      ? IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            state.didChange(null);
                            onChanged(null);
                          },
                        )
                      : const Icon(Icons.calendar_month_outlined),
                ),
                child: Text(state.value == null ? 'Choose' : formatDate(state.value!),
                    style: state.value == null ? TextStyle(color: context.brand.muted) : null),
              ),
            );
          },
        );
}
