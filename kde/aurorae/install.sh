#!/bin/sh
# Installs the Flatkit window decorations for the current user.
#   ./install.sh          copy the themes
#   ./install.sh --apply  copy them and switch KWin to Flatkit (light)
#   ./install.sh --apply dark
set -e
here=$(cd "$(dirname "$0")" && pwd)
dest="${XDG_DATA_HOME:-$HOME/.local/share}/aurorae/themes"
mkdir -p "$dest"
for theme in Flatkit Flatkit-Dark; do
  rm -rf "$dest/$theme"
  cp -r "$here/themes/$theme" "$dest/$theme"
  echo "installed $dest/$theme"
done

if [ "$1" = "--apply" ]; then
  theme=Flatkit
  [ "$2" = "dark" ] && theme=Flatkit-Dark
  kwc=$(command -v kwriteconfig6 || command -v kwriteconfig5)
  "$kwc" --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
  "$kwc" --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__$theme"
  qdbus=$(command -v qdbus6 || command -v qdbus || true)
  if [ -n "$qdbus" ]; then
    "$qdbus" org.kde.KWin /KWin reconfigure
  else
    dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure
  fi
  echo "KWin now uses $theme"
fi
