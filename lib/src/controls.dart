/// Flat controls: buttons, segmented tabs, text fields, panels and progress
/// bars. Hover and press change colour on the spot; nothing ripples, fades
/// or slides.
library;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Icons, InputBorder, InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import 'theme.dart';
import 'tooltip.dart';

/// Interaction state a [Pressable] hands its builder.
class PressState {
  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool enabled;
  const PressState({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.enabled = true,
  });
}

/// The kit's single interaction primitive: mouse, tap and keyboard
/// (Enter/Space) activation with hover, press and focus state, and no
/// visual effect of its own.
class Pressable extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, PressState state) builder;
  final bool autofocus;
  final FocusNode? focusNode;
  final MouseCursor? cursor;

  const Pressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.autofocus = false,
    this.focusNode,
    this.cursor,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    if (!_enabled) _pressed = false;
  }

  void _activate() {
    if (_enabled) widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: _enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: _enabled ? (widget.cursor ?? SystemMouseCursors.click) : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => _activate()),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: _enabled ? _activate : null,
        child: widget.builder(
          context,
          PressState(
            hovered: _hovered && _enabled,
            pressed: _pressed && _enabled,
            focused: _focused && _enabled,
            enabled: _enabled,
          ),
        ),
      ),
    );
  }
}

enum KitButtonKind { primary, secondary, ghost, danger }

class KitButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final KitButtonKind kind;
  final IconData? icon;
  final String? tooltip;
  final bool autofocus;

  const KitButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = KitButtonKind.secondary,
    this.icon,
    this.tooltip,
    this.autofocus = false,
  });

  const KitButton.primary(this.label,
      {super.key, required this.onPressed, this.icon, this.tooltip, this.autofocus = false})
      : kind = KitButtonKind.primary;

  const KitButton.ghost(this.label,
      {super.key, required this.onPressed, this.icon, this.tooltip, this.autofocus = false})
      : kind = KitButtonKind.ghost;

  const KitButton.danger(this.label,
      {super.key, required this.onPressed, this.icon, this.tooltip, this.autofocus = false})
      : kind = KitButtonKind.danger;

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    final button = Pressable(
      onPressed: onPressed,
      autofocus: autofocus,
      builder: (context, s) {
        late Color bg, fg, border;
        switch (kind) {
          case KitButtonKind.primary:
            bg = s.pressed ? c.accentPressed : (s.hovered ? c.accentHover : c.accent);
            fg = c.onAccent;
            border = bg;
          case KitButtonKind.danger:
            bg = s.pressed || s.hovered ? c.dangerHover : c.danger;
            fg = c.onDanger;
            border = bg;
          case KitButtonKind.secondary:
            bg = s.pressed ? c.pressed : (s.hovered ? c.hover : c.surface);
            fg = c.text;
            border = c.border;
          case KitButtonKind.ghost:
            bg = s.pressed ? c.pressed : (s.hovered ? c.hover : const Color(0x00000000));
            fg = c.accent;
            border = bg;
        }
        if (!s.enabled) {
          bg = kind == KitButtonKind.ghost ? const Color(0x00000000) : c.hover;
          fg = c.textDim;
          border = kind == KitButtonKind.secondary ? c.border : bg;
        }
        if (s.focused) border = c.focus;
        return Container(
          height: kitControlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(kitRadius),
            border: Border.all(color: border, width: s.focused ? 2 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KitText.body(context).copyWith(color: fg, fontWeight: FontWeight.w500)),
            ),
          ]),
        );
      },
    );
    return tooltip == null ? button : KitTooltip(message: tooltip!, child: button);
  }
}

class KitIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;

  /// Width and height of the square button.
  final double extent;

  const KitIconButton(
    this.icon, {
    super.key,
    required this.onPressed,
    this.tooltip,
    this.size = 18,
    this.color,
    this.extent = kitControlHeight,
  });

  /// A 24px button with a 14px icon, for actions inside list rows.
  const KitIconButton.compact(
    this.icon, {
    super.key,
    required this.onPressed,
    this.tooltip,
    this.color,
  })  : size = 14,
        extent = 24;

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    final button = Pressable(
      onPressed: onPressed,
      builder: (context, s) => Container(
        width: extent,
        height: extent,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.pressed ? c.pressed : (s.hovered ? c.hover : const Color(0x00000000)),
          borderRadius: BorderRadius.circular(kitRadius),
          border: s.focused ? Border.all(color: c.focus, width: 2) : null,
        ),
        child: Icon(icon, size: size, color: s.enabled ? (color ?? c.text) : c.borderStrong),
      ),
    );
    return tooltip == null ? button : KitTooltip(message: tooltip!, child: button);
  }
}

/// A row of joined toggle buttons, one of which is selected.
class KitSegmented<T> extends StatelessWidget {
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  const KitSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    return Container(
      height: kitControlHeight,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.hover,
        borderRadius: BorderRadius.circular(kitRadius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (value, label) in segments)
          Pressable(
            onPressed: () => onChanged(value),
            builder: (context, s) {
              final on = value == selected;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? c.surface : (s.hovered ? c.pressed : const Color(0x00000000)),
                  borderRadius: BorderRadius.circular(kitRadius - 2),
                  border: s.focused ? Border.all(color: c.focus, width: 2) : null,
                ),
                child: Text(label,
                    style: KitText.body(context).copyWith(
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? c.text : c.textDim,
                    )),
              );
            },
          ),
      ]),
    );
  }
}

/// A single-line text field with a flat border that changes colour on
/// focus. Wraps Material's [TextField] for editing, selection and IME, but
/// draws nothing of Material's.
class KitTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final IconData? prefixIcon;
  final bool autofocus;
  final bool error;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Focus for the field; one is made and owned by the field when null.
  final FocusNode? focusNode;

  /// Text style for what is typed and for the hint, merged over the body
  /// style (for example a monospace family).
  final TextStyle? style;

  /// Shown at the end of the field, such as a clear button.
  final Widget? trailing;

  /// Hides what is typed, for passwords.
  final bool obscureText;

  /// When false the field shows its text but can't be focused or edited.
  final bool enabled;

  /// The on-screen keyboard to show, such as [TextInputType.url] for addresses.
  final TextInputType? keyboardType;

  /// When false the keyboard doesn't correct words or turn dashes and quotes into typographic ones.
  final bool autocorrect;

  /// When false the keyboard shows no word suggestions, so it also doesn't add its own spaces (after a period, for
  /// example). Turn it off for addresses, usernames and codes.
  final bool enableSuggestions;

  const KitTextField({
    super.key,
    required this.controller,
    this.hint,
    this.prefixIcon,
    this.autofocus = false,
    this.error = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.style,
    this.trailing,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
    this.autocorrect = true,
    this.enableSuggestions = true,
  });

  @override
  State<KitTextField> createState() => _KitTextFieldState();
}

class _KitTextFieldState extends State<KitTextField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(KitTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _own)?.removeListener(_changed);
      _focus.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    final focused = _focus.hasFocus;
    final border = widget.error ? c.danger : (focused ? c.focus : c.border);
    final style = KitText.body(context).merge(widget.style);
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Container(
          height: kitControlHeight + 2,
          padding: EdgeInsets.only(left: 8, right: widget.trailing == null ? 8 : 3),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(kitRadius),
            border: Border.all(color: border, width: focused || widget.error ? 2 : 1),
          ),
          child: Row(children: [
            if (widget.prefixIcon != null) ...[
              Icon(widget.prefixIcon, size: 16, color: c.textDim),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                obscureText: widget.obscureText,
                enabled: widget.enabled,
                keyboardType: widget.keyboardType,
                autocorrect: widget.autocorrect,
                enableSuggestions: widget.enableSuggestions,
                smartDashesType: widget.autocorrect ? null : SmartDashesType.disabled,
                smartQuotesType: widget.autocorrect ? null : SmartQuotesType.disabled,
                style: widget.enabled ? style : style.copyWith(color: c.textDim),
                cursorColor: c.accent,
                cursorWidth: 1.5,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: style.copyWith(color: c.textDim),
                  hintFadeDuration: Duration.zero,
                ),
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ]),
        ),
      ),
    );
  }
}

/// A bordered surface for grouping content.
class KitPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const KitPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    return Container(
      margin: margin,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(kitRadius + 2),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

class KitDivider extends StatelessWidget {
  const KitDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(height: 1, color: KitTheme.of(context).border);
}

class KitVerticalDivider extends StatelessWidget {
  const KitVerticalDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(width: 1, color: KitTheme.of(context).border);
}

/// A checkbox that flips on the spot, with an optional [label] that is
/// part of the click target.
class KitCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final Widget? labelWidget;
  final bool autofocus;

  const KitCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.labelWidget,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    final text = labelWidget ?? (label == null ? null : Text(label!));
    return Pressable(
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      autofocus: autofocus,
      builder: (context, s) {
        final fill = !s.enabled
            ? (value ? c.borderStrong : c.hover)
            : value
                ? (s.pressed ? c.accentPressed : (s.hovered ? c.accentHover : c.accent))
                : (s.pressed ? c.pressed : (s.hovered ? c.hover : c.surface));
        final border = s.focused ? c.focus : (value && s.enabled ? fill : c.borderStrong);
        final box = Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border, width: s.focused ? 2 : 1),
          ),
          child: value ? Icon(Icons.check, size: 12, color: c.onAccent) : null,
        );
        if (text == null) return box;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          box,
          const SizedBox(width: 8),
          Flexible(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: s.enabled ? c.text : c.textDim),
              child: text,
            ),
          ),
        ]);
      },
    );
  }
}

/// A determinate progress bar that jumps straight to [value].
class KitProgressBar extends StatelessWidget {
  final double value;
  const KitProgressBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    return Container(
      height: 4,
      decoration: BoxDecoration(color: c.hover, borderRadius: BorderRadius.circular(2)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }
}

/// An indeterminate spinner, for work with no known length.
class KitSpinner extends StatelessWidget {
  final double size;
  const KitSpinner({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: KitTheme.of(context).accent),
      );
}
