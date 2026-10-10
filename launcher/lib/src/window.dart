/// Talks to the native runner, which owns the window: it shows the
/// launcher when the shortcut runs it again and hides it when it loses
/// focus.
library;

import 'package:flutter/services.dart';

class LauncherWindow {
  static const _channel = MethodChannel('flatkit_launcher/window');

  /// [onShown] runs each time the window is brought up, [onHidden] each
  /// time it goes away (by focus loss or [hide]).
  static void listen({required VoidCallback onShown, required VoidCallback onHidden}) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'shown':
          onShown();
        case 'hidden':
          onHidden();
      }
      return null;
    });
  }

  static Future<void> hide() async {
    try {
      await _channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // Running without the launcher's runner (tests, `flutter run -d web`).
    }
  }
}
