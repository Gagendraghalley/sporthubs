import 'package:flutter/material.dart';

/// [children] in as many columns as fit, each at least [minItemWidth] wide
/// (one on a phone, two or three on a laptop), filling the width. Cells in a
/// row share its height unless [equalHeight] is false.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;
  final bool equalHeight;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 340,
    this.maxColumns = 4,
    this.spacing = 12,
    this.runSpacing = 12,
    this.equalHeight = true,
  });

  /// How many columns of at least [minItemWidth] fit in [width].
  static int columnsFor(double width, {double minItemWidth = 340, int maxColumns = 4, double spacing = 12}) =>
      ((width + spacing) / (minItemWidth + spacing)).floor().clamp(1, maxColumns);

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth, minItemWidth: minItemWidth, maxColumns: maxColumns, spacing: spacing);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed) ...[if (i > 0) SizedBox(height: runSpacing), child],
            ],
          );
        }
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final cells = <Widget>[];
          for (var c = 0; c < columns; c++) {
            if (c > 0) cells.add(SizedBox(width: spacing));
            final i = start + c;
            cells.add(Expanded(child: i < children.length ? children[i] : const SizedBox.shrink()));
          }
          final row = Row(
            crossAxisAlignment: equalHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
            children: cells,
          );
          if (rows.isNotEmpty) rows.add(SizedBox(height: runSpacing));
          rows.add(equalHeight ? IntrinsicHeight(child: row) : row);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}

/// Two columns side by side when there's room ([breakpoint] and up), the
/// first above the second otherwise. [flex] shares the width between them.
class ResponsiveColumns extends StatelessWidget {
  final List<Widget> first;
  final List<Widget> second;
  final double breakpoint;
  final (int, int) flex;
  final double spacing;

  const ResponsiveColumns({
    super.key,
    required this.first,
    required this.second,
    this.breakpoint = 900,
    this.flex = (1, 1),
    this.spacing = 20,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...first, ...second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: flex.$1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: first)),
            SizedBox(width: spacing),
            Expanded(flex: flex.$2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: second)),
          ],
        );
      },
    );
  }
}
