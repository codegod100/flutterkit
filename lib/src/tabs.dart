/// A tab strip with an underline under the selected tab. Switching swaps
/// the underline on the spot; nothing slides.
library;

import 'package:flutter/widgets.dart';

import 'controls.dart';
import 'theme.dart';

class KitTabs<T> extends StatelessWidget {
  final List<(T, String)> tabs;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  /// Draws a border along the bottom of the whole strip.
  final bool border;

  const KitTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    this.height = 34,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = KitTheme.of(context);
    return Container(
      height: height,
      decoration: border
          ? BoxDecoration(border: Border(bottom: BorderSide(color: c.border)))
          : null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (value, label) in tabs)
            Pressable(
              onPressed: () => onChanged(value),
              builder: (context, s) {
                final on = value == selected;
                return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: s.pressed ? c.pressed : (s.hovered ? c.hover : const Color(0x00000000)),
                    border: Border(
                      bottom: BorderSide(
                        color: on ? c.accent : (s.focused ? c.focus : const Color(0x00000000)),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(label,
                      style: KitText.body(context).copyWith(
                        color: on ? c.text : c.textDim,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      )),
                );
              },
            ),
        ]),
      ),
    );
  }
}
