#!/bin/sh
# Builds the launcher and installs it for the current user:
#   ~/.local/share/flatkit-launcher/   the app bundle
#   ~/.local/bin/flatkit-launcher      a link to it
#   ~/.local/share/applications/dev.flatkit.Launcher.desktop
#   ~/.config/autostart/dev.flatkit.Launcher.desktop   (starts it hidden)
#
#   ./install.sh                     build and install
#   ./install.sh --shortcut Meta+Space   also bind a global shortcut
#   ./install.sh --uninstall
set -eu

cd "$(dirname "$0")"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
bin="$HOME/.local/bin"
id=dev.flatkit.Launcher
shortcut=""

while [ $# -gt 0 ]; do
  case "$1" in
    --shortcut) shortcut="$2"; shift 2 ;;
    --uninstall)
      "$bin/flatkit-launcher" --quit 2>/dev/null || true
      rm -rf "$data/flatkit-launcher" "$bin/flatkit-launcher" \
        "$data/applications/$id.desktop" "$config/autostart/$id.desktop"
      echo "Uninstalled."
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

flutter build linux --release

# Stop a running copy so the new build is what starts next.
"$bin/flatkit-launcher" --quit 2>/dev/null || true

rm -rf "$data/flatkit-launcher"
mkdir -p "$data/flatkit-launcher" "$bin" "$data/applications" "$config/autostart"
cp -r build/linux/x64/release/bundle/. "$data/flatkit-launcher/"
ln -sf "$data/flatkit-launcher/flatkit-launcher" "$bin/flatkit-launcher"

cat > "$data/applications/$id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Launcher
GenericName=Application Launcher
Comment=Search and start applications
Exec=$bin/flatkit-launcher
Icon=system-search
Terminal=false
Categories=Utility;
StartupNotify=false
DESKTOP

cat > "$config/autostart/$id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Launcher
Exec=$bin/flatkit-launcher --hidden
Icon=system-search
NoDisplay=true
X-KDE-autostart-phase=2
DESKTOP

if [ -n "$shortcut" ]; then
  kwrite=$(command -v kwriteconfig6 || command -v kwriteconfig5 || true)
  if [ -z "$kwrite" ]; then
    echo "kwriteconfig6 not found; set the shortcut in System Settings instead." >&2
  else
    "$kwrite" --file kglobalshortcutsrc --group services --group "$id.desktop" \
      --key _launch "$shortcut"
    echo "Bound $shortcut. Log out and back in (or restart kglobalaccel) for it to take effect."
  fi
fi

# Start it in the background now, so the first shortcut press is instant.
nohup "$bin/flatkit-launcher" --hidden >/dev/null 2>&1 &

echo "Installed. Run flatkit-launcher (or your shortcut) to open it."
