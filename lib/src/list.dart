/// Keyboard-driven lists: rows with a static selection highlight, and a
/// fixed-extent list that keeps the selected row in view by jumping, never
/// by animating.
library;

import 'package:flutter/widgets.dart';

import 'theme.dart';

const kitRowHeight = 28.0;

/// A list row with hover and selection states. The selection uses the
/// accent colour while [active] (the list holding the row has the
/// keyboard) and a neutral tint otherwise.
///
/// Rows don't take focus: lists are driven from the keyboard by whoever
/// owns the selection, and a tap just reports itself through [onTap].
class KitListRow extends StatefulWidget {
  final bool selected;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  const KitListRow({
    super.key,
    required this.child,
    this.selected = false,
    this.active = true,
    this.onTap,
    this.onDoubleTap,
    this.height = kitRowHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });

  @override
  State<KitListRow> createState() => _KitListRowState();
}

class _KitListRowState extends State<KitListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    final interactive = widget.onTap != null || widget.onDoubleTap != null;
    final strong = widget.selected && widget.active;
    final Color bg;
    if (strong) {
      bg = c.accent;
    } else if (widget.selected) {
      bg = c.pressed;
    } else if (_hovered && interactive) {
      bg = c.hover;
    } else {
      bg = const Color(0x00000000);
    }
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          height: widget.height,
          color: bg,
          padding: widget.padding,
          alignment: AlignmentDirectional.centerStart,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: strong ? c.onAccent : c.text),
            child: IconTheme.merge(
              data: IconThemeData(color: strong ? c.onAccent : c.textDim),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A list of [itemCount] rows of [itemExtent] each, scrolled so the row at
/// [selectedIndex] stays visible whenever the selection or count changes.
class KitSelectionList extends StatefulWidget {
  final int itemCount;
  final int selectedIndex;
  final double itemExtent;
  final Widget Function(BuildContext context, int index, bool selected) itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;

  const KitSelectionList({
    super.key,
    required this.itemCount,
    required this.selectedIndex,
    required this.itemBuilder,
    this.itemExtent = kitRowHeight,
    this.controller,
    this.padding,
  });

  @override
  State<KitSelectionList> createState() => _KitSelectionListState();
}

class _KitSelectionListState extends State<KitSelectionList> {
  ScrollController? _own;
  ScrollController get _controller => widget.controller ?? (_own ??= ScrollController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void didUpdateWidget(KitSelectionList old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex ||
        old.itemCount != widget.itemCount ||
        old.itemExtent != widget.itemExtent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal() {
    if (!mounted || !_controller.hasClients) return;
    final i = widget.selectedIndex;
    if (i < 0 || i >= widget.itemCount) return;
    final position = _controller.position;
    final top = i * widget.itemExtent;
    final bottom = top + widget.itemExtent;
    if (top < position.pixels) {
      _controller.jumpTo(top.clamp(0, position.maxScrollExtent));
    } else if (bottom > position.pixels + position.viewportDimension) {
      _controller.jumpTo((bottom - position.viewportDimension).clamp(0, position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    // Always shown, so it never fades in or out as the list jumps.
    return RawScrollbar(
      controller: _controller,
      thumbVisibility: true,
      thickness: 6,
      radius: const Radius.circular(3),
      thumbColor: c.borderStrong,
      fadeDuration: Duration.zero,
      timeToFade: Duration.zero,
      child: ListView.builder(
        controller: _controller,
        padding: widget.padding ?? EdgeInsets.zero,
        itemExtent: widget.itemExtent,
        itemCount: widget.itemCount,
        itemBuilder: (context, i) => widget.itemBuilder(context, i, i == widget.selectedIndex),
      ),
    );
  }
}
