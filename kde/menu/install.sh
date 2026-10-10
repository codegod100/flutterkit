#!/bin/sh
# Installs (or updates) the Flatkit Menu Plasma widget for the current user.
#
#   ./install.sh               install or update
#   ./install.sh --uninstall   remove it
#
# Then swap it in for the current menu: right-click the application menu in
# your panel, choose "Show Alternatives…", pick "Flatkit Menu". It takes the
# old menu's place, and the Meta key opens it.
set -eu

cd "$(dirname "$0")"
id=dev.flatkit.menu
kpackage=$(command -v kpackagetool6 || true)
if [ -z "$kpackage" ]; then
  echo "kpackagetool6 not found; this needs Plasma 6." >&2
  exit 1
fi

if [ "${1:-}" = "--uninstall" ]; then
  "$kpackage" -t Plasma/Applet --remove "$id"
  exit 0
fi

# Copy the package in place ourselves (what kpackagetool6 does), so an
# update always replaces every file.
dest="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$id"
updated=""
[ -d "$dest" ] && updated=1
rm -rf "$dest"
mkdir -p "$dest"
cp -r package/. "$dest/"
version=$(sed -n 's/.*"Version": "\(.*\)".*/\1/p' "$dest/metadata.json")
echo "Flatkit Menu $version is in $dest"

# The standalone launcher's installer (launcher/install.sh --meta) points
# the Meta key straight at that app. Hand Meta back to Plasma so it opens
# this menu instead.
kread=$(command -v kreadconfig6 || true)
kwrite=$(command -v kwriteconfig6 || true)
if [ -n "$kread" ] && [ -n "$kwrite" ] &&
  [ "$("$kread" --file kwinrc --group ModifierOnlyShortcuts --key Meta)" = \
    "dev.flatkit.Launcher,/dev/flatkit/Launcher,dev.flatkit.Launcher,Toggle" ]; then
  "$kwrite" --file kwinrc --group ModifierOnlyShortcuts --key Meta --delete
  gdbus call --session --dest org.kde.KWin --object-path /KWin \
    --method org.kde.KWin.reconfigure >/dev/null 2>&1 || true
  echo "Meta opens Plasma's launcher menu again."
fi

if [ -n "$updated" ]; then
  # Plasma keeps compiled QML around; drop it so the new files are what
  # loads, then restart the shell.
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell/qmlcache"
  # kquitapp6 + kstart is what reliably restarts the shell; restarting the
  # systemd unit can leave the old shell running.
  if command -v kquitapp6 >/dev/null && command -v kstart >/dev/null; then
    kquitapp6 plasmashell >/dev/null 2>&1 || true
    kstart plasmashell >/dev/null 2>&1 || true
    echo "Updated and restarted Plasma."
  else
    echo "Updated. Log out and back in to load the new version."
  fi
else
  echo "Installed. Right-click your application menu → Show Alternatives… → Flatkit Menu."
fi
