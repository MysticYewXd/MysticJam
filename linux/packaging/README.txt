MysticJam - local-only music player for Linux (beta)

Install (no sudo needed):
  1. Install libmpv, which plays the audio and is not bundled:
       Ubuntu/Debian:  sudo apt install libmpv2
       Fedora:         sudo dnf install mpv-libs
       Arch:           sudo pacman -S mpv
  2. In this folder, run:  ./install.sh
     (or right-click install.sh -> "Run as a Program")
  3. Open "MysticJam" from your app menu.

Or just run it without installing: ./mysticjam

To remove it later: ~/.local/share/mysticjam/uninstall.sh
(your library and settings are kept unless you delete
 ~/.local/share/com.musicplayer.music_player)

Needs a 64-bit Linux desktop with GTK 3. Built on Ubuntu, so it may not run
on a distribution with a much older system (glibc).
