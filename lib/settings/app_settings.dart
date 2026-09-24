import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How many entries "recently played" keeps before dropping the oldest —
/// enough for a meaningful list without the file growing unbounded.
const _recentlyPlayedLimit = 50;

enum LyricsAlign { left, center, right }

/// Look-and-feel preferences (Settings → Look & Feel). Kept in the same
/// settings file as the session state below since it's the same persistence
/// story; one immutable bundle so adding an option is one field + one line
/// in each of copyWith/toJson/fromJson.
class UiPrefs {
  final double lyricsFontSize;
  final LyricsAlign lyricsAlign;
  final double lyricsLineSpacing;

  /// Opacity of every lyric line except the current one.
  final double lyricsInactiveOpacity;
  final bool lyricsAutoScroll;
  final bool lyricsTapToSeek;

  /// Whether opening Lyrics may look a track up on lrclib.net when it has no
  /// local synced lyrics (the only thing in the app that uses the network).
  final bool lyricsOnlineLookup;
  final bool showLyricsIcon;
  final bool showFormatTag;

  /// Tint the mini player / Now Playing with the album art's colours.
  final bool albumColors;
  final bool showFps;

  const UiPrefs({
    this.lyricsFontSize = 20,
    this.lyricsAlign = LyricsAlign.left,
    this.lyricsLineSpacing = 1.4,
    this.lyricsInactiveOpacity = 0.35,
    this.lyricsAutoScroll = true,
    this.lyricsTapToSeek = true,
    this.lyricsOnlineLookup = true,
    this.showLyricsIcon = true,
    this.showFormatTag = true,
    this.albumColors = true,
    this.showFps = false,
  });

  UiPrefs copyWith({
    double? lyricsFontSize,
    LyricsAlign? lyricsAlign,
    double? lyricsLineSpacing,
    double? lyricsInactiveOpacity,
    bool? lyricsAutoScroll,
    bool? lyricsTapToSeek,
    bool? lyricsOnlineLookup,
    bool? showLyricsIcon,
    bool? showFormatTag,
    bool? albumColors,
    bool? showFps,
  }) => UiPrefs(
    lyricsFontSize: lyricsFontSize ?? this.lyricsFontSize,
    lyricsAlign: lyricsAlign ?? this.lyricsAlign,
    lyricsLineSpacing: lyricsLineSpacing ?? this.lyricsLineSpacing,
    lyricsInactiveOpacity: lyricsInactiveOpacity ?? this.lyricsInactiveOpacity,
    lyricsAutoScroll: lyricsAutoScroll ?? this.lyricsAutoScroll,
    lyricsTapToSeek: lyricsTapToSeek ?? this.lyricsTapToSeek,
    lyricsOnlineLookup: lyricsOnlineLookup ?? this.lyricsOnlineLookup,
    showLyricsIcon: showLyricsIcon ?? this.showLyricsIcon,
    showFormatTag: showFormatTag ?? this.showFormatTag,
    albumColors: albumColors ?? this.albumColors,
    showFps: showFps ?? this.showFps,
  );

  Map<String, dynamic> toJson() => {
    'lyricsFontSize': lyricsFontSize,
    'lyricsAlign': lyricsAlign.name,
    'lyricsLineSpacing': lyricsLineSpacing,
    'lyricsInactiveOpacity': lyricsInactiveOpacity,
    'lyricsAutoScroll': lyricsAutoScroll,
    'lyricsTapToSeek': lyricsTapToSeek,
    'lyricsOnlineLookup': lyricsOnlineLookup,
    'showLyricsIcon': showLyricsIcon,
    'showFormatTag': showFormatTag,
    'albumColors': albumColors,
    'showFps': showFps,
  };

  factory UiPrefs.fromJson(Map<String, dynamic> j) {
    const d = UiPrefs();
    double num_(String k, double fallback, double lo, double hi) {
      final v = j[k];
      return (v is num ? v.toDouble() : fallback).clamp(lo, hi);
    }

    bool flag(String k, bool fallback) {
      final v = j[k];
      return v is bool ? v : fallback;
    }

    return UiPrefs(
      lyricsFontSize: num_('lyricsFontSize', d.lyricsFontSize, 12, 40),
      lyricsAlign:
          LyricsAlign.values.asNameMap()[j['lyricsAlign']] ?? d.lyricsAlign,
      lyricsLineSpacing: num_(
        'lyricsLineSpacing',
        d.lyricsLineSpacing,
        1.0,
        2.5,
      ),
      lyricsInactiveOpacity: num_(
        'lyricsInactiveOpacity',
        d.lyricsInactiveOpacity,
        0.1,
        1.0,
      ),
      lyricsAutoScroll: flag('lyricsAutoScroll', d.lyricsAutoScroll),
      lyricsTapToSeek: flag('lyricsTapToSeek', d.lyricsTapToSeek),
      lyricsOnlineLookup: flag('lyricsOnlineLookup', d.lyricsOnlineLookup),
      showLyricsIcon: flag('showLyricsIcon', d.showLyricsIcon),
      showFormatTag: flag('showFormatTag', d.showFormatTag),
      albumColors: flag('albumColors', d.albumColors),
      showFps: flag('showFps', d.showFps),
    );
  }
}

/// Playback/session state and imported-folder history that survives an app
/// restart. Deliberately holds only primitives (no Track, no
/// PlayerRepeatMode) so this file has zero dependency on the playback or
/// library layers — PlaybackController converts between its own types and
/// these at the point where it reads/writes this state. Volume is
/// intentionally NOT here: this app drives volume from the OS's own system
/// volume (see SystemVolumeController), which already persists itself at
/// the OS level — remembering and reapplying our own separate value on
/// launch would fight with whatever the user has actually set since.
class AppSettingsState {
  final bool shuffleEnabled;

  /// 'off' | 'all' | 'one' — matches PlayerRepeatMode's enum names exactly
  /// (`.name`/`.values.byName`), see PlaybackController.
  final String repeatMode;

  final int? lastTrackId;
  final int lastPositionMs;

  /// Most-recently-played first, capped at [_recentlyPlayedLimit].
  final List<int> recentlyPlayedTrackIds;

  /// Every folder added via "Add Folder" or drag-and-drop. "Rescan library"
  /// scans these for new songs (see LibraryScanner.scanFolders).
  final List<String> importedFolders;

  final UiPrefs ui;

  const AppSettingsState({
    this.shuffleEnabled = false,
    this.repeatMode = 'off',
    this.lastTrackId,
    this.lastPositionMs = 0,
    this.recentlyPlayedTrackIds = const [],
    this.importedFolders = const [],
    this.ui = const UiPrefs(),
  });

  AppSettingsState copyWith({
    bool? shuffleEnabled,
    String? repeatMode,
    int? Function()? lastTrackId,
    int? lastPositionMs,
    List<int>? recentlyPlayedTrackIds,
    List<String>? importedFolders,
    UiPrefs? ui,
  }) {
    return AppSettingsState(
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      lastTrackId: lastTrackId != null ? lastTrackId() : this.lastTrackId,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      recentlyPlayedTrackIds:
          recentlyPlayedTrackIds ?? this.recentlyPlayedTrackIds,
      importedFolders: importedFolders ?? this.importedFolders,
      ui: ui ?? this.ui,
    );
  }

  Map<String, dynamic> toJson() => {
    'shuffleEnabled': shuffleEnabled,
    'repeatMode': repeatMode,
    'lastTrackId': lastTrackId,
    'lastPositionMs': lastPositionMs,
    'recentlyPlayedTrackIds': recentlyPlayedTrackIds,
    'importedFolders': importedFolders,
    'ui': ui.toJson(),
  };

  factory AppSettingsState.fromJson(Map<String, dynamic> json) {
    return AppSettingsState(
      shuffleEnabled: json['shuffleEnabled'] as bool? ?? false,
      repeatMode: json['repeatMode'] as String? ?? 'off',
      lastTrackId: json['lastTrackId'] as int?,
      lastPositionMs: json['lastPositionMs'] as int? ?? 0,
      recentlyPlayedTrackIds:
          (json['recentlyPlayedTrackIds'] as List?)?.cast<int>() ?? const [],
      importedFolders:
          (json['importedFolders'] as List?)?.cast<String>() ?? const [],
      ui: UiPrefs.fromJson(
        (json['ui'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

/// Persists [AppSettingsState] to a JSON file in the app support directory
/// — same pattern as ThemeLibraryNotifier (see theme_library.dart), reused
/// deliberately instead of adding a settings-persistence package: it's a
/// single small file, already proven in this codebase, and pulling in
/// something like shared_preferences would be a second, redundant way of
/// doing the exact same thing.
class AppSettingsNotifier extends Notifier<AppSettingsState> {
  static const _fileName = 'app_settings.json';

  final Completer<void> _readyCompleter = Completer<void>();
  Timer? _positionFlushTimer;
  bool _positionDirty = false;

  /// Completes once the initial disk load has finished (successfully or
  /// not) — PlaybackController awaits this once at startup before
  /// attempting to resume the last track, so it never races the async file
  /// read and tries to resume against default/empty settings.
  Future<void> get ready => _readyCompleter.future;

  @override
  AppSettingsState build() {
    _load();
    ref.onDispose(() {
      _positionFlushTimer?.cancel();
    });
    return const AppSettingsState();
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _load() async {
    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        state = AppSettingsState.fromJson(raw);
      }
    } catch (_) {
      // Missing/corrupt file just means "start fresh" — never block the
      // app on a persistence failure, same policy as theme_library.dart.
    } finally {
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    }
  }

  /// Writes to a temp file then renames over the real one. A rename on the
  /// same filesystem is atomic, so a crash or power loss mid-write can
  /// never leave a half-written, corrupt settings file behind — the worst
  /// case is losing only the update that was in flight.
  Future<void> _persist() async {
    try {
      final file = await _settingsFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(state.toJson()));
      await tmp.rename(file.path);
    } catch (_) {
      // Best-effort — a failed save just means this particular change
      // doesn't survive a restart, not worth surfacing as a user error.
    }
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    state = state.copyWith(shuffleEnabled: enabled);
    await _persist();
  }

  Future<void> setRepeatMode(String mode) async {
    state = state.copyWith(repeatMode: mode);
    await _persist();
  }

  /// Called every time a genuinely different track starts playing — always
  /// persisted immediately (not throttled), since this is a discrete event
  /// rather than a continuous stream like position updates. Also resets
  /// the remembered position to 0, since a freshly-started track has no
  /// meaningful "resume point" yet.
  Future<void> recordTrackStarted(int trackId) async {
    final updated = [
      trackId,
      ...state.recentlyPlayedTrackIds.where((id) => id != trackId),
    ].take(_recentlyPlayedLimit).toList();
    state = state.copyWith(
      lastTrackId: () => trackId,
      lastPositionMs: 0,
      recentlyPlayedTrackIds: updated,
    );
    await _persist();
  }

  /// Throttled position updates, called on every position tick during
  /// playback. Only actually writes to disk once every few seconds via
  /// [_positionFlushTimer] rather than on every tick — position updates
  /// arrive multiple times a second, and writing that often would be
  /// needless disk I/O for a value that's only ever read back after an
  /// unclean restart.
  void updatePosition(int trackId, int positionMs) {
    if (state.lastTrackId != trackId) {
      return; // stale tick from a track that's no longer current
    }
    state = state.copyWith(lastPositionMs: positionMs);
    _positionDirty = true;
    _positionFlushTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_positionDirty) {
        _positionDirty = false;
        _persist();
      }
    });
  }

  /// Forces an immediate write regardless of the throttle — called on
  /// pause and track changes, per the requirement that those save right
  /// away instead of waiting for the next throttle tick.
  Future<void> flushPositionNow() async {
    if (!_positionDirty) return;
    _positionDirty = false;
    await _persist();
  }

  Future<void> updateUi(UiPrefs Function(UiPrefs) change) async {
    state = state.copyWith(ui: change(state.ui));
    await _persist();
  }

  Future<void> addImportedFolder(String path) async {
    if (state.importedFolders.contains(path)) return;
    state = state.copyWith(importedFolders: [...state.importedFolders, path]);
    await _persist();
  }

  /// Clears the remembered last-track/position — called when a resume
  /// attempt finds the file no longer exists (or the queue is emptied
  /// entirely), so a subsequent restart doesn't keep trying to resume a
  /// track that can't be resumed.
  Future<void> clearLastTrack() async {
    state = state.copyWith(lastTrackId: () => null, lastPositionMs: 0);
    await _persist();
  }
}

final uiPrefsProvider = Provider<UiPrefs>(
  (ref) => ref.watch(appSettingsProvider.select((s) => s.ui)),
);

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettingsState>(
      AppSettingsNotifier.new,
    );
