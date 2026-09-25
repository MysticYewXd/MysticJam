# MysticJam

## VIBECODED WITH CLAUDE

> **Beta** — still being actively worked on and will have rough edges. Linux desktop is the main supported platform. A Windows build exists but is **experimental** (see below), and Android is planned but not available yet. Feedback and suggestions are welcome via issues.

A local-only Flutter music player for desktop — no accounts, no
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

### Windows (experimental)

`MysticJam-windows-x64.zip` is built automatically by GitHub Actions (see
`.github/workflows/build-windows.yml`) — from the repo's **Actions** tab, open
the latest "Build Windows" run and download the zip under *Artifacts*, or
take it from a release once one is attached. Extract it and run
`mysticjam.exe`; nothing else needs to be installed (the audio engine is
bundled). Windows SmartScreen may warn about an unrecognised app because the
build isn't code-signed — choose *More info → Run anyway*.

This build has not been tested on a real Windows machine yet, so expect
things to be rough. Your library and settings are stored under
`%APPDATA%\MysticJam\MysticJam` and are kept if you delete the app folder.

## Development

```sh
flutter pub get
flutter run -d linux
