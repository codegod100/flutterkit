/// File and environment access for [KdeColors] and [KitSystemTheme] where
/// dart:io exists.
library;

import 'dart:async';
import 'dart:io';

Map<String, String> platformEnvironment() => Platform.environment;

bool get platformIsLinux => Platform.isLinux;

String? readFile(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

/// Fires when [path] is written or replaced, or returns null when it can't
/// be watched.
Stream<void>? watchFile(String path) {
  // KDE saves by writing a temporary file and renaming it over
  // kdeglobals, so watch the directory rather than the file.
  final file = File(path);
  final dir = file.parent;
  if (!dir.existsSync()) return null;
  try {
    return dir
        .watch()
        .where((e) =>
            e.path == file.path || (e is FileSystemMoveEvent && e.destination == file.path))
        .handleError((_) {});
  } on FileSystemException {
    // No inotify; colours just won't update live.
    return null;
  }
}
