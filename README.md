# MysticJam

> **Beta** — still being actively worked on and will have rough edges. Windows and Android support are planned but not available yet (Linux desktop is the only supported platform right now). Feedback and suggestions are welcome via issues.

A local-only Flutter music player for Linux desktop — no accounts, no
streaming, no cloud. Everything lives in your own library on disk.

## Requirements

To build and run on Linux you need:

- [Flutter](https://docs.flutter.dev/get-started/install/linux) (stable channel)
- The Linux build tools: `clang`, `cmake`, `ninja-build`, `pkg-config`,
  `libgtk-3-dev`
- **libmpv** — the app uses it to play audio, and it is not bundled with the
  app, so it must be installed on the system. On Ubuntu/Debian:
  `sudo apt install libmpv2` (or `libmpv-dev` if the build asks for it).
  Package names can differ on other distributions.

## Installing (from a release download)

1. Install libmpv (see above), e.g. `sudo apt install libmpv2`.
2. Download `MysticJam-linux-x64.tar.gz` from the Releases page and extract it.
3. In the extracted folder, run `./install.sh`. This installs for your user
   only (no sudo): MysticJam appears in your app menu with its icon, and the
   `mysticjam` command works from a terminal.
4. To remove it later, run `~/.local/share/mysticjam/uninstall.sh` (your
   library and settings are kept).

You can also skip installing and just run `./mysticjam` from the extracted
folder.

## Development

```sh
flutter pub get
flutter run -d linux
```

Run the test suite:

```sh
flutter test
```

## Building a release

```sh
flutter build linux --release
```

Produces a relocatable bundle at `build/linux/x64/release/bundle/`. You can
run it directly from there:

```sh
./build/linux/x64/release/bundle/mysticjam
```

## Linux packaging (desktop integration)

The Linux runner ships with a `.desktop` file and icon
(`linux/mysticjam.desktop`, `linux/mysticjam.png`) providing:

- An entry in your application menu, named **MysticJam**.
- File-manager associations for the audio formats this app supports (MP3,
  FLAC, WAV, OGG, Opus, M4A/AAC, WMA, APE), so "Open With → MysticJam" works.
- **Single-instance behavior**: launching the app while it's already running
  (from the menu, or by opening another audio file) brings the existing
  window to the front and plays the new file there, rather than starting a
  second process.

These are installed automatically into the release bundle by
`flutter build linux --release` (harmless — they just ride along with the
relocatable bundle). To actually register them with your desktop
environment, install them into your XDG data directories and put the binary
somewhere on `PATH` — the `.desktop` file's `Exec=` line assumes
`mysticjam` is directly runnable by name, which a relocatable bundle
alone doesn't provide:

```sh
flutter build linux --release

# Symlink the binary onto PATH (adjust the source path to wherever you
# actually keep the bundle — this only needs to be done once, or again if
# you move the bundle).
sudo ln -sf "$(pwd)/build/linux/x64/release/bundle/mysticjam" /usr/local/bin/mysticjam

# Install the .desktop file and icon for the current user.
mkdir -p ~/.local/share/applications ~/.local/share/icons/hicolor/192x192/apps
cp linux/mysticjam.desktop ~/.local/share/applications/com.musicplayer.music_player.desktop
cp linux/mysticjam.png ~/.local/share/icons/hicolor/192x192/apps/com.musicplayer.music_player.png

# Refresh the desktop/icon caches so the change is picked up immediately.
update-desktop-database ~/.local/share/applications
gtk-update-icon-cache ~/.local/share/icons/hicolor
```

**Note on the icon:** the app icon is drawn in `linux/mysticjam.svg` and
exported as the 192×192 `linux/mysticjam.png` that gets installed. To change
it, edit the SVG, re-export the PNG at 192×192, and rebuild — nothing else
needs to change, the filename and install path stay the same. (The Android
launcher icons are still the default Flutter ones, since Android isn't
supported yet.)

**Note on a "real" system-wide install (e.g. installing straight to
`/usr`):** this was tried and doesn't work the way you'd expect — running
raw `cmake --build`/`cmake --install` outside of `flutter build linux`
fails, because part of the build (`flutter_assemble`) invokes Flutter's own
tool_backend script, which needs the environment `flutter build`/`flutter
run` set up and errors out without it. Verified directly, not assumed: a
bare `cmake -S linux -B <dir> && cmake --build <dir>` fails with `Unhandled
exception: RangeError` from `tool_backend.dart`. The symlink approach above
is the one that's actually confirmed working — stick with it, or copy the
already-built bundle's contents into `/usr` locations by hand after running
`flutter build linux --release` rather than trying to reconfigure the build
outside Flutter's own tooling.
