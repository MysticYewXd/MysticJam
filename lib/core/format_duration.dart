/// Formats a duration as `m:ss` (or `h:mm:ss` past an hour), the way every
/// track list/player screen in the app shows lengths.
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(hours > 0 ? 2 : 1, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
