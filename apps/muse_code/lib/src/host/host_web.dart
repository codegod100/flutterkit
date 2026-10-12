import 'package:web/web.dart' as web;

import 'host.dart';

Host createHost() => WebHost();

/// Keeps state in the browser's localStorage, so the relay settings and
/// projects survive a reload.
class WebHost implements Host {
  static const _key = 'muse_code.state';

  @override
  String get stateLocation => "this browser's local storage";

  @override
  Future<String?> loadState() async {
    try {
      return web.window.localStorage.getItem(_key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveState(String json) async {
    try {
      web.window.localStorage.setItem(_key, json);
    } catch (_) {
      // Storage blocked (private mode); keep running without saving.
    }
  }
}
