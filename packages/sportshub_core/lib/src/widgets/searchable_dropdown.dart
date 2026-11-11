import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';

/// One choice in a [SearchableDropdown]. Its [label] shows in the field once
/// chosen; [detail] is a quieter line under it in the list. Both are
/// searched.
@immutable
class DropdownOption<T> {
  final T value;
  final String label;
  final String? detail;

  const DropdownOption(this.value, this.label, {this.detail});
}

/// A dropdown whose list opens with a search box on top: type to narrow it
/// (names starting with what's typed come first), arrows and Enter to
/// choose, Escape or a tap outside to close. In a [Form] it checks itself
/// like any field, and it follows [value] when the page changes it.
class SearchableDropdown<T> extends FormField<T> {
  final List<DropdownOption<T>> options;

  /// Null turns the field off.
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;

  /// Shown while nothing is chosen, and instead of the choice while the
  /// field is off.
  final String? hint;
  final String searchHint;
  final double menuMaxHeight;

  /// The open list, for tests.
  static const menuKey = ValueKey('searchable-dropdown-menu');

  SearchableDropdown({
    super.key,
    required this.options,
    required this.onChanged,
    T? value,
    this.decoration = const InputDecoration(),
    this.hint,
    this.searchHint = 'Search',
    this.menuMaxHeight = 420,
    super.validator,
    super.autovalidateMode,
  }) : super(initialValue: value, builder: (field) => (field as _SearchableDropdownState<T>)._field());

  @override
  FormFieldState<T> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends FormFieldState<T> {
  final _focus = FocusNode(debugLabel: 'SearchableDropdown');
  final _textKey = GlobalKey();
  _MenuRoute<T>? _route;
  Rect? _lastAnchor;
  double _padBottom = 16;
  bool _hover = false;

  @override
  SearchableDropdown<T> get widget => super.widget as SearchableDropdown<T>;

  bool get _open => _route?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void didUpdateWidget(SearchableDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) setValue(widget.initialValue);
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    _focus.dispose();
    super.dispose();
  }

  DropdownOption<T>? get _chosen {
    for (final o in widget.options) {
      if (o.value == value) return o;
    }
    return null;
  }

  /// The field's box (without its helper or error line) where the overlay
  /// is: the list opens under it, or over it when there's more room there.
  Rect _anchor(RenderBox overlay) {
    final box = mounted ? context.findRenderObject() as RenderBox? : null;
    if (box == null || !box.attached || !box.hasSize) return _lastAnchor ?? Rect.zero;
    var rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final text = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (text != null && text.attached && text.hasSize) {
      final bottom = text.localToGlobal(Offset(0, text.size.height), ancestor: overlay).dy + _padBottom;
      if (bottom < rect.bottom) rect = Rect.fromLTRB(rect.left, rect.top, rect.right, bottom);
    }
    return _lastAnchor = rect;
  }

  Future<void> _openMenu() async {
    if (widget.onChanged == null || _open) return;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final chosen = _chosen;
    final route = _MenuRoute<T>(
      anchor: () => _anchor(overlay),
      options: widget.options,
      selected: chosen,
      searchHint: widget.searchHint,
      maxHeight: widget.menuMaxHeight,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      duration: Motion.of(context, Motion.dropdown),
    );
    setState(() => _route = route);
    final picked = await navigator.push(route);
    if (!mounted) return;
    setState(() => _route = null);
    _focus.requestFocus();
    if (picked == null) return;
    didChange(picked.value);
    widget.onChanged?.call(picked.value);
  }

  Widget _field() {
    final theme = Theme.of(context);
    final enabled = widget.onChanged != null;
    final hint = widget.hint;
    final label = _chosen?.label;
    final shown = !enabled && hint != null ? hint : (label ?? hint);
    final isHint = shown != null && shown != label;
    _padBottom =
        (widget.decoration.contentPadding ?? theme.inputDecorationTheme.contentPadding)
                ?.resolve(Directionality.of(context))
                .bottom ??
            12;
    final style = theme.textTheme.bodyLarge;
    final textStyle = isHint
        ? style?.copyWith(color: theme.inputDecorationTheme.hintStyle?.color ?? theme.hintColor)
        : enabled
            ? style
            : style?.copyWith(color: theme.disabledColor);
    final keyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        focusNode: _focus,
        canRequestFocus: enabled,
        onTap: enabled ? _openMenu : null,
        onHover: (h) => setState(() => _hover = h),
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: InputDecorator(
          decoration: widget.decoration.copyWith(
            enabled: enabled,
            errorText: errorText,
            suffixIcon: widget.decoration.suffixIcon ??
                Icon(_open ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, size: 26),
          ),
          isFocused: _open || (_focus.hasFocus && keyboard),
          isHovering: _hover && enabled,
          isEmpty: shown == null,
          child: Text(shown ?? '', key: _textKey, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
        ),
      ),
    );
  }
}

/// What the list gives back: the choice (which may itself be null, as an
/// 'All'), or nothing when it was closed.
typedef _Picked<T> = ({T value});

class _MenuRoute<T> extends PopupRoute<_Picked<T>> {
  final Rect Function() anchor;
  final List<DropdownOption<T>> options;
  final DropdownOption<T>? selected;
  final String searchHint;
  final double maxHeight;
  final CapturedThemes themes;
  final Duration duration;

  @override
  final String? barrierLabel;

  _MenuRoute({
    required this.anchor,
    required this.options,
    required this.selected,
    required this.searchHint,
    required this.maxHeight,
    required this.themes,
    required this.barrierLabel,
    required this.duration,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration == Duration.zero ? Duration.zero : Motion.press;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      themes.wrap(_Menu<T>(route: this));
}

class _Menu<T> extends StatefulWidget {
  final _MenuRoute<T> route;

  const _Menu({required this.route});

  @override
  State<_Menu<T>> createState() => _MenuState<T>();
}

class _MenuState<T> extends State<_Menu<T>> with WidgetsBindingObserver {
  static const _searchHeight = 56.0;
  static const _listPad = 4.0;
  static const _gap = 4.0;
  static const _margin = 8.0;

  final _search = TextEditingController();
  ScrollController? _scroll;
  late final _anim = CurvedAnimation(parent: widget.route.animation!, curve: Motion.ease, reverseCurve: Motion.easeIn);
  late final _scale = _anim.drive(Tween(begin: 0.96, end: 1.0));
  late List<DropdownOption<T>> _shown = widget.route.options;
  String _query = '';
  late int _active = _selectedIndex < 0 ? 0 : _selectedIndex;
  double _extent = 48;

  List<DropdownOption<T>> get _all => widget.route.options;

  int get _selectedIndex => widget.route.selected == null ? -1 : _shown.indexOf(widget.route.selected!);

  /// The keyboard stays down on phones until they tap the search box, so the
  /// list isn't hidden under it.
  bool get _autofocus => switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => false,
        _ => true,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    // The window or the keyboard changed; the field may have moved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _scroll?.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _filter(String text) {
    final query = text.trim().toLowerCase();
    setState(() {
      _query = query;
      if (query.isEmpty) {
        _shown = _all;
      } else {
        final starts = <DropdownOption<T>>[];
        final words = <DropdownOption<T>>[];
        final rest = <DropdownOption<T>>[];
        for (final o in _all) {
          final label = o.label.toLowerCase();
          if (label.startsWith(query)) {
            starts.add(o);
          } else if (label.contains(' $query')) {
            words.add(o);
          } else if (label.contains(query) || (o.detail?.toLowerCase().contains(query) ?? false)) {
            rest.add(o);
          }
        }
        _shown = [...starts, ...words, ...rest];
      }
      _active = query.isEmpty ? math.max(_selectedIndex, 0) : 0;
    });
    if (query.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(center: true));
    } else if (_scroll?.hasClients ?? false) {
      _scroll!.jumpTo(0);
    }
  }

  void _move(int by) {
    if (_shown.isEmpty) return;
    setState(() => _active = (_active + by).clamp(0, _shown.length - 1));
    _reveal();
  }

  /// Scrolls so the highlighted row shows.
  void _reveal({bool center = false}) {
    final scroll = _scroll;
    if (!mounted || scroll == null || !scroll.hasClients || _active < 0) return;
    final p = scroll.position;
    final top = _listPad + _active * _extent;
    final bottom = top + _extent;
    if (center) {
      scroll.jumpTo((top - (p.viewportDimension - _extent) / 2).clamp(0.0, p.maxScrollExtent));
    } else if (top < p.pixels + _listPad) {
      scroll.jumpTo(math.max(0, top - _listPad));
    } else if (bottom > p.pixels + p.viewportDimension - _listPad) {
      scroll.jumpTo(math.min(p.maxScrollExtent, bottom - p.viewportDimension + _listPad));
    }
  }

  void _pick(DropdownOption<T> o) => Navigator.of(context).pop((value: o.value));

  void _pickActive() {
    if (_active >= 0 && _active < _shown.length) _pick(_shown[_active]);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = media.textScaler.scale(16) / 16;
    final hasDetail = _all.any((o) => o.detail != null);
    // Label 24 high (and two lines of detail, 32), padded.
    _extent = hasDetail ? 56 * scale + 12 : 24 * scale + 24;

    return LayoutBuilder(builder: (context, c) {
      final a = widget.route.anchor();
      final topBound = media.padding.top + _margin;
      final bottomBound = c.maxHeight - math.max(media.viewInsets.bottom, media.padding.bottom) - _margin;
      // Sized for the whole list, so it doesn't jump about while they type.
      final natural = _searchHeight + 1 + _listPad * 2 + math.max(_all.length, 1) * _extent;
      final want = math.min(widget.route.maxHeight, natural);
      final below = bottomBound - (a.bottom + _gap);
      final above = (a.top - _gap) - topBound;
      final goesBelow = below >= want || below >= above;
      final height = math.min(want, math.max(goesBelow ? below : above, math.min(want, 160.0)));
      final top = goesBelow ? a.bottom + _gap : a.top - _gap - height;
      final width = a.width.clamp(math.min(240.0, c.maxWidth - _margin * 2), c.maxWidth - _margin * 2).toDouble();
      final left = a.left.clamp(_margin, math.max(_margin, c.maxWidth - _margin - width)).toDouble();

      if (_scroll == null) {
        final list = height - _searchHeight - 1;
        final content = _listPad * 2 + _all.length * _extent;
        final offset = _listPad + _active * _extent - (list - _extent) / 2;
        _scroll = ScrollController(initialScrollOffset: offset.clamp(0.0, math.max(0.0, content - list)));
      }

      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: FadeTransition(
              opacity: _anim,
              child: ScaleTransition(
                scale: _scale,
                alignment: goesBelow ? Alignment.topCenter : Alignment.bottomCenter,
                child: _card(context),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final menu = theme.popupMenuTheme;
    return Material(
      key: SearchableDropdown.menuKey,
      color: menu.color ?? theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: menu.elevation ?? 8,
      shadowColor: menu.shadowColor,
      shape: menu.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: _searchHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
                    const SingleActivator(LogicalKeyboardKey.pageDown): () => _move(6),
                    const SingleActivator(LogicalKeyboardKey.pageUp): () => _move(-6),
                  },
                  child: TextField(
                    controller: _search,
                    autofocus: _autofocus,
                    onChanged: _filter,
                    onSubmitted: (_) => _pickActive(),
                    textInputAction: TextInputAction.search,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.route.searchHint,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                      suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _search.clear();
                                _filter('');
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _all.isEmpty ? 'Nothing to choose yet' : 'No matches for “${_search.text.trim()}”',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: _listPad),
                    itemExtent: _extent,
                    itemCount: _shown.length,
                    itemBuilder: _row,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final o = _shown[i];
    final selected = identical(o, widget.route.selected);
    final active = i == _active;
    final base = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: selected || o.detail != null ? FontWeight.w700 : FontWeight.w500,
      color: selected ? colors.onSecondaryContainer : null,
    );
    const mark = TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline);
    return Ink(
      color: selected
          ? colors.secondaryContainer
          : active
              ? colors.onSurface.withValues(alpha: 0.06)
              : null,
      child: InkWell(
        onTap: () => _pick(o),
        onHover: (h) {
          if (h && _active != i) setState(() => _active = i);
        },
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(_marked(o.label, mark), maxLines: 1, overflow: TextOverflow.ellipsis, style: base),
                    if (o.detail != null)
                      Text.rich(
                        _marked(o.detail!, mark),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected ? colors.onSecondaryContainer : theme.hintColor,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_rounded, size: 20, color: colors.onSecondaryContainer),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// [text] with what they typed picked out.
  TextSpan _marked(String text, TextStyle mark) {
    final at = _query.isEmpty ? -1 : text.toLowerCase().indexOf(_query);
    if (at < 0 || at + _query.length > text.length) return TextSpan(text: text);
    return TextSpan(children: [
      TextSpan(text: text.substring(0, at)),
      TextSpan(text: text.substring(at, at + _query.length), style: mark),
      TextSpan(text: text.substring(at + _query.length)),
    ]);
  }
}
