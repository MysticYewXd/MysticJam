#!/bin/sh
# Installs MysticJam for the current user only (no sudo needed): copies the
# app to ~/.local/share/mysticjam, adds an app-menu entry with the icon, and
# a `mysticjam` command in ~/.local/bin. Safe to run again to update.
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/mysticjam"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/192x192/apps"
BIN="$HOME/.local/bin"
ID="com.musicplayer.music_player"

if ! ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; then
  echo "Warning: libmpv was not found. MysticJam needs it to play audio."
  echo "  Ubuntu/Debian:  sudo apt install libmpv2"
fi

mkdir -p "$DEST" "$APPS" "$ICONS" "$BIN"

# Skip the copy when run from the install location itself, so a re-run there
# can't delete its own source.
if [ "$SRC" != "$DEST" ]; then
  rm -rf "$DEST/data" "$DEST/lib"
  cp -a "$SRC/mysticjam" "$SRC/data" "$SRC/lib" "$DEST/"
  cp "$SRC/uninstall.sh" "$DEST/uninstall.sh"
fi

cp "$SRC/share/icons/hicolor/192x192/apps/$ID.png" "$ICONS/$ID.png"
sed "s|^Exec=.*|Exec=$DEST/mysticjam %U|" \
  "$SRC/share/applications/$ID.desktop" > "$APPS/$ID.desktop"
ln -sf "$DEST/mysticjam" "$BIN/mysticjam"

update-desktop-database "$APPS" 2>/dev/null || true
gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "MysticJam installed. Open it from your app menu (search \"MysticJam\")."
echo "If it doesn't appear right away, log out and back in once."
