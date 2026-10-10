/// Parsing of freedesktop.org desktop entries (`.desktop` files) and of
/// their Exec lines.
library;

/// One `[Desktop Action …]` of an application, such as "New Private Window".
class DesktopAction {
  final String id;
  final String name;
  final String? icon;
  final String exec;

  const DesktopAction({required this.id, required this.name, this.icon, required this.exec});
}

/// The parts of an `Application` desktop entry the launcher uses.
class DesktopEntry {
  /// The desktop file ID: its path below `applications/` with `/` turned
  /// into `-`, such as `org.kde.dolphin.desktop`.
  final String id;
  final String path;
  final String name;
  final String? genericName;
  final String? comment;
  final String? icon;
  final String exec;
  final String? tryExec;
  final String? workingDirectory;
  final bool terminal;
  final List<String> keywords;
  final List<String> categories;
  final List<DesktopAction> actions;

  /// Whether the entry asked to be left out of menus (NoDisplay or Hidden,
  /// or OnlyShowIn/NotShowIn excluding the current desktop).
  final bool hidden;

  const DesktopEntry({
    required this.id,
    required this.path,
    required this.name,
    this.genericName,
    this.comment,
    this.icon,
    required this.exec,
    this.tryExec,
    this.workingDirectory,
    this.terminal = false,
    this.keywords = const [],
    this.categories = const [],
    this.actions = const [],
    this.hidden = false,
  });

  /// Parses [contents] as an application entry. Returns null for anything
  /// that isn't a launchable application (links, directories, entries
  /// without a Name or Exec).
  ///
  /// [locale] is a POSIX locale such as `de_DE.UTF-8@euro`, used to pick
  /// translated keys; [desktops] are the current desktop names (from
  /// `XDG_CURRENT_DESKTOP`) that OnlyShowIn and NotShowIn are checked
  /// against.
  static DesktopEntry? parse(
    String contents, {
    required String id,
    String path = '',
    String? locale,
    List<String> desktops = const ['KDE'],
  }) {
    final groups = parseGroups(contents);
    final main = groups['Desktop Entry'];
    if (main == null) return null;
    if ((main['Type'] ?? 'Application') != 'Application') return null;

    final keys = localeKeys(locale);
    String? get(Map<String, String> group, String key, {bool localized = false}) {
      if (localized) {
        for (final suffix in keys) {
          final v = group['$key[$suffix]'];
          if (v != null) return unescape(v);
        }
      }
      final v = group[key];
      return v == null ? null : unescape(v);
    }

    List<String> list(Map<String, String> group, String key, {bool localized = false}) {
      String? raw;
      if (localized) {
        for (final suffix in keys) {
          raw = group['$key[$suffix]'];
          if (raw != null) break;
        }
      }
      raw ??= group[key];
      return raw == null ? const [] : splitList(raw);
    }

    final name = get(main, 'Name', localized: true);
    final exec = get(main, 'Exec');
    if (name == null || name.isEmpty || exec == null || exec.trim().isEmpty) return null;

    bool flag(String key) => main[key]?.trim().toLowerCase() == 'true';
    final upper = desktops.map((d) => d.toUpperCase()).toSet();
    final only = list(main, 'OnlyShowIn');
    final not = list(main, 'NotShowIn');
    final excluded = (only.isNotEmpty && !only.any((d) => upper.contains(d.toUpperCase()))) ||
        not.any((d) => upper.contains(d.toUpperCase()));

    final actions = <DesktopAction>[];
    for (final actionId in list(main, 'Actions')) {
      final group = groups['Desktop Action $actionId'];
      if (group == null) continue;
      final actionName = get(group, 'Name', localized: true);
      final actionExec = get(group, 'Exec');
      if (actionName == null || actionExec == null || actionExec.trim().isEmpty) continue;
      actions.add(DesktopAction(
          id: actionId, name: actionName, icon: get(group, 'Icon'), exec: actionExec));
    }

    String? nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

    return DesktopEntry(
      id: id,
      path: path,
      name: name.trim(),
      genericName: nonEmpty(get(main, 'GenericName', localized: true)),
      comment: nonEmpty(get(main, 'Comment', localized: true)),
      icon: nonEmpty(get(main, 'Icon')),
      exec: exec,
      tryExec: nonEmpty(get(main, 'TryExec')),
      workingDirectory: nonEmpty(get(main, 'Path')),
      terminal: flag('Terminal'),
      keywords: list(main, 'Keywords', localized: true),
      categories: list(main, 'Categories'),
      actions: actions,
      hidden: flag('NoDisplay') || flag('Hidden') || excluded,
    );
  }

  /// The groups of a desktop file, keys kept as written (including any
  /// `[locale]` suffix). Later duplicates of a key win.
  static Map<String, Map<String, String>> parseGroups(String contents) {
    final groups = <String, Map<String, String>>{};
    Map<String, String>? current;
    for (var line in contents.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        current = groups.putIfAbsent(line.substring(1, line.length - 1), () => {});
        continue;
      }
      final eq = line.indexOf('=');
      if (current == null || eq <= 0) continue;
      current[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
    }
    return groups;
  }

  /// Locale suffixes to try, best first, for a POSIX locale
  /// `lang_COUNTRY.ENCODING@MODIFIER`, as the spec orders them.
  static List<String> localeKeys(String? locale) {
    if (locale == null || locale.isEmpty || locale == 'C' || locale == 'POSIX') return const [];
    var rest = locale;
    String? modifier;
    final at = rest.indexOf('@');
    if (at >= 0) {
      modifier = rest.substring(at + 1);
      rest = rest.substring(0, at);
    }
    final dot = rest.indexOf('.');
    if (dot >= 0) rest = rest.substring(0, dot);
    String? country;
    final underscore = rest.indexOf('_');
    final lang = underscore >= 0 ? rest.substring(0, underscore) : rest;
    if (underscore >= 0) country = rest.substring(underscore + 1);
    return [
      if (country != null && modifier != null) '${lang}_$country@$modifier',
      if (country != null) '${lang}_$country',
      if (modifier != null) '$lang@$modifier',
      lang,
    ];
  }

  /// Undoes the `\s \n \t \r \\` escapes of string values.
  static String unescape(String v) {
    if (!v.contains('\\')) return v;
    final out = StringBuffer();
    for (var i = 0; i < v.length; i++) {
      final ch = v[i];
      if (ch != '\\' || i + 1 == v.length) {
        out.write(ch);
        continue;
      }
      final next = v[++i];
      switch (next) {
        case 's':
          out.write(' ');
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'r':
          out.write('\r');
        case '\\':
          out.write('\\');
        default:
          // Leave unknown escapes (such as Exec's `\"`) for later stages.
          out.write('\\');
          out.write(next);
      }
    }
    return out.toString();
  }

  /// Splits a `;`-separated list, honouring `\;`.
  static List<String> splitList(String raw) {
    final items = <String>[];
    final current = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '\\' && i + 1 < raw.length && raw[i + 1] == ';') {
        current.write(';');
        i++;
      } else if (ch == ';') {
        items.add(unescape(current.toString()).trim());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    if (current.isNotEmpty) items.add(unescape(current.toString()).trim());
    return items.where((s) => s.isNotEmpty).toList();
  }
}

/// Splits an Exec value into a program and its arguments and expands the
/// field codes, launching without files or URLs: `%f %F %u %U` are
/// dropped, `%i` becomes `--icon <icon>`, `%c` the name and `%k` the
/// desktop file's path. Returns null when the line is malformed.
List<String>? parseExec(String exec, {String? icon, String name = '', String path = ''}) {
  final args = <String>[];
  var current = StringBuffer();
  var inWord = false;
  var quoted = false;

  // Field codes outside quotes may stand alone (and then can expand to
  // zero or two words) or sit inside a word; inside quotes they are kept
  // literally, as the spec forbids them there.
  void endWord() {
    if (!inWord) return;
    args.add(current.toString());
    current = StringBuffer();
    inWord = false;
  }

  final standalone = <int, String>{}; // index in args -> field code

  for (var i = 0; i < exec.length; i++) {
    final ch = exec[i];
    if (quoted) {
      if (ch == '"') {
        quoted = false;
      } else if (ch == '\\' && i + 1 < exec.length && '"`\$\\'.contains(exec[i + 1])) {
        current.write(exec[++i]);
      } else {
        current.write(ch);
      }
      continue;
    }
    if (ch == ' ' || ch == '\t' || ch == '\n') {
      endWord();
    } else if (ch == '"') {
      quoted = true;
      inWord = true;
    } else if (ch == '%' && i + 1 < exec.length) {
      final code = exec[++i];
      final alone = !inWord && (i + 1 == exec.length || ' \t\n'.contains(exec[i + 1]));
      if (alone) {
        standalone[args.length] = code;
        args.add('');
        continue;
      }
      inWord = true;
      switch (code) {
        case '%':
          current.write('%');
        case 'c':
          current.write(name);
        case 'k':
          current.write(path);
        default:
          break; // file/URL codes and deprecated ones expand to nothing
      }
    } else {
      current.write(ch);
      inWord = true;
    }
  }
  if (quoted) return null;
  endWord();

  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    final code = standalone[i];
    if (code == null) {
      out.add(args[i]);
      continue;
    }
    switch (code) {
      case '%':
        out.add('%');
      case 'i':
        if (icon != null && icon.isNotEmpty) out.addAll(['--icon', icon]);
      case 'c':
        out.add(name);
      case 'k':
        out.add(path);
      default:
        break;
    }
  }
  return out.isEmpty ? null : out;
}
