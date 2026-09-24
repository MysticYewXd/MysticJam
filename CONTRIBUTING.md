# Contributing to MysticJam

Thanks for considering it. MysticJam is a local-only Flutter music player,
Linux desktop first — no accounts, no streaming, no cloud, and no
telemetry. Contributions should keep that scope.

## Getting set up

```sh
flutter pub get
flutter run -d linux
```

Run the test suite before opening a PR:

```sh
flutter analyze
flutter test
```

Both need to be clean. `flutter build linux --release` (see the README) is
worth running too if you touched anything platform-specific.

## Scope

- **Linux desktop is the target right now.** Android has a project folder
  but is explicitly not supported yet — it has no background-playback
  service, no runtime permission handling, and hasn't been run on a device.
  Don't add Android-only code paths unless you're prepared to build that
  out properly; a partial implementation is worse than none.
- **No accounts, no streaming, no analytics.** The one thing that talks to
  the network is an opt-in lyrics lookup (`lib/core/lyrics/`), off by
  default in spirit — keep it that way if you touch it. Anything else
  that would send data off the user's machine needs a strong reason and an
  explicit setting to turn it off.
- **No audio DSP.** No equalizer, no crossfade, no resampler settings.
  Playback goes straight from the decoder to the OS's audio output; keep it
  that way.

## Architecture rules

These aren't style preferences — tests and existing code assume them:

- **`PlaybackController` is the single source of truth** for playback
  state. Screens read it through Riverpod; they don't talk to the audio
  engine directly.
- **media_kit types stay inside `MediaKitAudioEngine`.** Nothing outside
  `lib/core/audio/` should import `package:media_kit`.
- **Widgets never touch Drift directly.** Go through
  `LibraryRepository` (`lib/core/library/library_repository.dart`). It's
  the only thing that runs queries against `AppDatabase`.
- **Theming goes through `AppTheme`/`ThemeProvider`.** No hardcoded
  `Color`/`Icons.*` in a screen — every themed widget in `lib/widgets/themed/`
  exists so that a theme can override it.
- **Logging never includes what the user is listening to.** See
  `lib/core/logging/app_log.dart` — file paths, titles and artists are
  stripped before anything is written. If you add a log call, don't pass it
  a raw file path or track title.

## Database changes

Any change to `lib/core/library/library_model.dart` needs:

1. A bump to `AppDatabase.schemaVersion` in `database.dart`.
2. A migration step in `onUpgrade` — existing users' libraries must survive
   the upgrade with their data intact.
3. Regenerate the generated code: `dart run build_runner build`.
4. A migration test in `test/core/library/database_migration_test.dart`
   that seeds the *old* schema by hand and checks the upgrade preserves
   existing rows and adds the new column(s) as `NULL`/default. Look at the
   existing `seedV*Database` helpers there for the pattern.

## Commit messages

Look at `git log` for the tone this project uses: a short imperative
summary line, then (for anything non-trivial) a couple of bullet points on
*why*, not a restatement of the diff. No fixed prefix convention
(`feat:`/`fix:` etc.) is enforced — clarity matters more than format.

## Pull requests

- Keep them scoped to one thing. A bug fix doesn't need an unrelated
  refactor riding along.
- Add or update tests for the behavior you changed. `flutter test` should
  cover the new code, not just leave it to manual checking.
- If you're not sure a feature fits the project's scope (see above), open
  an issue first rather than a large PR.

## Reporting bugs

Open an issue with: what you did, what you expected, what happened
instead, and your OS/Flutter version (`flutter --version`). If it's a
crash, attach the relevant lines from
`~/.local/share/com.musicplayer.music_player/logs/mysticjam.log` — it's
designed to be safe to share (no file paths or track info), but skim it
before pasting just in case.
