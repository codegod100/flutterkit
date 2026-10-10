/// The launcher's one screen: a search field over a keyboard-driven list
/// of applications, their actions, a calculator answer and a run-command
/// row.
library;

import 'dart:io';

import 'package:flatkit/flatkit.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'apps.dart';
import 'calc.dart';
import 'desktop_entry.dart';
import 'icons.dart';

const rowHeight = 46.0;

/// Something Enter can act on.
sealed class LauncherItem {
  const LauncherItem();
}

class AppItem extends LauncherItem {
  final AppResult result;
  const AppItem(this.result);
}

class ActionItem extends LauncherItem {
  final DesktopEntry entry;
  final DesktopAction action;
  const ActionItem(this.entry, this.action);
}

class CalcItem extends LauncherItem {
  final String expression;
  final double value;
  const CalcItem(this.expression, this.value);
}

class CommandItem extends LauncherItem {
  final String command;
  const CommandItem(this.command);
}

/// What the view needs from the outside world, so tests can stand in for
/// launching and hiding.
class LauncherServices {
  final Future<void> Function(DesktopEntry entry, DesktopAction? action) launchApp;
  final Future<void> Function(String command, bool terminal) runCommand;
  final Future<void> Function() hide;

  const LauncherServices({required this.launchApp, required this.runCommand, required this.hide});
}

class LauncherView extends StatefulWidget {
  final List<DesktopEntry> apps;
  final IconIndex icons;
  final LaunchHistory history;
  final LauncherServices services;

  const LauncherView({
    super.key,
    required this.apps,
    required this.icons,
    required this.history,
    required this.services,
  });

  @override
  State<LauncherView> createState() => LauncherViewState();
}

class LauncherViewState extends State<LauncherView> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  List<LauncherItem> _items = const [];
  int _selected = 0;

  /// The app whose actions are listed, or null for the main list.
  DesktopEntry? _actionsOf;

  @override
  void initState() {
    super.initState();
    _query.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(LauncherView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apps != widget.apps) _refresh(keepSelection: true);
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Clears the query and leaves any action list, for the next time the
  /// window comes up.
  void reset() {
    setState(() {
      _actionsOf = null;
      _query.clear();
      _selected = 0;
    });
    _refresh();
  }

  void focusSearch() => _focus.requestFocus();

  String? _lastQuery;

  void _refresh({bool keepSelection = false}) {
    final q = _query.text;
    final queryChanged = q != _lastQuery;
    _lastQuery = q;
    final List<LauncherItem> items;
    final actionsOf = _actionsOf;
    if (actionsOf != null) {
      items = [
        for (final a in actionsOf.actions)
          if (q.trim().isEmpty || fuzzyAction(q, a)) ActionItem(actionsOf, a),
      ];
    } else {
      final calc = evaluate(q);
      final apps = rank(widget.apps, q, widget.history);
      items = [
        if (calc != null) CalcItem(q.trim(), calc),
        for (final r in apps) AppItem(r),
        if (q.trim().isNotEmpty) CommandItem(q.trim()),
      ];
    }
    setState(() {
      _items = items;
      if (queryChanged || !keepSelection) _selected = 0;
      _selected = items.isEmpty ? 0 : _selected.clamp(0, items.length - 1);
    });
  }

  static bool fuzzyAction(String q, DesktopAction a) =>
      a.name.toLowerCase().contains(q.trim().toLowerCase());

  void _move(int delta) {
    if (_items.isEmpty) return;
    setState(() => _selected = (_selected + delta).clamp(0, _items.length - 1));
  }

  void _openActions() {
    final item = _items.isEmpty ? null : _items[_selected];
    if (item is! AppItem || item.result.entry.actions.isEmpty) return;
    _actionsOf = item.result.entry;
    _query.clear(); // triggers _refresh
    _refresh();
  }

  void _closeActions() {
    final of = _actionsOf;
    if (of == null) return;
    _actionsOf = null;
    _query.clear();
    _refresh();
    final i = _items.indexWhere((it) => it is AppItem && it.result.entry.id == of.id);
    if (i >= 0) setState(() => _selected = i);
  }

  Future<void> _activate(int index, {bool terminal = false}) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    try {
      switch (item) {
        case AppItem(:final result):
          await widget.services.launchApp(result.entry, null);
          widget.history.record(result.entry.id);
        case ActionItem(:final entry, :final action):
          await widget.services.launchApp(entry, action);
          widget.history.record(entry.id);
        case CalcItem(:final value):
          await Clipboard.setData(ClipboardData(text: formatNumber(value)));
        case CommandItem(:final command):
          await widget.services.runCommand(command, terminal);
      }
    } on LaunchException catch (e) {
      if (mounted) showKitToast(context, e.message, duration: const Duration(seconds: 4));
      return;
    }
    await widget.services.hide();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed;
    final alt = keys.isAltPressed;
    final shift = keys.isShiftPressed;

    if (key == LogicalKeyboardKey.arrowDown ||
        (ctrl && (key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.keyJ))) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        (ctrl && (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.keyK))) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _move(8);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _move(-8);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (ctrl && _actionsOf == null && _query.text.trim().isNotEmpty) {
        // Ctrl+Enter runs what was typed in a terminal, whatever matched.
        widget.services
            .runCommand(_query.text.trim(), true)
            .then((_) => widget.services.hide(), onError: (Object e) {
          if (mounted) showKitToast(context, '$e');
        });
      } else {
        _activate(_selected);
      }
    } else if (key == LogicalKeyboardKey.escape) {
      if (_actionsOf != null) {
        _closeActions();
      } else {
        widget.services.hide();
      }
    } else if (key == LogicalKeyboardKey.tab) {
      if (shift || _actionsOf != null) {
        _closeActions();
      } else {
        _openActions();
      }
    } else if (key == LogicalKeyboardKey.arrowRight && _actionsOf == null && _caretAtEnd) {
      final item = _items.isEmpty ? null : _items[_selected];
      if (item is! AppItem || item.result.entry.actions.isEmpty) return KeyEventResult.ignored;
      _openActions();
    } else if ((key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.backspace) &&
        _actionsOf != null &&
        _query.text.isEmpty) {
      _closeActions();
    } else if (alt && _digit(key) != null) {
      _activate(_digit(key)! - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool get _caretAtEnd {
    final s = _query.selection;
    return !s.isValid || (s.isCollapsed && s.baseOffset == _query.text.length);
  }

  static int? _digit(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final i = digits.indexOf(key);
    return i < 0 ? null : i + 1;
  }

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    final actionsOf = _actionsOf;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Container(
        decoration: BoxDecoration(
          color: c.background,
          border: Border.all(color: c.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: KitTextField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                prefixIcon: actionsOf == null ? Icons.search : Icons.subdirectory_arrow_right,
                hint: actionsOf == null
                    ? 'Search applications, or type a command'
                    : 'Actions for ${actionsOf.name}',
                style: const TextStyle(fontSize: 15),
                trailing: actionsOf == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(actionsOf.name, style: KitText.dim(context, small: true)),
                      ),
              ),
            ),
            const KitDivider(),
            Expanded(
              child: _items.isEmpty
                  ? Center(child: Text('Nothing found', style: KitText.dim(context)))
                  : KitSelectionList(
                      itemCount: _items.length,
                      selectedIndex: _selected,
                      itemExtent: rowHeight,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemBuilder: (context, i, selected) => KitListRow(
                        selected: selected,
                        height: rowHeight,
                        onTap: () {
                          setState(() => _selected = i);
                          _activate(i);
                        },
                        child: _row(context, _items[i], i, selected),
                      ),
                    ),
            ),
            const KitDivider(),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, LauncherItem item, int index, bool selected) {
    final c = KitTheme.of(context);
    final onAccent = selected;
    final dim = KitText.small(context, color: onAccent ? c.onAccent.withValues(alpha: 0.8) : c.textDim);
    final (Widget icon, Widget title, String? subtitle, bool hasActions) = switch (item) {
      AppItem(:final result) => (
          AppIcon(path: widget.icons.lookup(result.entry.icon)),
          _highlighted(context, result.entry.name, result.namePositions, selected),
          result.entry.genericName ?? result.entry.comment,
          result.entry.actions.isNotEmpty,
        ),
      ActionItem(:final entry, :final action) => (
          AppIcon(path: widget.icons.lookup(action.icon ?? entry.icon)),
          Text(action.name, overflow: TextOverflow.ellipsis),
          entry.name,
          false,
        ),
      CalcItem(:final value) => (
          const Icon(Icons.calculate_outlined, size: 26),
          Text('= ${formatNumber(value)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          'Enter copies the result',
          false,
        ),
      CommandItem(:final command) => (
          const Icon(Icons.terminal, size: 26),
          Text('Run “$command”', overflow: TextOverflow.ellipsis),
          'Ctrl+Enter runs it in a terminal',
          false,
        ),
    };
    return Row(children: [
      SizedBox(width: 30, height: 30, child: Center(child: icon)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            if (subtitle != null) Text(subtitle, style: dim, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      if (hasActions) Icon(Icons.chevron_right, size: 18, color: dim.color),
      if (index < 9) ...[
        const SizedBox(width: 8),
        Text('Alt+${index + 1}', style: dim),
      ],
    ]);
  }

  Widget _highlighted(BuildContext context, String text, List<int> positions, bool selected) {
    final c = KitTheme.of(context);
    if (positions.isEmpty) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    final hit = TextStyle(
      fontWeight: FontWeight.w700,
      color: selected ? null : c.accent,
      decoration: selected ? TextDecoration.underline : null,
      decorationColor: selected ? c.onAccent : null,
    );
    final spans = <TextSpan>[];
    final set = positions.toSet();
    var run = StringBuffer();
    bool? runHit;
    for (var i = 0; i < text.length; i++) {
      final h = set.contains(i);
      if (runHit != null && h != runHit) {
        spans.add(TextSpan(text: run.toString(), style: runHit ? hit : null));
        run = StringBuffer();
      }
      runHit = h;
      run.write(text[i]);
    }
    if (run.isNotEmpty) spans.add(TextSpan(text: run.toString(), style: runHit == true ? hit : null));
    return Text.rich(TextSpan(children: spans), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _footer(BuildContext context) {
    final style = KitText.dim(context, small: true);
    final hints = _actionsOf == null
        ? '↑↓ select   Enter open   Tab actions   Esc close'
        : '↑↓ select   Enter run   Tab back   Esc back';
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(children: [
        Expanded(child: Text(hints, style: style, overflow: TextOverflow.ellipsis)),
        Text(_actionsOf == null ? '${widget.apps.length} apps' : '', style: style),
      ]),
    );
  }
}

/// An application icon from a file, falling back to a generic one when
/// there is no file or it can't be drawn.
class AppIcon extends StatelessWidget {
  final String? path;
  final double size;

  const AppIcon({super.key, required this.path, this.size = 30});

  static final _svgzCache = <String, Future<Uint8List?>>{};

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.apps, size: size - 4);
    final p = path;
    if (p == null) return fallback;
    if (p.endsWith('.svg')) {
      return SvgPicture.file(File(p),
          width: size, height: size, placeholderBuilder: (_) => SizedBox(width: size, height: size));
    }
    if (p.endsWith('.svgz')) {
      return FutureBuilder<Uint8List?>(
        future: _svgzCache.putIfAbsent(p, () async {
          try {
            return Uint8List.fromList(gzip.decode(await File(p).readAsBytes()));
          } catch (_) {
            return null;
          }
        }),
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) return SizedBox(width: size, height: size);
          return SvgPicture.memory(data, width: size, height: size);
        },
      );
    }
    if (p.endsWith('.png')) {
      return Image.file(File(p),
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * 2).round(),
          errorBuilder: (_, __, ___) => fallback);
    }
    return fallback; // xpm and friends
  }
}
