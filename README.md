<div align="center">

<img src="linux/mysticjam.svg" width="96" alt="MysticJam logo">

# MysticJam-V1_stable

**Your music, on your machine. Nothing else.**

A local-only music player for the desktop, built with Flutter.<br>
No accounts, no streaming, no cloud, no tracking. It plays the music files you already have.

<sub>Linux first &nbsp;·&nbsp; Windows beta &nbsp;·&nbsp; Version 1 (stable)</sub>

</div>

<!-- Add a screenshot here once you have one:
<p align="center"><img src="assets/screenshot.png" width="720" alt="MysticJam playing an album"></p>
-->

> [!NOTE]
> **This is MysticJam Version 1, the first stable release.** Linux is the main platform, Windows has a beta build, and Android is planned but not available yet. Bug reports and ideas are very welcome in [Issues](https://github.com/MysticYewXd/MysticJam/issues).

---

## Contents

- [Features](#features)
- [What's new in Version 1](#whats-new-in-version-1)
- [Supported formats](#supported-formats)
- [Install on Linux](#install-on-linux)
  - [Step 1: Install libmpv](#step-1-install-libmpv)
  - [Step 2: Download and install MysticJam](#step-2-download-and-install-mysticjam)
- [Install on Windows (beta)](#install-on-windows-beta)
- [Using it](#using-it)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Themes and Look & Feel](#themes-and-look--feel)
- [Privacy](#privacy)
- [Where your data lives](#where-your-data-lives)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Building from source](#building-from-source)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Features

| | |
|---|---|
| **Your library** | Browse by artist, album, genre and folder, with search across everything. Rescan any time to pick up new songs and refreshed tags. |
| **Playlists and queue** | Build playlists, line up a play queue, shuffle, and repeat one or all. A **Recently played** list remembers where you've been. |
| **Fast scanning** | The library scanner is written in Rust and reads many songs at once, so even big libraries are added quickly. Oversized cover images are shrunk once, so browsing stays light on memory. |
| **Synced lyrics** | Reads `.lrc` files that sit next to your songs, or lyrics embedded in any format (FLAC, MP3, Opus, M4A and more). Lines follow the music, and you can tap a line to jump there. Duets show the second voice on the other side, in its own colour. |
| **Disc player** | An optional Now Playing style: a spinning disc you can drag to scrub, hardware-style keys, and an OLED panel with the album's songs, a live volume slider and a seek bar. |
| **Album colours** | The player can tint itself with the colours of the current album art. |
| **Themes** | A theme editor for colours, typography and shape, four starter presets to remix, and a light mode. |
| **Desktop integration** | On Linux, MysticJam shows up in your desktop's media controls and responds to media keys (MPRIS); clicking it there brings the window to the front. Its volume sliders follow your volume keys and desktop volume control. Files can be opened with MysticJam from your file manager. |
| **Keyboard friendly** | Play, pause, seek, skip and change volume without touching the mouse. |
| **Queue control** | Reorder the queue by dragging, or remove a song with one click. |
| **Undo** | Deleted something by mistake? <kbd>Ctrl</kbd>+<kbd>Z</kbd> brings it back. |
| **Private by design** | Works fully offline. The only network feature is an optional lyrics lookup, which you can switch off. |

---

## What's new in Version 1

- **Rust-powered library scanning:** reading your music is several times faster and runs on all CPU cores.
- **Lyrics from every format:** embedded lyrics are now found in FLAC, Opus, OGG, M4A, MP4, WAV, AAC, APE and WMA, not just MP3. Timed lyrics stored inside the file are recognised as synced.
- **Cleaner lyrics:** word-by-word timing codes and singer markers (common in Apple Music lyrics) are hidden, duet lines are styled by voice, and `[instrumental:true]` markers are no longer shown as lyrics.
- **Disc player:** a spinning-disc Now Playing view with a live volume slider and a seek bar; the album's entrance effect plays when the album changes, not on every skip.
- **Artists credited properly:** songs with several artists show them all (for example *Kanye West, Ye*), and albums split by inconsistent tags are joined back together.
- **Volume that keeps up:** the sliders change the volume while you drag, and follow your volume keys and desktop volume control on Linux.
- **Queue:** remove songs from the queue with the ✕ button.
- **Lighter on memory:** oversized embedded covers are stored at a sensible size.
- **App log:** a small, privacy-safe log to help with bug reports (no song names or paths).

---

## Supported formats

| Format | Plays | Reads tags (artist, album, art) |
|---|:---:|:---:|
| MP3 | ✅ | ✅ |
| FLAC | ✅ | ✅ |
| OGG Vorbis | ✅ | ✅ |
| Opus | ✅ | ✅ |
| M4A / AAC | ✅ | ✅ |
| WMA | ✅ | ✅ |
| APE | ✅ | ✅ |
| WAV | ✅ | ✅ |
| Audio inside MP4, MOV | ✅ | ✅ |
| Audio inside MKV, WEBM, AVI | ✅ | ➖ uses the file name |

Embedded lyrics are read from every format above that has tags, plus `.lrc` files next to any song.

---

## Install on Linux

You need a 64-bit Linux desktop with GTK 3. Installing takes a minute and needs no `sudo` for MysticJam itself.

### Step 1: Install libmpv

MysticJam plays audio through **libmpv**, which is not bundled with the Linux build, so install it first. Pick your distro:

<details open>
<summary><b>Arch Linux, CachyOS, EndeavourOS, Manjaro, Garuda</b></summary>

```sh
sudo pacman -S --needed mpv
```

On Arch, libmpv comes with the `mpv` package.

</details>

<details>
<summary><b>Ubuntu, Debian, Linux Mint, Pop!_OS</b></summary>

```sh
sudo apt install libmpv2
```

</details>

<details>
<summary><b>Fedora</b></summary>

```sh
sudo dnf install mpv-libs
```

</details>

<details>
<summary><b>openSUSE</b></summary>

```sh
sudo zypper install libmpv2
```

</details>

<details>
<summary><b>Any other distro</b></summary>

Install whichever package provides **`libmpv.so.2`**. You can check that it's found with:

```sh
ldconfig -p | grep libmpv
```

</details>

> [!TIP]
> The installer checks for libmpv and prints a warning if it can't find it, so you'll know straight away if this step was missed.

### Step 2: Download and install MysticJam

1. Download **`MysticJam-linux-x64.tar.gz`** from the [Releases page](https://github.com/MysticYewXd/MysticJam/releases).
2. Extract it:

   ```sh
   tar -xzf MysticJam-linux-x64.tar.gz
   ```

3. Open a terminal in the extracted folder and run the installer:

   ```sh
   ./install.sh
   ```

4. Open **MysticJam** from your app menu. If it doesn't appear straight away, log out and back in once.

The installer sets things up for your user only:

| What | Where |
|---|---|
| The app | `~/.local/share/mysticjam` |
| App menu entry and icon | `~/.local/share/applications` and `~/.local/share/icons` |
| The `mysticjam` terminal command | `~/.local/bin/mysticjam` |

<details>
<summary>Just want to try it without installing?</summary>

Run it straight from the extracted folder:

```sh
./mysticjam
```

</details>

> [!NOTE]
> The release is built on Ubuntu, so it may not start on a distribution with a much older system. Building from source (see [below](#building-from-source)) works around that.

---

## Install on Windows (beta)

1. Download **`MysticJam-windows-x64.zip`** from the [Releases page](https://github.com/MysticYewXd/MysticJam/releases).
2. Extract it anywhere you like.
3. Run **`mysticjam.exe`**.

Nothing else needs installing; on Windows the audio engine is bundled.

> [!WARNING]
> The Windows build isn't code-signed, so **SmartScreen may warn** about an unrecognised app. Choose **More info → Run anyway**.

> [!NOTE]
> The Windows build has been tested on Windows 11. It is built automatically by GitHub Actions, and some desktop features (MPRIS media controls, "Open with" from the file manager) are Linux only for now.

---

## Using it

1. **Add your music.** In the library, use **Add Folder** or **Add Files**.
2. **Browse.** Find songs by artist, album, genre or folder, or search for anything.
3. **Play.** Pick a song, and the mini player and dock keep it at hand while you browse. Open **Now Playing** for the full player, the queue and lyrics.
4. **Keep it fresh.** Hit **Rescan library** after adding new music to a folder you've already added, or **Refresh Metadata** (the refresh icon in the Library) after changing your songs' tags.
5. **Try the disc player.** In Now Playing, use the disc button in the top bar (or **Settings → Look & Feel**) to switch between the classic view and the spinning disc.

> [!TIP]
> Your music files are never moved, changed or deleted. **Clear Library** in Settings only forgets them; the files on disk stay exactly where they are.

### Lyrics

MysticJam looks for lyrics in this order:

1. A `.lrc` file next to the song with the same name, for example `Song.mp3` and `Song.lrc`.
2. Lyrics embedded in the song's tags, synced (timed) first, then plain.
3. If **Look up missing lyrics online** is on, a one-time lookup on [lrclib.net](https://lrclib.net). Whatever it finds is saved, so it never asks twice.

Added `.lrc` files later? Use **Settings → Look & Feel → Rescan lyrics**.

---

## Keyboard shortcuts

| Key | What it does |
|---|---|
| <kbd>Space</kbd> | Play / pause |
| <kbd>←</kbd> <kbd>→</kbd> | Seek back / forward 5 seconds |
| <kbd>Ctrl</kbd>+<kbd>←</kbd> <kbd>Ctrl</kbd>+<kbd>→</kbd> | Previous / next track |
| <kbd>Ctrl</kbd>+<kbd>↑</kbd> <kbd>Ctrl</kbd>+<kbd>↓</kbd> | Volume up / down 5% |
| <kbd>Ctrl</kbd>+<kbd>Z</kbd> | Undo the last delete |
| Media keys | Play-pause, next, previous |

Shortcuts work on every screen, and step aside while you're typing in a search box.

> [!NOTE]
> On Linux, most desktops send media keys to MPRIS rather than to the app. MysticJam handles both, so the keys work either way.

---

## Themes and Look & Feel

### Themes

MysticJam's default look is **Vesper Dusk**. Open **Settings → Themes** to build your own in the theme editor, starting from scratch or from one of the starter presets:

**Vesper Dawn** &nbsp;·&nbsp; **Midnight** &nbsp;·&nbsp; **Sunset** &nbsp;·&nbsp; **Mono**

Duplicate a preset and edit the copy to make it yours. **Light Mode** in Settings switches to a true white background.

### Look & Feel

**Settings → Look & Feel** fine-tunes the details:

| Section | Options |
|---|---|
| **Lyrics** | Text position (left, middle, right), text size, line spacing, how faded the other lines are, auto-scroll, tap a line to seek, online lookup, rescan |
| **Lists** | Mark songs that have lyrics, show the file format (FLAC / MP3) on song rows |
| **Now Playing** | Classic or disc player style, and tinting the player with the album art's colours |
| **Display** | Shows your monitor's refresh rate (MysticJam renders at it automatically), and an optional FPS counter |

---

## Privacy

- **No accounts, no analytics, no telemetry.**
- **Nothing leaves your computer** unless the lyrics lookup is on. It sends only the artist, title and length of a song that has no lyrics, to lrclib.net. Turn it off in **Settings → Look & Feel** and MysticJam is fully offline.
- **The log file contains no song names or file paths**, so it's safe to share when reporting a bug.

---

## Where your data lives

Your library, settings, themes and album art are kept in one folder, separate from the app:

| Platform | Folder |
|---|---|
| Linux | `~/.local/share/com.musicplayer.music_player` |
| Windows | `%APPDATA%\MysticJam\MysticJam` |

| File / folder | What it holds |
|---|---|
| `music_player.sqlite` | Your library: songs, albums, playlists |
| `app_settings.json` | Settings, Look & Feel options, the last song played |
| `custom_themes.json` | Themes you've made |
| `album_art/` | Cached album covers |
| `logs/mysticjam.log` | A small log with no song names or file paths |

> [!TIP]
> To reset just one thing, delete only that file. For example, delete `app_settings.json` to go back to default settings while keeping your library.

<details>
<summary>Can't see the <code>.local</code> folder in your file manager?</summary>

`~` means your home folder. Open it, turn on **Show hidden files** (usually <kbd>Ctrl</kbd>+<kbd>H</kbd>), then open `.local` → `share`.

</details>

---

## Updating

**Linux:** download the new release, extract it, and run `./install.sh` again. It replaces the old version and keeps your library and settings.

**Windows:** extract the new zip over the old folder, or into a new one. Your data lives elsewhere, so nothing is lost.

---

## Uninstalling

### Linux

```sh
~/.local/share/mysticjam/uninstall.sh
```

This removes the app, its menu entry, its icon and the `mysticjam` command.

### Windows

Delete the folder you extracted.

> [!IMPORTANT]
> **Uninstalling keeps your library and settings**, so a reinstall picks up right where you left off. To remove those too, delete the data folder from [Where your data lives](#where-your-data-lives). On Linux:
>
> ```sh
> rm -rf ~/.local/share/com.musicplayer.music_player
> ```

---

## Building from source

You need [Flutter](https://docs.flutter.dev/get-started/install/linux) (stable channel), a [Rust toolchain](https://rustup.rs) (the library scanner is a Rust crate that the Flutter build compiles automatically), the Linux desktop build tools, and libmpv **with its development files**.

<details open>
<summary><b>Arch Linux, CachyOS, EndeavourOS, Manjaro</b></summary>

```sh
sudo pacman -S --needed clang cmake ninja pkgconf gtk3 mpv
```

</details>

<details>
<summary><b>Ubuntu, Debian, Linux Mint, Pop!_OS</b></summary>

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev
```

</details>

<details>
<summary><b>Fedora</b></summary>

```sh
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel
sudo dnf install 'pkgconfig(mpv)'
```

</details>

Then clone, run and build:

```sh
# Rust, if you don't have it yet
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

git clone https://github.com/MysticYewXd/MysticJam
cd MysticJam
flutter pub get
flutter run -d linux               # run a debug build
flutter build linux --release      # build a release
```

The release build lands in `build/linux/x64/release/bundle/`.

<details>
<summary>Building for Windows</summary>

On a Windows machine with Flutter, Visual Studio's C++ tools and [Rust](https://rustup.rs):

```sh
flutter pub get
flutter build windows --release
```

The app lands in `build\windows\x64\runner\Release\`. The [Build Windows](.github/workflows/build-windows.yml) workflow does the same on GitHub Actions and attaches the zip to a release whenever a `v*` tag is pushed.

</details>

---

## Troubleshooting

<details>
<summary><b>There's no sound, or the app won't start, on Linux</b></summary>

libmpv is most likely missing. Install it as in [Step 1](#step-1-install-libmpv), then check it's found:

```sh
ldconfig -p | grep libmpv
```

</details>

<details>
<summary><b>MysticJam doesn't appear in my app menu</b></summary>

Log out and back in once so your desktop rereads its app list. You can also start it from a terminal with `mysticjam`.

</details>

<details>
<summary><b><code>mysticjam: command not found</code></b></summary>

The command lives in `~/.local/bin`, which some distros don't put on your `PATH`. Add it:

```sh
# bash / zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# fish
fish_add_path ~/.local/bin
```

Then open a new terminal.

</details>

<details>
<summary><b>Some songs show the file name instead of the artist and title</b></summary>

WAV files and audio inside video containers don't carry tags MysticJam can read, so it uses the file name. For other formats, check the file actually has tags, then hit **Rescan library**.

</details>

<details>
<summary><b>Lyrics don't show up</b></summary>

- Check the `.lrc` file has **exactly** the same name as the song, in the same folder.
- Run **Settings → Look & Feel → Rescan lyrics** after adding `.lrc` files.
- For songs with no lyrics file, turn on **Look up missing lyrics online**.

</details>

<details>
<summary><b>Windows says "Windows protected your PC"</b></summary>

That's SmartScreen, because the build isn't code-signed. Choose **More info → Run anyway**.

</details>

<details>
<summary><b>It still doesn't work</b></summary>

Start it from a terminal so you can see its messages:

```sh
mysticjam
```

Then [open an issue](https://github.com/MysticYewXd/MysticJam/issues) with what you did, what happened, your distro or Windows version, and the relevant lines from `logs/mysticjam.log` in your [data folder](#where-your-data-lives).

</details>

---

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first: it covers the project's scope (local-only, no streaming, no audio DSP), its architecture rules, and how to run the tests. Security issues are covered in [SECURITY.md](SECURITY.md).

The interface uses the **DM Sans** and **Fraunces** fonts under the [SIL Open Font License](assets/fonts/OFL.txt).

### Thanks

- **Shadow** ([@darknesspwner](https://github.com/darknesspwner)) for help with Fedora support.

---

## License

MysticJam is released under the [MIT License](LICENSE).

<div align="center"><sub>Made by Kong. A sibling of <a href="https://github.com/MysticYewXd/MysticQuaere">MysticQuaere</a>.</sub></div>
