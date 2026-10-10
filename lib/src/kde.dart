/// Picks up the KDE Plasma colour scheme from kdeglobals, and follows the
/// desktop's light/dark setting everywhere else.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'platform/kde_stub.dart' if (dart.library.io) 'platform/kde_io.dart';
import 'theme.dart';

/// Reads KDE's colour scheme from kdeglobals.
class KdeColors {
  KdeColors._();

  /// Whether [environment] (the process environment by default) belongs to
  /// a Plasma session.
  static bool isKde([Map<String, String>? environment]) {
    final env = environment ?? platformEnvironment();
    if (env['KDE_FULL_SESSION'] == 'true') return true;
    final desktops = (env['XDG_CURRENT_DESKTOP'] ?? '').toUpperCase().split(':');
    return desktops.contains('KDE');
  }

  /// `$XDG_CONFIG_HOME/kdeglobals`, or `~/.config/kdeglobals`.
  static String? path([Map<String, String>? environment]) {
    final env = environment ?? platformEnvironment();
    var config = env['XDG_CONFIG_HOME'] ?? '';
    if (config.isEmpty) {
      final home = env['HOME'] ?? '';
      if (home.isEmpty) return null;
      config = '$home/.config';
    }
    return '$config/kdeglobals';
  }

  /// The colours of the running Plasma session, or null when this isn't
  /// Plasma or kdeglobals has no colour scheme in it.
  static KitColors? read([Map<String, String>? environment]) {
    if (!platformIsLinux && environment == null) return null;
    if (!isKde(environment)) return null;
    final p = path(environment);
    if (p == null) return null;
    final contents = readFile(p);
    return contents == null ? null : parse(contents);
  }

  /// Maps the contents of a kdeglobals file onto [KitColors]. Returns null
  /// when it has no `[Colors:Window]` group. Keys a scheme leaves out come
  /// from [KitColors.light] or [KitColors.dark], whichever matches the
  /// scheme's window background.
  static KitColors? parse(String kdeglobals) {
    final ini = _parseIni(kdeglobals);
    final window = ini['Colors:Window'];
    if (window == null) return null;

    Color? get(String group, String key) => _color(ini[group]?[key]);

    final background = _color(window['BackgroundNormal']);
    if (background == null) return null;
    final dark = background.computeLuminance() < 0.5;
    final base = dark ? KitColors.dark : KitColors.light;

    final surface = get('Colors:Button', 'BackgroundNormal') ??
        get('Colors:View', 'BackgroundNormal') ??
        base.surface;
    final text = _color(window['ForegroundNormal']) ?? base.text;
    final textDim = _color(window['ForegroundInactive']) ?? Color.lerp(background, text, 0.6)!;
    final accent = get('General', 'AccentColor') ??
        get('Colors:Selection', 'BackgroundNormal') ??
        get('Colors:View', 'DecorationFocus') ??
        base.accent;
    final onAccent = get('Colors:Selection', 'ForegroundNormal') ?? _onColor(accent);
    final danger = get('Colors:View', 'ForegroundNegative') ??
        _color(window['ForegroundNegative']) ??
        base.danger;
    final success = get('Colors:View', 'ForegroundPositive') ??
        _color(window['ForegroundPositive']) ??
        base.success;
    final focus = get('Colors:View', 'DecorationFocus') ?? accent;

    // Hover and press states stay neutral tints of the surface, as the rest
    // of the kit draws them; accent and danger states shift towards the
    // text colour so they read on either kind of scheme.
    return KitColors(
      brightness: dark ? Brightness.dark : Brightness.light,
      background: background,
      surface: surface,
      hover: Color.lerp(surface, text, 0.07)!,
      pressed: Color.lerp(surface, text, 0.14)!,
      border: Color.lerp(background, text, 0.18)!,
      borderStrong: Color.lerp(background, text, 0.35)!,
      text: text,
      textDim: textDim,
      accent: accent,
      accentHover: Color.lerp(accent, text, 0.12)!,
      accentPressed: Color.lerp(accent, text, 0.24)!,
      onAccent: onAccent,
      danger: danger,
      dangerHover: Color.lerp(danger, text, 0.12)!,
      onDanger: _onColor(danger),
      success: success,
      focus: focus,
      shadow: base.shadow,
    );
  }

  static Map<String, Map<String, String>> _parseIni(String s) {
    final groups = <String, Map<String, String>>{};
    Map<String, String>? current;
    for (var line in s.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        current = groups.putIfAbsent(line.substring(1, line.length - 1), () => {});
        continue;
      }
      final eq = line.indexOf('=');
      if (current == null || eq < 0) continue;
      var key = line.substring(0, eq).trim();
      // Drop KConfig's [$e]/[$i] flags and locale suffixes.
      final bracket = key.indexOf('[');
      if (bracket >= 0) key = key.substring(0, bracket);
      current[key] = line.substring(eq + 1).trim();
    }
    return groups;
  }

  /// KConfig colours are `r,g,b`, `r,g,b,a` or `#rrggbb`.
  static Color? _color(String? v) {
    if (v == null || v.isEmpty) return null;
    if (v.startsWith('#')) {
      final hex = v.substring(1);
      final n = int.tryParse(hex, radix: 16);
      if (n == null) return null;
      if (hex.length == 6) return Color(0xFF000000 | n);
      if (hex.length == 8) return Color(n); // KConfig writes #aarrggbb
      return null;
    }
    final parts = v.split(',').map((p) => int.tryParse(p.trim())).toList();
    if (parts.length < 3 || parts.length > 4 || parts.contains(null)) return null;
    int ch(int i) => parts[i]!.clamp(0, 255);
    return Color.fromARGB(parts.length == 4 ? ch(3) : 255, ch(0), ch(1), ch(2));
  }

  static Color _onColor(Color c) =>
      c.computeLuminance() > 0.45 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}

/// Gives its subtree the desktop's colours: the KDE colour scheme on
/// Plasma, updated live when it changes, and otherwise [light] or [dark]
/// following the platform's brightness setting.
///
/// Place it above `MaterialApp` and build the app from the colours:
///
/// ```dart
/// KitSystemTheme(
///   builder: (context, colors) => MaterialApp(
///     theme: KitTheme.material(colors),
///     home: ...,
///   ),
/// )
/// ```
///
/// The colours are also provided as a [KitTheme] around what [builder]
/// returns.
class KitSystemTheme extends StatefulWidget {
  final Widget Function(BuildContext context, KitColors colors) builder;
  final KitColors light;
  final KitColors dark;

  /// Turns KDE detection off, leaving just the light/dark switch.
  final bool followKde;

  /// Stands in for the process environment, for tests.
  final Map<String, String>? environment;

  const KitSystemTheme({
    super.key,
    required this.builder,
    this.light = KitColors.light,
    this.dark = KitColors.dark,
    this.followKde = true,
    this.environment,
  });

  @override
  State<KitSystemTheme> createState() => _KitSystemThemeState();
}

class _KitSystemThemeState extends State<KitSystemTheme> with WidgetsBindingObserver {
  KitColors? _kde;
  StreamSubscription<void>? _watch;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didUpdateWidget(KitSystemTheme old) {
    super.didUpdateWidget(old);
    if (old.followKde != widget.followKde || old.environment != widget.environment) {
      _stop();
      _start();
    }
  }

  void _start() {
    _kde = null;
    if (!widget.followKde) return;
    final env = widget.environment;
    if (!(env != null || platformIsLinux) || !KdeColors.isKde(env)) return;
    _kde = KdeColors.read(env);
    final path = KdeColors.path(env);
    if (path == null) return;
    _watch = watchFile(path)?.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), _reload);
    });
  }

  void _reload() {
    if (!mounted) return;
    final colors = KdeColors.read(widget.environment);
    // Keep what we have if the file was caught half-written.
    if (colors != null) setState(() => _kde = colors);
  }

  void _stop() {
    _debounce?.cancel();
    _watch?.cancel();
    _watch = null;
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _kde ??
        (WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark
            ? widget.dark
            : widget.light);
    return KitTheme(
        colors: colors, child: Builder(builder: (context) => widget.builder(context, colors)));
  }
}
