#!/bin/sh
# Removes what install.sh added. Your music library and settings are kept.
set -e

ID="com.musicplayer.music_player"

rm -f "$HOME/.local/bin/mysticjam" \
  "$HOME/.local/share/applications/$ID.desktop" \
  "$HOME/.local/share/icons/hicolor/192x192/apps/$ID.png"
rm -rf "$HOME/.local/share/mysticjam"

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "MysticJam removed."
echo "Your library and settings are still in ~/.local/share/$ID"
echo "(delete that folder as well if you want them gone too)."
