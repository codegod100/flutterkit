#!/bin/sh
# Builds the KDE Store archives: store/Flatkit.tar.gz and store/Flatkit-Dark.tar.gz.
# Each holds one theme folder, the layout "Get New Window Decorations" installs.
set -e
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$here/store"
for theme in Flatkit Flatkit-Dark; do
  tmp=$(mktemp -d)
  cp -r "$here/themes/$theme" "$tmp/$theme"
  cp "$here/LICENSE" "$tmp/$theme/LICENSE"
  tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 \
    -C "$tmp" -cf - "$theme" | gzip -n -9 > "$here/store/$theme.tar.gz"
  rm -rf "$tmp"
  echo "wrote $here/store/$theme.tar.gz"
done
