# flatkit

Flat Flutter widgets with instant feedback: no ink ripples, no hover or
press highlights that fade, and menus, dialogs and tooltips that appear and
close in a single frame.

- `KitButton` (primary, secondary, ghost, danger) and `KitIconButton`
  (`.compact` for 24px in-row actions)
- `KitSegmented` toggle tabs
- `KitTextField`, with an optional focus node, text style and trailing widget
- `KitMenu` popup menus and `KitSelect`, with arrow keys, Enter and Escape
- `showKitDialog` and `KitDialog`
- `KitTabs` underlined tab strip
- `KitListRow` and `KitSelectionList`, keyboard-driven lists whose
  selection jumps into view
- `KitCheckbox`
- `showKitToast`, a notice at the bottom of the window
- `KitTooltip`, `KitPanel`, `KitDivider`, `KitVerticalDivider`,
  `KitProgressBar`, `KitSpinner`
- `Pressable`, the hover/press/focus primitive the rest are built on

Colours come from `KitTheme` (`KitColors.light` and `KitColors.dark`).
`KitTheme.material(colors)` gives a `ThemeData` with splashes, highlights
and page transitions turned off for anything Material left in your app.
It also sets the text font to Inter, which ships with the kit: it stays
sharp at small sizes where the platform fallback font can look soft. Use
`kitTextStyle` for the same style outside a Material theme.

```dart
MaterialApp(
  theme: KitTheme.material(KitColors.light),
  builder: (context, child) => KitTheme(
    colors: KitColors.light,
    child: Material(color: KitColors.light.background, child: child),
  ),
  home: ...,
);
```

### Following the desktop theme

`KitSystemTheme` picks the colours for you: on KDE Plasma it reads the
colour scheme and accent colour from `kdeglobals` and updates live when you
change them in System Settings; elsewhere it switches between
`KitColors.light` and `KitColors.dark` with the desktop's dark mode.

```dart
KitSystemTheme(
  builder: (context, colors) => MaterialApp(
    theme: KitTheme.material(colors),
    builder: (context, child) =>
        Material(color: colors.background, child: child),
    home: ...,
  ),
);
```

`KdeColors.read()` gives the Plasma colours directly (null off Plasma).
Neither touches `dart:io` on the web, so apps using them still build with
`flutter build web` (they just get the light/dark switch there).

### Matching window decorations

`kde/aurorae` has KWin title bars in the same style, light and dark, so
windows around a flatkit app look like part of it. See
[kde/aurorae/README.md](kde/aurorae/README.md) to install them.

## Launcher

[launcher/](launcher/README.md) is a keyboard-driven application launcher
for KDE Plasma built with the kit: fuzzy search over installed apps, desktop
actions, a calculator and a run-command fallback, in Plasma's colours and
icon theme. `launcher/install.sh --meta` builds and installs it and puts it
on the Meta key.

## Using it with pixi

flatkit builds as a conda package with pixi. Installing it puts the Dart
package at `$CONDA_PREFIX/share/flatkit`. In your app's `pixi.toml`:

```toml
[workspace]
channels = ["conda-forge"]
platforms = ["linux-64"]
preview = ["pixi-build"]

[dependencies]
flatkit = { git = "https://github.com/codegod100/flutterkit", branch = "main" }
```

and in `pubspec.yaml`:

```yaml
dependencies:
  flatkit:
    path: .pixi/envs/default/share/flatkit
```

Run `pixi install` before `flutter pub get`; `pixi update flatkit` picks up
new commits.

## Developing

```sh
flutter test
pixi build   # builds the conda package
```
