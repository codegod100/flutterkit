# KDE Store release

Upload-ready files for [store.kde.org](https://store.kde.org), one product
per theme. Rebuild them after changing the themes:

```sh
python3 kde/aurorae/generate.py
QT_QPA_PLATFORM=offscreen python3 kde/aurorae/preview.py   # store/*.png
kde/aurorae/package.sh                                     # store/*.tar.gz
```

| Product      | File                  | Screenshot         |
|--------------|-----------------------|--------------------|
| Flatkit      | `Flatkit.tar.gz`      | `Flatkit.png`      |
| Flatkit Dark | `Flatkit-Dark.tar.gz` | `Flatkit-Dark.png` |

## Uploading

1. Sign in at store.kde.org (a KDE Store / Pling account).
2. Click **Add Product** (the + in the top bar).
3. Category: **Plasma Themes & Addons → Window Decorations → Aurorae Themes**.
   This is the category Plasma's *Get New Window Decorations* reads, so the
   theme becomes installable from System Settings.
4. Fill in the fields below, attach the screenshot as the logo/gallery image,
   then save.
5. On the product's **Files** tab, upload the `.tar.gz`. Leave the file
   version at `1.0` to match `metadata.desktop`.
6. Repeat for the second theme.

When releasing an update, bump `X-KDE-PluginInfo-Version` in `generate.py`,
rebuild, and upload the new archive on the existing product's Files tab.

## Flatkit

- **Title:** Flatkit
- **License:** MIT
- **Source / homepage:** https://github.com/codegod100/flutterkit
- **Tags:** flat, minimal, light, aurorae
- **Summary:** A flat, quiet light window decoration with rounded top corners and a red-on-hover close button.
- **Description:**

  Flatkit is a flat Aurorae window decoration taken from the flatkit Flutter
  widget kit, so KDE windows match apps built with it.

  - Light title bar with a 1px outline, 10px rounded top corners and a hairline under the title
  - 24px flat buttons with subtle hover and pressed states; close turns red on hover
  - Minimize, maximize/restore, close, keep above/below, on all desktops, shade and help
  - No animations: buttons change state instantly

  Recommended: Border size **Tiny**, window title font **Inter SemiBold 10pt**.

  A dark variant is available as **Flatkit Dark**.

## Flatkit Dark

- **Title:** Flatkit Dark
- **License:** MIT
- **Source / homepage:** https://github.com/codegod100/flutterkit
- **Tags:** flat, minimal, dark, aurorae
- **Summary:** A flat, quiet dark window decoration with rounded top corners and a red-on-hover close button.
- **Description:**

  Flatkit Dark is a flat Aurorae window decoration taken from the flatkit
  Flutter widget kit, so KDE windows match apps built with it.

  - Dark title bar with a 1px outline, 10px rounded top corners and a hairline under the title
  - 24px flat buttons with subtle hover and pressed states; close turns red on hover
  - Minimize, maximize/restore, close, keep above/below, on all desktops, shade and help
  - No animations: buttons change state instantly

  Recommended: Border size **Tiny**, window title font **Inter SemiBold 10pt**.

  A light variant is available as **Flatkit**.
