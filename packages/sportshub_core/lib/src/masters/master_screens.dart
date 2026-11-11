import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../access/access.dart';
import '../access/permission_gate.dart';
import '../theme/brand.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import '../widgets/searchable_dropdown.dart';
import 'location.dart';
import 'master_repository.dart';

/// Admin -> Master data: dzongkhags, gewogs and thromdes, and villages.
/// Rows are turned off rather than deleted, so addresses keep pointing at
/// them.
class AdminMastersScreen extends ConsumerStatefulWidget {
  const AdminMastersScreen({super.key});

  @override
  ConsumerState<AdminMastersScreen> createState() => _AdminMastersScreenState();
}

class _AdminMastersScreenState extends ConsumerState<AdminMastersScreen> {
  LocationLevel _level = LocationLevel.dzongkhag;
  int? _dzongkhagId;
  int? _gewogId;
  String _search = '';
  bool _withInactive = false;
  final _searchField = TextEditingController();
  Timer? _debounce;

  MasterQuery get _query => (
        level: _level,
        dzongkhagId: _level == LocationLevel.dzongkhag ? null : _dzongkhagId,
        gewogId: _level == LocationLevel.village ? _gewogId : null,
        search: _search,
        withInactive: _withInactive,
      );

  @override
  void dispose() {
    _debounce?.cancel();
    _searchField.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _search = text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      title: 'Master data',
      permission: PlatformPermission.masters,
      builder: (context, _) {
        final list = ref.watch(masterListProvider(_query));
        return AppPage(
          title: 'Master data',
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add_rounded),
            label: Text('Add ${_level.label.toLowerCase()}'),
          ),
          body: RefreshIndicator(
            onRefresh: () async => ref.invalidate(masterListProvider(_query)),
            child: ListView(
              padding: pagePadding(context, bottom: 96),
              children: [
                _filterBar(),
                const SizedBox(height: 4),
                AsyncValueView<List<LocationItem>>(
                  value: list,
                  onRetry: () => ref.invalidate(masterListProvider(_query)),
                  data: (items) => items.isEmpty
                      ? EmptyState(
                          icon: Icons.travel_explore_rounded,
                          title: 'Nothing here',
                          message: _search.isEmpty ? null : 'No ${_level.plural.toLowerCase()} match "$_search".',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The table's foot counts them; here, only when
                            // there are more than came back.
                            if (items.length >= masterListLimit)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                child: FormHint(
                                  'Showing the first $masterListLimit. Search, or choose a '
                                  '${_level == LocationLevel.village ? 'gewog' : 'dzongkhag'}, to see the rest.',
                                ),
                              )
                            else
                              const SizedBox(height: 8),
                            _MasterTable(level: _level, items: items, onTap: _edit),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The level, the parents to narrow by, the search and the turned-off
  /// switch: in two rows on a wide screen, one under another on a phone.
  Widget _filterBar() {
    final levels = SegmentedButton<LocationLevel>(
      segments: [
        for (final l in LocationLevel.values)
          ButtonSegment(value: l, label: Text(l == LocationLevel.gewog ? 'Gewogs' : l.plural)),
      ],
      selected: {_level},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _level = s.first),
    );
    final dzongkhag = _level == LocationLevel.dzongkhag
        ? null
        : _ParentFilter(
            level: LocationLevel.dzongkhag,
            value: _dzongkhagId,
            onChanged: (id) => setState(() {
              _dzongkhagId = id;
              _gewogId = null;
            }),
          );
    final gewog = _level != LocationLevel.village
        ? null
        : _ParentFilter(
            key: ValueKey('gewog-filter-$_dzongkhagId'),
            level: LocationLevel.gewog,
            dzongkhagId: _dzongkhagId,
            value: _gewogId,
            onChanged: (id) => setState(() => _gewogId = id),
          );
    final search = TextField(
      controller: _searchField,
      onChanged: _onSearch,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search ${_level.plural.toLowerCase()}',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchField.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchField.clear();
                  _onSearch('');
                },
              ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              levels,
              const SizedBox(height: 14),
              if (dzongkhag != null) ...[dzongkhag, const SizedBox(height: 12)],
              if (gewog != null) ...[gewog, const SizedBox(height: 12)],
              search,
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Show turned-off ones'),
                value: _withInactive,
                onChanged: (v) => setState(() => _withInactive = v),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(width: 520, child: levels),
                const Spacer(),
                Text('Show turned-off ones', style: context.text.bodyMedium),
                const SizedBox(width: 10),
                Switch(value: _withInactive, onChanged: (v) => setState(() => _withInactive = v)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dzongkhag != null) ...[Expanded(child: dzongkhag), const SizedBox(width: 12)],
                if (gewog != null) ...[Expanded(child: gewog), const SizedBox(width: 12)],
                Expanded(flex: dzongkhag == null ? 1 : 2, child: search),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _edit(LocationItem? item) async {
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (_) => LocationEditDialog(
        level: item?.level ?? _level,
        item: item,
        dzongkhagId: _dzongkhagId,
        gewogId: _gewogId,
      ),
    );
    if (saved == true) {
      ref.invalidate(masterListProvider);
      ref.invalidate(dzongkhagsProvider);
      ref.invalidate(gewogsProvider);
      ref.invalidate(villagesProvider);
    }
  }
}

/// The rows as a table: name, where it is (its gewog and dzongkhag), its
/// code, whether it's in use; 25 to a page. Tap a row to change it. On a
/// phone the name's cell carries where it is and its code.
class _MasterTable extends StatelessWidget {
  final LocationLevel level;
  final List<LocationItem> items;
  final ValueChanged<LocationItem> onTap;

  const _MasterTable({required this.level, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    Widget plain(String? text, {bool code = false}) => Text(
          text ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: text == null || code ? brand.muted : brand.body,
            fontFeatures: code ? const [FontFeature.tabularFigures()] : null,
          ),
        );
    final village = level == LocationLevel.village;
    final gewog = level == LocationLevel.gewog;
    return DataGrid<LocationItem>(
      // A new level is a new table: its own order and first page.
      key: ValueKey(level),
      rows: items,
      noun: level.plural.toLowerCase(),
      pageSizes: const [25, 50, 100],
      rowLabel: (i) => 'Change ${i.name}',
      dimmed: (i) => !i.isActive,
      onRowTap: onTap,
      columns: [
        GridColumn(
          key: 'name',
          label: 'Name',
          flex: 4,
          sortBy: (i) => i.name.toLowerCase(),
          cell: (context, i) => _NameCell(item: i),
        ),
        if (gewog) ...[
          GridColumn(
            key: 'kind',
            label: 'Kind',
            flex: 2,
            showFrom: 700,
            sortBy: (i) => i.kind ?? GewogKind.gewog,
            cell: (context, i) => plain(GewogKind.label(i.kind ?? GewogKind.gewog)),
          ),
          GridColumn(
            key: 'place',
            label: 'Dzongkhag',
            flex: 3,
            showFrom: 700,
            sortBy: (i) => (i.parentName ?? '').toLowerCase(),
            cell: (context, i) => plain(i.parentName),
          ),
        ],
        if (village) ...[
          GridColumn(
            key: 'place',
            label: 'Gewog or thromde',
            flex: 3,
            showFrom: 700,
            sortBy: (i) => (i.parentName ?? '').toLowerCase(),
            cell: (context, i) => plain(i.parentName),
          ),
          GridColumn(
            key: 'dzongkhag',
            label: 'Dzongkhag',
            flex: 3,
            showFrom: 860,
            sortBy: (i) => (i.grandparentName ?? '').toLowerCase(),
            cell: (context, i) => plain(i.grandparentName),
          ),
          GridColumn(
            key: 'code',
            label: 'Code',
            flex: 2,
            showFrom: 700,
            sortBy: (i) => i.code ?? '',
            cell: (context, i) => plain(i.code, code: true),
          ),
        ],
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 108,
          showFrom: 480,
          sortBy: (i) => i.isActive ? 0 : 1,
          cell: (context, i) => i.isActive
              ? StatusChip(label: 'In use', color: brand.success)
              : StatusChip(label: 'Off', color: brand.muted),
        ),
        GridColumn(
          key: 'edit',
          label: '',
          width: 40,
          alignEnd: true,
          cell: (context, i) => Icon(Icons.edit_outlined, size: 18, color: brand.muted),
        ),
      ],
    );
  }
}

/// The name; with the other columns away (a phone), where it is, its code,
/// and 'Off'.
class _NameCell extends StatelessWidget {
  final LocationItem item;

  const _NameCell({required this.item});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final details = [
      if (!DataGrid.shows(context, 'kind') && item.kind == GewogKind.thromde) 'Thromde',
      if (!DataGrid.shows(context, 'place') && item.place != null) item.place!,
      if (!DataGrid.shows(context, 'code') && item.code != null) item.code!,
    ];
    final off = !item.isActive && !DataGrid.shows(context, 'status');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.name,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        if (details.isNotEmpty)
          Text(details.join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
        if (off)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: StatusChip(label: 'Off', color: brand.muted),
          ),
      ],
    );
  }
}

/// A dropdown narrowing the list to one dzongkhag or gewog ('All' for none).
class _ParentFilter extends ConsumerWidget {
  final LocationLevel level;
  final int? dzongkhagId;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _ParentFilter({super.key, required this.level, required this.value, required this.onChanged, this.dzongkhagId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsDzongkhag = level == LocationLevel.gewog && dzongkhagId == null;
    final items = needsDzongkhag
        ? const <LocationItem>[]
        : ref
                .watch(masterListProvider((
                  level: level,
                  dzongkhagId: dzongkhagId,
                  gewogId: null,
                  search: '',
                  withInactive: true,
                )))
                .valueOrNull ??
            const <LocationItem>[];
    return SearchableDropdown<int?>(
      value: items.any((i) => i.id == value) ? value : null,
      decoration: InputDecoration(labelText: level == LocationLevel.gewog ? 'Gewog' : 'Dzongkhag'),
      hint: needsDzongkhag ? 'Choose a dzongkhag to choose a gewog' : 'All',
      options: [
        const DropdownOption<int?>(null, 'All'),
        for (final i in items) DropdownOption<int?>(i.id, i.name),
      ],
      onChanged: needsDzongkhag ? null : onChanged,
    );
  }
}

/// Adds a row to the master data, or changes one ([item]). Pops true when
/// saved.
class LocationEditDialog extends ConsumerStatefulWidget {
  final LocationLevel level;
  final LocationItem? item;

  /// The list's filters, the parent a new row starts under.
  final int? dzongkhagId;
  final int? gewogId;

  const LocationEditDialog({super.key, required this.level, this.item, this.dzongkhagId, this.gewogId});

  @override
  ConsumerState<LocationEditDialog> createState() => _LocationEditDialogState();
}

class _LocationEditDialogState extends ConsumerState<LocationEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late int? _dzongkhagId = switch (widget.level) {
    LocationLevel.gewog => widget.item?.parentId ?? widget.dzongkhagId,
    LocationLevel.village => widget.item?.grandparentId ?? widget.dzongkhagId,
    LocationLevel.dzongkhag => null,
  };
  late int? _gewogId = widget.level == LocationLevel.village ? (widget.item?.parentId ?? widget.gewogId) : null;
  late String _kind = widget.item?.kind ?? GewogKind.gewog;
  late bool _active = widget.item?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final editing = widget.item != null;
    return AlertDialog(
      title: Text(editing ? 'Change ${level.label.toLowerCase()}' : 'Add a ${level.label.toLowerCase()}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (level != LocationLevel.dzongkhag) ...[
                  _ParentPicker(
                    level: LocationLevel.dzongkhag,
                    value: _dzongkhagId,
                    onChanged: (id) => setState(() {
                      _dzongkhagId = id;
                      _gewogId = null;
                    }),
                  ),
                  const SizedBox(height: 14),
                ],
                if (level == LocationLevel.village) ...[
                  _ParentPicker(
                    key: ValueKey('gewog-$_dzongkhagId'),
                    level: LocationLevel.gewog,
                    dzongkhagId: _dzongkhagId,
                    value: _gewogId,
                    onChanged: (id) => setState(() => _gewogId = id),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _name,
                  autofocus: !editing,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    final min = level == LocationLevel.village ? 1 : 2;
                    final max = switch (level) {
                      LocationLevel.dzongkhag => 60,
                      LocationLevel.gewog => 80,
                      LocationLevel.village => 100,
                    };
                    if (text.length < min) return 'Enter the name';
                    if (text.length > max) return 'Up to $max letters';
                    return null;
                  },
                ),
                if (level == LocationLevel.gewog) ...[
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: GewogKind.gewog, label: Text('Gewog')),
                      ButtonSegment(value: GewogKind.thromde, label: Text('Thromde / town')),
                    ],
                    selected: {_kind},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                  ),
                ],
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In use'),
                  subtitle: Text(_active ? 'Offered in forms' : 'Hidden from forms; addresses keep it'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(editing ? 'Save' : 'Add')),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => ref.read(masterRepositoryProvider).save(
            widget.level,
            id: widget.item?.id,
            parentId: widget.level == LocationLevel.gewog ? _dzongkhagId : _gewogId,
            name: _name.text,
            kind: _kind,
            active: _active,
          ),
      success: widget.item == null ? 'Added' : 'Saved',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }
}

/// The required parent of a new or changed row.
class _ParentPicker extends ConsumerWidget {
  final LocationLevel level;
  final int? dzongkhagId;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _ParentPicker({super.key, required this.level, required this.value, required this.onChanged, this.dzongkhagId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = level == LocationLevel.gewog && dzongkhagId == null;
    final items = waiting
        ? const <LocationItem>[]
        : ref
                .watch(masterListProvider((
                  level: level,
                  dzongkhagId: dzongkhagId,
                  gewogId: null,
                  search: '',
                  withInactive: true,
                )))
                .valueOrNull ??
            const <LocationItem>[];
    return SearchableDropdown<int>(
      value: items.any((i) => i.id == value) ? value : null,
      decoration: InputDecoration(labelText: '${level == LocationLevel.gewog ? 'Gewog or thromde' : 'Dzongkhag'} *'),
      hint: waiting ? 'Choose the dzongkhag first' : null,
      options: [for (final i in items) DropdownOption(i.id, i.isActive ? i.name : '${i.name} (off)')],
      onChanged: waiting ? null : onChanged,
      validator: (id) =>
          id == null ? (level == LocationLevel.gewog ? 'Choose the gewog' : 'Choose the dzongkhag') : null,
    );
  }
}
