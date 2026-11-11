import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'common.dart';
import 'motion.dart';

// A data table in the manner of Material UI's data grid: a header row whose
// columns sort when tapped (up, down, then as it came), rows that light up
// under the mouse and open on a tap, and a footer with rows per page and
// the page's range. Columns that don't fit the width step aside, narrowest
// screens first, so a phone still gets a table and never a sideways scroll.

/// One column of a [DataGrid].
class GridColumn<T> {
  /// Names the column for [DataGrid.shows].
  final String key;
  final String label;

  /// Its share of the width left by fixed columns; or a fixed [width].
  final int flex;
  final double? width;

  /// The table's width from which it shows; under it, it steps aside.
  final double showFrom;

  /// What sorting by it compares; not sortable without one.
  final Comparable<Object?> Function(T row)? sortBy;

  /// Its contents, at the end of the cell rather than the start.
  final bool alignEnd;

  final Widget Function(BuildContext context, T row) cell;

  const GridColumn({
    required this.key,
    required this.label,
    required this.cell,
    this.flex = 1,
    this.width,
    this.showFrom = 0,
    this.sortBy,
    this.alignEnd = false,
  });
}

/// [rows] as a table of [columns], a page at a time.
class DataGrid<T> extends StatefulWidget {
  final List<GridColumn<T>> columns;
  final List<T> rows;
  final ValueChanged<T>? onRowTap;

  /// Read out for a row that opens.
  final String Function(T row)? rowLabel;

  /// The page sizes on offer; the first is the start.
  final List<int> pageSizes;

  /// What the footer counts: 'accounts', 'members'.
  final String noun;

  /// Rows shown faded: turned off, hidden.
  final bool Function(T row)? dimmed;

  const DataGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.rowLabel,
    this.pageSizes = const [10, 25, 50],
    this.noun = 'rows',
    this.dimmed,
  });

  /// Whether the grid around [context] is showing the column [key] (a cell
  /// can carry what a hidden column would have said).
  static bool shows(BuildContext context, String key) =>
      context.dependOnInheritedWidgetOfExactType<_GridScope>()?.shown.contains(key) ?? true;

  @override
  State<DataGrid<T>> createState() => _DataGridState<T>();
}

class _DataGridState<T> extends State<DataGrid<T>> {
  /// The column sorted by, and which way; null as the rows came.
  String? _sortKey;
  bool _ascending = true;
  int _page = 0;
  late int _pageSize = widget.pageSizes.first;

  @override
  void didUpdateWidget(DataGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fewer rows (a filter, a search): back to a page that has some.
    if (_page * _pageSize >= widget.rows.length) _page = 0;
  }

  /// Up, then down, then as the rows came: as Material UI's grid does.
  void _sortBy(GridColumn<T> column) => setState(() {
        _page = 0;
        if (_sortKey != column.key) {
          _sortKey = column.key;
          _ascending = true;
        } else if (_ascending) {
          _ascending = false;
        } else {
          _sortKey = null;
        }
      });

  List<T> get _sorted {
    final column = widget.columns.where((c) => c.key == _sortKey && c.sortBy != null).firstOrNull;
    if (column == null) return widget.rows;
    final rows = widget.rows;
    final keys = [for (final r in rows) column.sortBy!(r)];
    // By position, so it's stable: rows that tie keep the order they came in.
    final order = List.generate(rows.length, (i) => i)
      ..sort((a, b) {
        final c = keys[a].compareTo(keys[b]);
        return c != 0 ? (_ascending ? c : -c) : a.compareTo(b);
      });
    return [for (final i in order) rows[i]];
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, box) {
          final shown = [for (final c in widget.columns) if (box.maxWidth >= c.showFrom) c];
          final rows = _sorted;
          final total = rows.length;
          final pages = (total / _pageSize).ceil();
          final page = rows.skip(_page * _pageSize).take(_pageSize).toList();
          return _GridScope(
            shown: {for (final c in shown) c.key},
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header<T>(columns: shown, sortKey: _sortKey, ascending: _ascending, onSort: _sortBy),
                const Divider(height: 1),
                // A new page or order cross-fades in.
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.dropdown),
                  switchInCurve: Motion.ease,
                  switchOutCurve: Motion.easeIn,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
                  child: Column(
                    key: ValueKey('$_page-$_pageSize-$_sortKey-$_ascending'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, row) in page.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _Row<T>(
                          columns: shown,
                          row: row,
                          label: widget.rowLabel?.call(row),
                          dimmed: widget.dimmed?.call(row) ?? false,
                          onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                _Footer(
                  // A short list: just how many; no pages to turn.
                  paged: total > widget.pageSizes.first,
                  from: total == 0 ? 0 : _page * _pageSize + 1,
                  to: (_page * _pageSize + page.length),
                  total: total,
                  noun: widget.noun,
                  pageSize: _pageSize,
                  pageSizes: widget.pageSizes,
                  wide: box.maxWidth >= 480,
                  onPageSize: (n) => setState(() {
                    _pageSize = n;
                    _page = 0;
                  }),
                  onPrevious: _page > 0 ? () => setState(() => _page--) : null,
                  onNext: _page < pages - 1 ? () => setState(() => _page++) : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GridScope extends InheritedWidget {
  final Set<String> shown;

  const _GridScope({required this.shown, required super.child});

  @override
  bool updateShouldNotify(_GridScope old) => old.shown.length != shown.length || !old.shown.containsAll(shown);
}

/// The cells of a row (or the header) laid out by their columns.
Widget _cells<T>(List<GridColumn<T>> columns, Widget Function(GridColumn<T> c) cell) => Row(
      children: [
        for (final c in columns)
          if (c.width != null)
            SizedBox(width: c.width, child: cell(c))
          else
            Expanded(flex: c.flex, child: cell(c)),
      ],
    );

/// 'accounts' -> 'account', 'packages' -> 'package', 'staff' stays.
String _singular(String noun) => noun.endsWith('s') ? noun.substring(0, noun.length - 1) : noun;

const _cellPadding = EdgeInsets.symmetric(horizontal: 8);
const _rowPadding = EdgeInsets.symmetric(horizontal: 10);

class _Header<T> extends StatelessWidget {
  final List<GridColumn<T>> columns;
  final String? sortKey;
  final bool ascending;
  final ValueChanged<GridColumn<T>> onSort;

  const _Header({required this.columns, required this.sortKey, required this.ascending, required this.onSort});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.brand.subtle,
      padding: _rowPadding,
      constraints: const BoxConstraints(minHeight: 52),
      child: _cells<T>(columns, (c) => _HeaderCell(column: c, sorted: sortKey == c.key, ascending: ascending, onSort: onSort)),
    );
  }
}

/// A column's name; tapped, it sorts by it, the arrow saying which way.
/// Under the mouse a sortable column shows a faint arrow, as an invitation.
class _HeaderCell<T> extends StatefulWidget {
  final GridColumn<T> column;
  final bool sorted;
  final bool ascending;
  final ValueChanged<GridColumn<T>> onSort;

  const _HeaderCell({required this.column, required this.sorted, required this.ascending, required this.onSort});

  @override
  State<_HeaderCell<T>> createState() => _HeaderCellState<T>();
}

class _HeaderCellState<T> extends State<_HeaderCell<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.column;
    final brand = context.brand;
    final label = Text(
      c.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: widget.sorted ? brand.ink : brand.body),
    );
    if (c.sortBy == null) {
      return Padding(padding: _cellPadding, child: Align(alignment: c.alignEnd ? Alignment.centerRight : Alignment.centerLeft, child: label));
    }
    final arrow = AnimatedOpacity(
      opacity: widget.sorted ? 1 : (_hover ? 0.45 : 0),
      duration: Motion.hover,
      child: AnimatedRotation(
        // Up for ascending, turned to point down for descending.
        turns: widget.sorted && !widget.ascending ? 0.5 : 0,
        duration: Motion.of(context, Motion.dropdown),
        curve: Motion.ease,
        child: Icon(Icons.arrow_upward_rounded, size: 16, color: widget.sorted ? brand.ink : brand.muted),
      ),
    );
    return Semantics(
      button: true,
      label: '${c.label}, ${widget.sorted ? (widget.ascending ? 'sorted ascending' : 'sorted descending') : 'sort'}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSort(c),
          child: Padding(
            padding: _cellPadding.add(const EdgeInsets.symmetric(vertical: 14)),
            child: Row(
              mainAxisAlignment: c.alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [Flexible(child: label), const SizedBox(width: 4), arrow],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row: lights up under the mouse, and opens on a tap.
class _Row<T> extends StatefulWidget {
  final List<GridColumn<T>> columns;
  final T row;
  final String? label;
  final bool dimmed;
  final VoidCallback? onTap;

  const _Row({required this.columns, required this.row, this.label, this.dimmed = false, this.onTap});

  @override
  State<_Row<T>> createState() => _RowState<T>();
}

class _RowState<T> extends State<_Row<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tint = context.colors.tertiary;
    final row = AnimatedContainer(
      duration: Motion.hover,
      curve: Motion.ease,
      color: tint.withValues(alpha: _hover && widget.onTap != null ? 0.05 : 0),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: _rowPadding,
          constraints: const BoxConstraints(minHeight: 64),
          child: _cells<T>(
            widget.columns,
            (c) => Padding(
              padding: _cellPadding.add(const EdgeInsets.symmetric(vertical: 10)),
              child: Align(
                alignment: c.alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                child: c.cell(context, widget.row),
              ),
            ),
          ),
        ),
      ),
    );
    final content = widget.dimmed
        ? AnimatedOpacity(opacity: 0.62, duration: Motion.of(context, Motion.dropdown), child: row)
        : row;
    return Semantics(
      button: widget.onTap != null,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: content,
      ),
    );
  }
}

/// 'Rows per page 10 ▾   1–10 of 42   ‹ ›', at the table's foot; just
/// '4 roles' when they all fit on one page.
class _Footer extends StatelessWidget {
  final bool paged;
  final int from;
  final int to;
  final int total;
  final String noun;
  final int pageSize;
  final List<int> pageSizes;
  final bool wide;
  final ValueChanged<int> onPageSize;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _Footer({
    required this.paged,
    required this.from,
    required this.to,
    required this.total,
    required this.noun,
    required this.pageSize,
    required this.pageSizes,
    required this.wide,
    required this.onPageSize,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final quiet = TextStyle(fontSize: 13.5, color: brand.body);
    if (!paged) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Text('$total ${total == 1 ? _singular(noun) : noun}', style: quiet.copyWith(color: brand.muted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          if (wide) ...[
            Text('Rows per page', style: quiet),
            const SizedBox(width: 10),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: pageSize,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                style: quiet.copyWith(color: brand.ink, fontWeight: FontWeight.w600, fontFamily: brandFont),
                items: [for (final n in pageSizes) DropdownMenuItem(value: n, child: Text('$n'))],
                onChanged: (n) => n == null ? null : onPageSize(n),
              ),
            ),
          ],
          const Spacer(),
          Semantics(
            liveRegion: true,
            child: Text(total == 0 ? 'No $noun' : '$from–$to of $total', style: quiet),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Previous page',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
