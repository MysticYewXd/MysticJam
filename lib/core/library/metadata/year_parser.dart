/// Pulls a four-digit year out of a tag's raw date string. Formats seen in
/// the wild: a bare "2019" (ID3 TYER, most Vorbis YEAR), a full ISO date
/// "2019-05-03" or timestamp (ID3v2.4 TDRC, Vorbis DATE, MP4 ©day), or
/// occasionally "05/03/2019". Returns null when no plausible year is
/// present, never 0 — same "null means unknown" convention as
/// Tracks.trackNumber.
int? parseLeadingYear(String? raw) {
  if (raw == null) return null;
  final match = _yearPattern.firstMatch(raw);
  if (match == null) return null;
  return int.parse(match.group(0)!);
}

// A standalone 4-digit run in 1000-2999 — anchoring on digit boundaries so
// something like "12345" or a catalog number doesn't yield a bogus "1234".
final _yearPattern = RegExp(r'(?<!\d)[12]\d{3}(?!\d)');
