import 'dart:isolate';

import 'package:flatkit/flatkit.dart';
import 'package:flutter/material.dart';

import 'src/apps.dart';
import 'src/desktop_entry.dart';
import 'src/icons.dart';
import 'src/launcher_view.dart';
import 'src/window.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LauncherApp());
}

class LauncherApp extends StatefulWidget {
  const LauncherApp({super.key});

  @override
  State<LauncherApp> createState() => _LauncherAppState();
}

class _LauncherAppState extends State<LauncherApp> {
  final _view = GlobalKey<LauncherViewState>();
  final _history = LaunchHistory.load();
  List<DesktopEntry> _apps = const [];
  IconIndex _icons = IconIndex.empty();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    LauncherWindow.listen(
      onShown: () {
        _view.currentState?.focusSearch();
        _load();
      },
      // Reset while hidden, so the next show starts from a clean slate
      // without drawing a stale frame first.
      onHidden: () => _view.currentState?.reset(),
    );
    _load();
  }

  /// Rescans applications and icons off the UI thread. Runs at start and
  /// on every show, so newly installed apps turn up without a restart.
  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final results = await Future.wait([
        Isolate.run(() => scanApplications()),
        IconIndex.build(),
      ]);
      if (!mounted) return;
      setState(() {
        _apps = results[0] as List<DesktopEntry>;
        _icons = results[1] as IconIndex;
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return KitSystemTheme(
      builder: (context, colors) => MaterialApp(
        title: 'Launcher',
        debugShowCheckedModeBanner: false,
        theme: KitTheme.material(colors),
        builder: (context, child) => Material(
          color: colors.background,
          child: DefaultTextStyle(style: kitTextStyle.copyWith(color: colors.text), child: child!),
        ),
        home: LauncherView(
          key: _view,
          apps: _apps,
          icons: _icons,
          history: _history,
          services: LauncherServices(
            launchApp: (entry, action) => launch(entry, action: action),
            runCommand: (command, terminal) => runCommand(command, terminal: terminal),
            hide: LauncherWindow.hide,
          ),
        ),
      ),
    );
  }
}
