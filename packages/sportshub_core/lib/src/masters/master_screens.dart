import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../access/access.dart';
import '../access/permission_gate.dart';
import '../theme/brand.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
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
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                              child: FormHint(
                                items.length >= masterListLimit
                                    ? 'Showing the first $masterListLimit. Search, or choose a '
                                        '${_level == LocationLevel.village ? 'gewog' : 'dzongkhag'}, to see the rest.'
                                    : '${items.length} ${items.length == 1 ? _level.label.toLowerCase() : _level.plural.toLowerCase()}',
                              ),
                            ),
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
    final saved = await showDialog<bool>(
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

/// The rows as a table on a wide screen (name, where it is, code, whether
/// it's in use); as a list on a phone. Tap a row to change it.
class _MasterTable extends StatelessWidget {
  final LocationLevel level;
  final List<LocationItem> items;
  final ValueChanged<LocationItem> onTap;

  const _MasterTable({required this.level, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 700) {
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, item) in items.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _LocationTile(item: item, onTap: () => onTap(item)),
                ],
              ],
            ),
          );
        }
        final muted = context.brand.muted;
        final columns = <(String, int, Widget Function(LocationItem))>[
          ('Name', 4, (i) => Text(i.name, style: TextStyle(fontWeight: FontWeight.w600, color: i.isActive ? null : muted))),
          if (level == LocationLevel.gewog) ...[
            ('Kind', 2, (i) => Text(GewogKind.label(i.kind ?? GewogKind.gewog))),
            ('Dzongkhag', 3, (i) => Text(i.parentName ?? '—')),
          ],
          if (level == LocationLevel.village) ...[
            ('Gewog or thromde', 3, (i) => Text(i.parentName ?? '—')),
            ('Dzongkhag', 3, (i) => Text(i.grandparentName ?? '—')),
            ('Code', 2, (i) => Text(i.code ?? '—', style: TextStyle(color: muted, fontFeatures: const [FontFeature.tabularFigures()]))),
          ],
          ('Status', 2, (i) => Align(
                alignment: Alignment.centerLeft,
                child: i.isActive
                    ? StatusChip(label: 'In use', color: context.brand.success)
                    : StatusChip(label: 'Off', color: muted),
              )),
        ];
        Widget row(List<Widget> cells, {Widget? trailing}) => Row(
              children: [
                for (final (i, col) in columns.indexed) Expanded(flex: col.$2, child: cells[i]),
                SizedBox(width: 40, child: trailing),
              ],
            );
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: context.colors.primary.withValues(alpha: 0.05),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: row([
                  for (final col in columns)
                    Text(col.$1, style: context.text.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w700)),
                ]),
              ),
              for (final item in items) ...[
                const Divider(height: 1),
                InkWell(
                  onTap: () => onTap(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: row(
                      [for (final col in columns) col.$3(item)],
                      trailing: Icon(Icons.edit_outlined, size: 18, color: muted),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LocationTile extends StatelessWidget {
  final LocationItem item;
  final VoidCallback onTap;

  const _LocationTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final details = [
      if (item.kind == GewogKind.thromde) 'Thromde',
      if (item.place != null) item.place!,
      if (item.code != null) item.code!,
    ];
    return ListTile(
      onTap: onTap,
      title: Text(item.name, style: TextStyle(color: item.isActive ? null : context.brand.muted)),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!item.isActive) StatusChip(label: 'Off', color: context.brand.muted),
          const SizedBox(width: 4),
          const Icon(Icons.edit_outlined, size: 20),
        ],
      ),
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
    return DropdownButtonFormField<int?>(
      initialValue: items.any((i) => i.id == value) ? value : null,
      isExpanded: true,
      menuMaxHeight: 420,
      decoration: InputDecoration(labelText: level == LocationLevel.gewog ? 'Gewog' : 'Dzongkhag'),
      hint: Text(needsDzongkhag ? 'Choose a dzongkhag to choose a gewog' : 'All'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('All')),
        for (final i in items)
          DropdownMenuItem<int?>(value: i.id, child: Text(i.name, overflow: TextOverflow.ellipsis)),
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
    return DropdownButtonFormField<int>(
      initialValue: items.any((i) => i.id == value) ? value : null,
      isExpanded: true,
      menuMaxHeight: 420,
      decoration: InputDecoration(labelText: '${level == LocationLevel.gewog ? 'Gewog or thromde' : 'Dzongkhag'} *'),
      hint: waiting ? const Text('Choose the dzongkhag first') : null,
      items: [
        for (final i in items)
          DropdownMenuItem(
              value: i.id, child: Text(i.isActive ? i.name : '${i.name} (off)', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: waiting ? null : onChanged,
      validator: (id) =>
          id == null ? (level == LocationLevel.gewog ? 'Choose the gewog' : 'Choose the dzongkhag') : null,
    );
  }
}
