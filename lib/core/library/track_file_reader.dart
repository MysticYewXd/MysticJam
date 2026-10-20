import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../src/rust/api/track.dart' as rust;
import 'metadata/metadata_reader.dart';
import 'metadata/track_metadata.dart';

/// Formats the Rust reader (rust/src/api/track.rs, built on lofty) handles.
/// Everything else — WMA, and video containers lofty can't parse — goes
/// through the Dart readers.
const _rustFormats = {
  'mp3',
  'aac',
  'm4a',
  'flac',
  'wav',
  'ogg',
  'opus',
  'ape',
  'mp4',
  'mov',
};

const _coverArtBaseNames = ['cover', 'folder', 'album', 'front', 'albumart'];
const _coverArtExtensions = ['jpg', 'jpeg', 'png'];

/// Everything the scanner stores from one song file.
class TrackFileData {
  /// Tags, plain (untimed) embedded lyrics, and cover art — embedded, or a
  /// `cover.jpg`-style image next to the song.
  final ParsedMetadata metadata;

  /// LRC text: the `.lrc` file next to the song, else timestamped lyrics
  /// embedded in it.
  final String? syncedLyrics;

  const TrackFileData(this.metadata, this.syncedLyrics);
}

/// Reads one song: Rust for the formats it supports, the Dart readers for
/// the rest and for any file Rust fails on (so nothing that read before
/// stops reading). Never throws.
Future<TrackFileData> readTrackFile(String path) async {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  if (_rustFormats.contains(ext)) {
    try {
      final f = await rust.readTrackFile(path: path);
      return TrackFileData(
        ParsedMetadata(
          title: f.title,
          artist: f.artist,
          album: f.album,
          albumArtist: f.albumArtist,
          genre: f.genre,
          year: f.year,
          trackNumber: f.trackNumber,
          durationMs: f.durationMs,
          lyrics: f.lyrics,
          artwork: f.artwork,
        ),
        f.syncedLyrics,
      );
    } catch (_) {
      // Unsupported or damaged in a way lofty rejects: try the Dart reader.
    }
  }
  return _readWithDart(path);
}

Future<TrackFileData> _readWithDart(String path) async {
  final m = await readTrackMetadata(path);
  var plain = m.lyrics;
  String? embeddedSynced;
  if (plain != null && _hasNoLyricLines(plain)) {
    plain = null; // e.g. just "[instrumental:true]"
  } else if (plain != null && _isSynced(plain)) {
    embeddedSynced = plain;
    plain = null;
  } else if (plain != null) {
    plain = _withoutHeaderTags(plain);
  }
  return TrackFileData(
    ParsedMetadata(
      title: m.title,
      artist: m.artist,
      album: m.album,
      albumArtist: m.albumArtist,
      genre: m.genre,
      year: m.year,
      trackNumber: m.trackNumber,
      durationMs: m.durationMs,
      lyrics: plain,
      artwork: m.artwork ?? await _findFolderCover(path),
    ),
    await _findLrcSidecar(path) ?? embeddedSynced,
  );
}

// The Rust rules (rust/src/lyrics.rs), so both readers classify alike.
bool _isSynced(String text) {
  try {
    return rust.isSyncedLyrics(text: text);
  } catch (_) {
    return false;
  }
}

String _withoutHeaderTags(String text) {
  try {
    return rust.plainLyricsText(text: text);
  } catch (_) {
    return text;
  }
}

bool _hasNoLyricLines(String text) {
  try {
    return rust.hasNoLyricLines(text: text);
  } catch (_) {
    return false;
  }
}

/// Reads `<same name>.lrc` next to [audioFilePath], if it exists — a
/// straight sibling-file check, not a directory listing, since (unlike
/// cover art) an LRC file's own name always matches the track it's for.
/// Case-insensitive extension, since rippers/taggers disagree on `.lrc`
/// vs `.LRC`. Returns the raw file content for parseLrc to read later,
/// not pre-parsed — see Tracks.syncedLyrics.
Future<String?> _findLrcSidecar(String audioFilePath) async {
  final base = p.withoutExtension(audioFilePath);
  for (final candidate in ['$base.lrc', '$base.LRC']) {
    try {
      final file = File(candidate);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) return content;
        return null;
      }
    } catch (_) {
      // Unreadable sidecar (permissions, bad encoding) — not fatal, the
      // track still gets indexed without synced lyrics.
    }
  }
  return null;
}

/// Many rips ship art as a plain cover.jpg/folder.jpg next to the audio
/// instead of embedding it. Same rule as the Rust reader: by file name
/// order, skipping empty files.
Future<Uint8List?> _findFolderCover(String audioFilePath) async {
  try {
    final dir = Directory(p.dirname(audioFilePath));
    if (!await dir.exists()) return null;
    final candidates = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final base = p.basenameWithoutExtension(entity.path).toLowerCase();
      final ext = p.extension(entity.path).replaceFirst('.', '').toLowerCase();
      if (_coverArtBaseNames.contains(base) &&
          _coverArtExtensions.contains(ext)) {
        candidates.add(entity);
      }
    }
    candidates.sort((a, b) => a.path.compareTo(b.path));
    for (final file in candidates) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
    }
  } catch (_) {
    // No cover file, or the directory couldn't be listed — not fatal.
  }
  return null;
}
