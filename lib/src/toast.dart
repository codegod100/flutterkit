/// Short notices at the bottom of the window, replacing Material's
/// SnackBar. A toast appears and disappears in a single frame.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'theme.dart';

OverlayEntry? _entry;
Timer? _timer;

/// Shows [message] at the bottom of the nearest [Overlay] for [duration],
/// replacing any toast already showing.
void showKitToast(BuildContext context, String message,
    {Duration duration = const Duration(seconds: 2)}) {
  hideKitToast();
  final c = KitTheme.of(context);
  final style = KitText.body(context).copyWith(color: c.background);
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 16,
      right: 16,
      bottom: 40,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.text,
              borderRadius: BorderRadius.circular(kitRadius),
              boxShadow: [BoxShadow(color: c.shadow, blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Text(message,
                style: style, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  _entry = entry;
  _timer = Timer(duration, hideKitToast);
}

/// Removes the toast now, if one is showing.
void hideKitToast() {
  _timer?.cancel();
  _timer = null;
  _entry?.remove();
  _entry = null;
}
