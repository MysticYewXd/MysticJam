import 'dart:convert';

import 'package:http/http.dart' as http;

/// Looks up synced (LRC-format) lyrics on lrclib.net, a free public lyrics
/// database. Sends only artist, title and duration, and only when the user
/// opens the Lyrics screen for a track with no local synced lyrics — never
/// in bulk or in the background. Returns the raw LRC text (parse it with
/// parseLrc), or null for no match / any network or server failure.
Future<String?> fetchSyncedLyrics({
  required String artist,
  required String title,
  int? durationSec,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(
          Uri.https('lrclib.net', '/api/get', {
            'artist_name': artist,
            'track_name': title,
            if (durationSec != null) 'duration': '$durationSec',
          }),
          headers: {'User-Agent': 'MysticJam/0.1'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final synced = jsonDecode(utf8.decode(response.bodyBytes))['syncedLyrics'];
    return synced is String && synced.trim().isNotEmpty ? synced : null;
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
