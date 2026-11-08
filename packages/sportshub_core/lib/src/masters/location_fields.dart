import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location.dart';
import 'master_repository.dart';

/// Dzongkhag, then gewog (or thromde), then village, from the master data:
/// each list opens once the one above is chosen, and changing one clears
/// those under it.
class LocationFields extends ConsumerWidget {
  final LocationSelection value;
  final ValueChanged<LocationSelection> onChanged;

  /// All three must be chosen (else only what is chosen is kept).
  final bool required;
  final double gap;

  /// Side by side when there's room (700 wide and up), else one under
  /// another.
  final bool inRow;

  const LocationFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.gap = 14,
    this.inRow = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dzongkhags = ref.watch(dzongkhagsProvider);
    final gewogs = value.dzongkhagId == null ? null : ref.watch(gewogsProvider(value.dzongkhagId!));
    final villages = value.gewogId == null ? null : ref.watch(villagesProvider(value.gewogId!));
    String label(String text) => required ? '$text *' : text;

    final fields = [
        _LocationDropdown(
          key: const ValueKey('location-dzongkhag'),
          label: label('Dzongkhag'),
          items: dzongkhags,
          value: value.dzongkhagId,
          onChanged: (id) => onChanged(value.withDzongkhag(id)),
          validator: required ? (id) => id == null ? 'Choose the dzongkhag' : null : null,
        ),
        _LocationDropdown(
          // A new list under a new dzongkhag.
          key: ValueKey('location-gewog-${value.dzongkhagId}'),
          label: label('Gewog or thromde'),
          items: gewogs,
          value: value.gewogId,
          hint: value.dzongkhagId == null ? 'Choose the dzongkhag first' : null,
          onChanged: (id) => onChanged(value.withGewog(id)),
          validator: required ? (id) => id == null ? 'Choose the gewog' : null : null,
        ),
        _LocationDropdown(
          key: ValueKey('location-village-${value.gewogId}'),
          label: label('Village'),
          items: villages,
          value: value.villageId,
          hint: value.gewogId == null ? 'Choose the gewog first' : null,
          onChanged: (id) => onChanged(value.withVillage(id)),
          validator: required ? (id) => id == null ? 'Choose the village' : null : null,
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) => inRow && c.maxWidth >= 700
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, f) in fields.indexed) ...[if (i > 0) SizedBox(width: gap), Expanded(child: f)],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, f) in fields.indexed) ...[if (i > 0) SizedBox(height: gap), f],
              ],
            ),
    );
  }
}

class _LocationDropdown extends StatelessWidget {
  final String label;

  /// Null until the level above is chosen.
  final AsyncValue<List<LocationItem>>? items;
  final int? value;
  final String? hint;
  final ValueChanged<int?> onChanged;
  final FormFieldValidator<int>? validator;

  const _LocationDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final list = items?.valueOrNull ?? const <LocationItem>[];
    final loading = items?.isLoading ?? false;
    final failed = items?.hasError ?? false;
    return DropdownButtonFormField<int>(
      initialValue: list.any((i) => i.id == value) ? value : null,
      isExpanded: true,
      menuMaxHeight: 420,
      decoration: InputDecoration(
        labelText: label,
        helperText: failed ? 'Could not load the list. Pull to refresh or try again.' : null,
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
      ),
      hint: hint == null ? null : Text(hint!),
      items: [
        for (final i in list) DropdownMenuItem(value: i.id, child: Text(i.name, overflow: TextOverflow.ellipsis))
      ],
      onChanged: items == null || list.isEmpty ? null : onChanged,
      validator: validator,
    );
  }
}
