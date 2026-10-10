# flatkit launcher

A keyboard-driven application launcher for KDE Plasma, built with
[flatkit](..). Press a shortcut, type a few letters, hit Enter.

- Finds every installed application from its `.desktop` file (system,
  `~/.local/share/applications`, Flatpak and Snap), skipping ones hidden
  from Plasma and ones whose program isn't installed
- Fuzzy search over names, generic names ("browser", "terminal"),
  keywords and the command, with matched letters highlighted
- Apps you start often and recently rise to the top
- Desktop actions: Tab (or →) on an app lists entries like "New Private
  Window"
- Arithmetic as you type: `12*7+1` shows `= 85`, Enter copies it
- Anything else runs as a shell command; Ctrl+Enter runs it in your
  terminal (KDE's configured one, else Konsole)
- Plasma's colour scheme, accent colour and icon theme, updated live
- Stays resident and hidden, so it opens instantly; it hides again when
  it loses focus

| Key | Does |
| --- | --- |
| ↑ ↓, Ctrl+N/P, Ctrl+J/K | Move the selection |
| Page Up/Down | Move by a page |
| Enter | Open the selection |
| Alt+1 … Alt+9 | Open that row |
| Tab, → | Show the app's actions |
| Shift+Tab, ←, Esc | Back from actions |
| Ctrl+Enter | Run the text in a terminal |
| Esc | Close |

## Install

Needs Flutter and the Linux desktop build dependencies (`clang cmake
ninja-build pkg-config libgtk-3-dev`, plus `libgtk-layer-shell-dev` for the
Wayland overlay, see below).

```sh
cd launcher
./install.sh --meta
```

This builds a release, installs it under `~/.local`, adds it to autostart
(started hidden) and makes the Meta (Windows) key, pressed on its own, open
the launcher instead of Plasma's application menu. It takes effect at once.
KWin calls the launcher's `dev.flatkit.Launcher.Toggle` D-Bus method for
this, set in `kwinrc`:

```ini
[ModifierOnlyShortcuts]
Meta=dev.flatkit.Launcher,/dev/flatkit/Launcher,dev.flatkit.Launcher,Toggle
```

A D-Bus service file starts the launcher on demand if it isn't running yet.

To use a key combination instead, `./install.sh --shortcut Meta+Space` (log
out and in once for it to register), or bind one in System Settings →
Keyboard → Shortcuts → Add New → Application → "Launcher".

`./install.sh --uninstall` removes it all again and gives the Meta key back
to Plasma's menu.

## How it runs

The first `flatkit-launcher` starts the app and shows the window. Running
it again (which is what the shortcut does) toggles the window of the copy
already running, over D-Bus, as does calling
`dev.flatkit.Launcher.Toggle` on `/dev/flatkit/Launcher`. Flags:

- `--hidden`: start without showing the window (used by autostart)
- `--quit`: stop the running copy

On Wayland, when built with gtk-layer-shell, the launcher is a layer-shell
overlay: KWin centres it over everything and gives it the keyboard. Set
`FLATKIT_LAUNCHER_NO_LAYER_SHELL=1` to get a plain window instead. On X11,
or without gtk-layer-shell, it is an undecorated, always-on-top window
centred on screen.

Launch history is kept in `~/.local/state/flatkit-launcher/history.json`.

## Developing

```sh
flutter test
flutter run -d linux
```

`lib/src` holds the pieces: `desktop_entry.dart` (desktop file and Exec
parsing), `apps.dart` (scanning, ranking, history, launching),
`fuzzy.dart`, `icons.dart` (icon theme lookup), `calc.dart` and
`launcher_view.dart` (the UI). The window behaviour lives in
`linux/runner/my_application.cc`.
