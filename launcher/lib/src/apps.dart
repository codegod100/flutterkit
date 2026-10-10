/// Finding installed applications, ranking them against a query, and
/// launching them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'desktop_entry.dart';
import 'fuzzy.dart';

/// The `applications` directories to scan, most important first, per the
/// XDG base directory spec: `$XDG_DATA_HOME` then each of
/// `$XDG_DATA_DIRS`.
List<String> applicationDirs([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? '';
  var dataHome = env['XDG_DATA_HOME'] ?? '';
  if (dataHome.isEmpty) dataHome = '$home/.local/share';
  var dataDirs = env['XDG_DATA_DIRS'] ?? '';
  if (dataDirs.isEmpty) dataDirs = '/usr/local/share:/usr/share';
  final dirs = <String>[dataHome, ...dataDirs.split(':').where((d) => d.isNotEmpty)];
  // Flatpak and Snap exports, which some sessions leave out of the list.
  for (final extra in [
    '$home/.local/share/flatpak/exports/share',
    '/var/lib/flatpak/exports/share',
    '/var/lib/snapd/desktop',
  ]) {
    if (!dirs.contains(extra)) dirs.add(extra);
  }
  final seen = <String>{};
  return [
    for (final d in dirs)
      if (seen.add(d.endsWith('/') ? d.substring(0, d.length - 1) : d))
        '${d.endsWith('/') ? d.substring(0, d.length - 1) : d}/applications',
  ];
}

/// Reads every application entry under [dirs]. An ID found in an earlier
/// directory shadows the same ID further down, so a user's copy in
/// `~/.local/share/applications` (or a Hidden=true override) wins.
/// Hidden entries and ones whose TryExec isn't installed are left out.
List<DesktopEntry> scanApplications({List<String>? dirs, Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final locale = env['LC_ALL']?.isNotEmpty == true
      ? env['LC_ALL']
      : (env['LC_MESSAGES']?.isNotEmpty == true ? env['LC_MESSAGES'] : env['LANG']);
  final desktops = (env['XDG_CURRENT_DESKTOP'] ?? 'KDE').split(':');
  final pathDirs = (env['PATH'] ?? '/usr/bin:/bin').split(':');

  final byId = <String, DesktopEntry?>{};
  for (final dir in dirs ?? applicationDirs(env)) {
    final root = Directory(dir);
    if (!root.existsSync()) continue;
    List<FileSystemEntity> files;
    try {
      files = root.listSync(recursive: true, followLinks: true);
    } on FileSystemException {
      continue;
    }
    for (final f in files) {
      if (f is! File || !f.path.endsWith('.desktop')) continue;
      final id = f.path.substring(dir.length + 1).replaceAll('/', '-');
      if (byId.containsKey(id)) continue;
      String contents;
      try {
        contents = f.readAsStringSync();
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
      final entry =
          DesktopEntry.parse(contents, id: id, path: f.path, locale: locale, desktops: desktops);
      // Record shadowing entries even when they aren't shown.
      byId[id] = entry;
    }
  }

  return [
    for (final e in byId.values)
      if (e != null && !e.hidden && _tryExecOk(e.tryExec, pathDirs)) e,
  ];
}

bool _tryExecOk(String? tryExec, List<String> pathDirs) {
  if (tryExec == null) return true;
  if (tryExec.startsWith('/')) return File(tryExec).existsSync();
  return pathDirs.any((d) => d.isNotEmpty && File('$d/$tryExec').existsSync());
}

/// How often and how recently each application was launched, kept in
/// `$XDG_STATE_HOME/flatkit-launcher/history.json`.
class LaunchHistory {
  final File? file;
  final Map<String, ({int count, int last})> _entries;

  LaunchHistory._(this.file, this._entries);

  LaunchHistory.memory() : this._(null, {});

  static String defaultPath([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    var state = env['XDG_STATE_HOME'] ?? '';
    if (state.isEmpty) state = '${env['HOME'] ?? ''}/.local/state';
    return '$state/flatkit-launcher/history.json';
  }

  static LaunchHistory load([String? path]) {
    final file = File(path ?? defaultPath());
    final entries = <String, ({int count, int last})>{};
    try {
      final data = jsonDecode(file.readAsStringSync());
      if (data is Map) {
        data.forEach((key, value) {
          if (key is String && value is Map) {
            final count = value['count'];
            final last = value['last'];
            if (count is int && last is int) entries[key] = (count: count, last: last);
          }
        });
      }
    } catch (_) {
      // Missing or unreadable: start fresh.
    }
    return LaunchHistory._(file, entries);
  }

  ({int count, int last})? operator [](String id) => _entries[id];

  void record(String id, {DateTime? now}) {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final old = _entries[id];
    _entries[id] = (count: (old?.count ?? 0) + 1, last: t);
    _save();
  }

  void _save() {
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.tmp');
      tmp.writeAsStringSync(jsonEncode({
        for (final e in _entries.entries) e.key: {'count': e.value.count, 'last': e.value.last},
      }));
      tmp.renameSync(f.path);
    } on FileSystemException {
      // History is a nicety; never fail a launch over it.
    }
  }

  /// A boost for ranking: grows with the log of the launch count and fades
  /// over a couple of weeks since the last launch.
  double boost(String id, {DateTime? now}) {
    final e = _entries[id];
    if (e == null) return 0;
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final days = math.max(0, t - e.last) / Duration.millisecondsPerDay;
    final recency = math.exp(-days / 14);
    return math.log(1 + e.count) * 6 + recency * 8;
  }
}

/// An application that matched a query, with where its name matched.
class AppResult {
  final DesktopEntry entry;
  final double score;

  /// Matched character indices in [DesktopEntry.name], for highlighting.
  final List<int> namePositions;

  const AppResult(this.entry, this.score, this.namePositions);
}

/// Ranks [apps] against [query]. An empty query lists everything, the
/// most used first and the rest alphabetically.
List<AppResult> rank(List<DesktopEntry> apps, String query, LaunchHistory history,
    {DateTime? now}) {
  final q = query.trim();
  if (q.isEmpty) {
    final results = [for (final a in apps) AppResult(a, history.boost(a.id, now: now), const [])];
    results.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase());
    });
    return results;
  }

  final results = <AppResult>[];
  for (final app in apps) {
    final name = fuzzyMatch(q, app.name);
    var best = name?.score ?? double.negativeInfinity;

    // Other fields count for less than the name, so "files" finds Dolphin
    // through its generic name but ranks an app called Files above it.
    void consider(String? text, double weight) {
      if (text == null || text.isEmpty) return;
      final m = fuzzyMatch(q, text);
      if (m != null && m.score * weight > best) best = m.score * weight;
    }

    consider(app.genericName, 0.8);
    for (final k in app.keywords) {
      consider(k, 0.75);
    }
    consider(_execName(app.exec), 0.7);
    // The comment only counts as a whole-word substring match, since a
    // fuzzy hit somewhere in a sentence means little.
    final comment = app.comment?.toLowerCase();
    if (comment != null && q.length >= 3 && RegExp('\\b${RegExp.escape(q.toLowerCase())}').hasMatch(comment)) {
      best = math.max(best, q.length * 16 * 0.5);
    }

    if (best == double.negativeInfinity) continue;
    results.add(AppResult(app, best + history.boost(app.id, now: now), name?.positions ?? const []));
  }
  results.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase());
  });
  return results;
}

String? _execName(String exec) {
  final args = parseExec(exec);
  if (args == null) return null;
  var program = args.first;
  // Look through wrappers so "env FOO=1 flatpak run org.x.App" finds App.
  var i = 0;
  if (program == 'env' || program.endsWith('/env')) {
    i = 1;
    while (i < args.length && args[i].contains('=')) {
      i++;
    }
    if (i < args.length) program = args[i];
  }
  if (program == 'flatpak' || program.endsWith('/flatpak')) {
    final app = args.skip(i + 1).where((a) => !a.startsWith('-') && a != 'run').firstOrNull;
    if (app != null) return app.split('.').last;
  }
  return program.split('/').last;
}

/// The terminal to run `Terminal=true` applications in: KDE's configured
/// one, else the first of a few common ones found on PATH.
List<String> terminalCommand([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? '';
  var config = env['XDG_CONFIG_HOME'] ?? '';
  if (config.isEmpty) config = '$home/.config';
  try {
    final groups = DesktopEntry.parseGroups(File('$config/kdeglobals').readAsStringSync());
    final t = groups['General']?['TerminalApplication'];
    if (t != null && t.trim().isNotEmpty) {
      final args = parseExec(t);
      if (args != null) return [...args, '-e'];
    }
  } catch (_) {}
  final pathDirs = (env['PATH'] ?? '/usr/bin:/bin').split(':');
  for (final t in ['konsole', 'kitty', 'alacritty', 'foot', 'wezterm', 'xterm']) {
    if (pathDirs.any((d) => d.isNotEmpty && File('$d/$t').existsSync())) {
      return t == 'wezterm' ? ['wezterm', 'start', '--'] : [t, '-e'];
    }
  }
  return ['xterm', '-e'];
}

/// Environment for launched apps: the launcher's own, minus what only
/// makes sense for the launcher's process.
Map<String, String> launchEnvironment() {
  final env = Map<String, String>.of(Platform.environment);
  env.remove('FLUTTER_ENGINE_SWITCHES');
  env.remove('DESKTOP_STARTUP_ID');
  env.remove('XDG_ACTIVATION_TOKEN');
  return env;
}

/// Starts [entry] (or one of its [action]s) detached from the launcher.
/// Throws a [LaunchException] when the Exec line can't be run.
Future<void> launch(DesktopEntry entry, {DesktopAction? action}) async {
  final args = parseExec(action?.exec ?? entry.exec,
      icon: action?.icon ?? entry.icon, name: entry.name, path: entry.path);
  if (args == null) throw LaunchException('Can\'t read the command for ${entry.name}');
  final command = entry.terminal ? [...terminalCommand(), ...args] : args;
  await _start(command, workingDirectory: entry.workingDirectory, name: entry.name);
}

/// Runs [commandLine] through the shell, in a terminal when [terminal].
Future<void> runCommand(String commandLine, {bool terminal = false}) async {
  final command = terminal
      ? [...terminalCommand(), 'sh', '-c', commandLine]
      : ['sh', '-c', commandLine];
  await _start(command, name: commandLine);
}

Future<void> _start(List<String> command, {String? workingDirectory, required String name}) async {
  var dir = workingDirectory;
  if (dir == null || !Directory(dir).existsSync()) dir = Platform.environment['HOME'];
  try {
    await Process.start(
      command.first,
      command.sublist(1),
      workingDirectory: dir,
      environment: launchEnvironment(),
      includeParentEnvironment: false,
      mode: ProcessStartMode.detached,
    );
  } on ProcessException catch (e) {
    throw LaunchException('Couldn\'t start $name: ${e.message}');
  }
}

class LaunchException implements Exception {
  final String message;
  const LaunchException(this.message);

  @override
  String toString() => message;
}
