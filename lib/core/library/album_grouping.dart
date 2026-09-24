/// Which album a track belongs to, decided purely from its embedded tags —
/// never from the folder it sits in, so two albums sharing one directory
/// stay separate and one album split across folders stays together.
///
/// A pure function (no I/O, no database) on purpose: the scanner calls it at
/// index time, and a future "edit tags" flow can call the exact same thing
/// to re-home a track after the user fixes its album/artist, guaranteeing
/// both paths agree on what "the same album" means.
class AlbumKey {
  /// Normalized identity — what the database enforces uniqueness on.
  final String groupKey;

  /// Display title, as tagged (first-seen casing wins in the database).
  final String title;

  /// Album-level artist for display, null for the Unknown Album bucket or
  /// when neither an album artist nor a track artist is tagged.
  final String? artist;

  /// True only for the catch-all bucket for files with no usable album tag.
  final bool isUnknown;

  const AlbumKey({
    required this.groupKey,
    required this.title,
    required this.artist,
    required this.isUnknown,
  });
}

/// Display name of the bucket for files with a missing, blank or unreadable
/// album tag.
const unknownAlbumTitle = 'Unknown Album';

/// Reserved group key for that bucket. It starts with a NUL character, which
/// [_clean] strips from every real tag value, so no real album key can ever
/// equal it — even an album literally titled "Unknown Album" gets a
/// different key and stays a separate album.
const unknownAlbumGroupKey = '\u0000unknown-album';

/// Fields are separated by an ASCII unit separator: it can't appear in a
/// normalized tag value, so ("a", "b c") and ("a b", "c") never produce the
/// same joined key the way a plain space or dash separator could.
const _fieldSeparator = '\u001f';

/// Groups by (album title, album artist) — NOT album title alone, so two
/// different artists' albums with the same name ("Greatest Hits") don't
/// merge into one.
///
/// [albumArtist] falls back to [artist] when absent: that keeps ordinary
/// single-artist releases grouped correctly even when the tagger never wrote
/// an album-artist field. The known cost of that fallback is compilations
/// tagged only with per-track artists and no album artist — those split into
/// one album per artist. Tagging them with an album artist (e.g. "Various
/// Artists") is what fixes them, and is exactly what the planned in-app tag
/// editor is for.
AlbumKey albumKeyFor({String? album, String? albumArtist, String? artist}) {
  final title = _clean(album);
  if (title == null) {
    return const AlbumKey(
      groupKey: unknownAlbumGroupKey,
      title: unknownAlbumTitle,
      artist: null,
      isUnknown: true,
    );
  }

  final groupingArtist = _clean(albumArtist) ?? _clean(artist);
  return AlbumKey(
    groupKey:
        '${_normalize(title)}$_fieldSeparator'
        '${groupingArtist == null ? '' : _normalize(groupingArtist)}',
    title: title,
    artist: groupingArtist,
    isUnknown: false,
  );
}

/// Trimmed, whitespace-collapsed display form, or null if nothing usable is
/// left (null, empty, or whitespace/control characters only — a "broken"
/// tag that would otherwise create an invisible-titled album).
String? _clean(String? value) {
  if (value == null) return null;
  final collapsed = value
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return collapsed.isEmpty ? null : collapsed;
}

/// Case-insensitive comparison form of an already-[_clean]ed value.
String _normalize(String cleaned) => cleaned.toLowerCase();
