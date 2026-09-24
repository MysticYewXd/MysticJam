/// Parses a tag's raw track-number string into just the track number,
/// discarding a trailing "/total" if present — every format that stores
/// this as text (Vorbis comments' TRACKNUMBER, APEv2's Track, ID3's TRCK)
/// uses either a bare "5" or a "5/12" (track/total) convention. Returns
/// null for anything that doesn't start with a parseable integer, rather
/// than 0 — see Tracks.trackNumber in library_model.dart for why 0 is
/// never used as an "unknown" sentinel.
int? parseLeadingTrackNumber(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  final slash = trimmed.indexOf('/');
  final leading = slash == -1 ? trimmed : trimmed.substring(0, slash);
  return int.tryParse(leading.trim());
}
