/// Finding application icons in the freedesktop icon theme, the way
/// Plasma does: the configured theme, what it inherits, then hicolor and
/// /usr/share/pixmaps.
library;

import 'dart:io';
import 'dart:isolate';

import 'desktop_entry.dart';

/// Maps icon names to files for one desired size. Built once by scanning
/// the theme directories, so lookups are map reads rather than stat calls.
class IconIndex {
  final Map<String, String> _byName;

  IconIndex(this._byName);

  IconIndex.empty() : _byName = const {};

  int get length => _byName.length;

  /// The file for [icon], which may be a name ("org.kde.dolphin") or an
  /// absolute path. Names with an extension are looked up without it too,
  /// since many desktop files get this wrong.
  String? lookup(String? icon) {
    if (icon == null || icon.isEmpty) return null;
    if (icon.startsWith('/')) return File(icon).existsSync() ? icon : null;
    final hit = _byName[icon];
    if (hit != null) return hit;
    final dot = icon.lastIndexOf('.');
    if (dot > 0) {
      final ext = icon.substring(dot + 1).toLowerCase();
      if (ext == 'png' || ext == 'svg' || ext == 'svgz' || ext == 'xpm') {
        return _byName[icon.substring(0, dot)];
      }
    }
    return null;
  }

  /// Builds the index on a background isolate.
  static Future<IconIndex> build({int size = 48, Map<String, String>? environment}) async {
    final env = environment ?? Platform.environment;
    final map = await Isolate.run(() => buildSync(size: size, environment: env));
    return IconIndex(map);
  }

  /// Scans themes in order of preference; the first file found for a name
  /// wins, and within a theme the directory closest to [size] wins
  /// (scalable directories count as an exact fit).
  static Map<String, String> buildSync({int size = 48, Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final bases = iconBaseDirs(env);
    final result = <String, String>{};

    for (final theme in themeChain(currentTheme(env), bases)) {
      for (final dir in _themeDirs(theme, bases, size)) {
        _addDir(dir, result);
      }
    }
    for (final base in bases) {
      // Unthemed icons straight in an icons directory (~/.icons/foo.png).
      _addDir(base, result);
    }
    _addDir('/usr/share/pixmaps', result);
    return result;
  }

  static void _addDir(String dir, Map<String, String> into) {
    final d = Directory(dir);
    if (!d.existsSync()) return;
    List<FileSystemEntity> files;
    try {
      files = d.listSync(followLinks: true);
    } on FileSystemException {
      return;
    }
    // Prefer svg over png over xpm within one directory.
    final local = <String, (int, String)>{};
    for (final f in files) {
      final path = f.path;
      final slash = path.lastIndexOf('/');
      final file = path.substring(slash + 1);
      final dot = file.lastIndexOf('.');
      if (dot <= 0) continue;
      final rank = switch (file.substring(dot + 1)) {
        'svg' => 0,
        'svgz' => 1,
        'png' => 2,
        'xpm' => 3,
        _ => -1,
      };
      if (rank < 0) continue;
      final name = file.substring(0, dot);
      final old = local[name];
      if (old == null || rank < old.$1) local[name] = (rank, path);
    }
    local.forEach((name, v) => into.putIfAbsent(name, () => v.$2));
  }

  /// The theme's directories that hold application icons, nearest to
  /// [size] first.
  static List<String> _themeDirs(String theme, List<String> bases, int size) {
    final dirs = <({String path, int distance})>[];
    for (final base in bases) {
      final root = '$base/$theme';
      final indexFile = File('$root/index.theme');
      if (!indexFile.existsSync()) continue;
      Map<String, Map<String, String>> groups;
      try {
        groups = DesktopEntry.parseGroups(indexFile.readAsStringSync());
      } catch (_) {
        continue;
      }
      // index.theme lists are comma-separated, unlike desktop files.
      final names = (groups['Icon Theme']?['Directories'] ?? '')
          .split(',')
          .map((d) => d.trim())
          .where((d) => d.isNotEmpty);
      for (final name in names) {
        final g = groups[name];
        if (g == null) continue;
        final context = g['Context'];
        // Applications live in the "Applications" context; some themes
        // leave Context out entirely, so keep those too.
        if (context != null && context != 'Applications' && context != 'Apps') continue;
        if ((int.tryParse(g['Scale'] ?? '1') ?? 1) != 1) continue;
        dirs.add((path: '$root/$name', distance: _distance(g, size)));
      }
    }
    dirs.sort((a, b) => a.distance.compareTo(b.distance));
    return [for (final d in dirs) d.path];
  }

  static int _distance(Map<String, String> g, int size) {
    final s = int.tryParse(g['Size'] ?? '') ?? 0;
    final type = g['Type'] ?? 'Threshold';
    if (type == 'Scalable') {
      final min = int.tryParse(g['MinSize'] ?? '') ?? s;
      final max = int.tryParse(g['MaxSize'] ?? '') ?? s;
      if (size >= min && size <= max) return 0;
      return size < min ? min - size : size - max;
    }
    if (type == 'Threshold') {
      final t = int.tryParse(g['Threshold'] ?? '') ?? 2;
      if ((size - s).abs() <= t) return (size - s).abs();
    }
    // Bigger icons scale down better than small ones scale up.
    return s >= size ? s - size : (size - s) * 2;
  }
}

/// `~/.icons`, then `icons` in each XDG data directory.
List<String> iconBaseDirs(Map<String, String> env) {
  final home = env['HOME'] ?? '';
  var dataHome = env['XDG_DATA_HOME'] ?? '';
  if (dataHome.isEmpty) dataHome = '$home/.local/share';
  var dataDirs = env['XDG_DATA_DIRS'] ?? '';
  if (dataDirs.isEmpty) dataDirs = '/usr/local/share:/usr/share';
  final dirs = [
    '$home/.icons',
    '$dataHome/icons',
    for (final d in dataDirs.split(':'))
      if (d.isNotEmpty) '${d.endsWith('/') ? d.substring(0, d.length - 1) : d}/icons',
    '/var/lib/flatpak/exports/share/icons',
    '$home/.local/share/flatpak/exports/share/icons',
  ];
  final seen = <String>{};
  return [for (final d in dirs) if (seen.add(d)) d];
}

/// The icon theme Plasma uses: `[Icons] Theme` in kdeglobals, defaulting to
/// Breeze.
String currentTheme(Map<String, String> env) {
  var config = env['XDG_CONFIG_HOME'] ?? '';
  if (config.isEmpty) config = '${env['HOME'] ?? ''}/.config';
  try {
    final groups = DesktopEntry.parseGroups(File('$config/kdeglobals').readAsStringSync());
    final theme = groups['Icons']?['Theme'];
    if (theme != null && theme.trim().isNotEmpty) return theme.trim();
  } catch (_) {}
  return 'breeze';
}

/// [theme] and everything it inherits, depth first, ending with hicolor.
List<String> themeChain(String theme, List<String> bases) {
  final chain = <String>[];
  void visit(String t) {
    if (chain.contains(t) || chain.length > 16) return;
    chain.add(t);
    for (final base in bases) {
      final f = File('$base/$t/index.theme');
      if (!f.existsSync()) continue;
      try {
        final inherits = DesktopEntry.parseGroups(f.readAsStringSync())['Icon Theme']?['Inherits'];
        if (inherits != null) {
          for (final parent in inherits.split(',')) {
            final p = parent.trim();
            if (p.isNotEmpty && p != 'hicolor') visit(p);
          }
        }
      } catch (_) {}
      break;
    }
  }

  visit(theme);
  chain.remove('hicolor');
  chain.add('hicolor');
  return chain;
}
