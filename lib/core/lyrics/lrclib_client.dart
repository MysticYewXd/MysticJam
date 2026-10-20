import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logging/app_log.dart';

/// Looks up synced (LRC-format) lyrics on lrclib.net, a free public lyrics
/// database. Sends only artist, title and duration, and only when the user
/// opens the Lyrics screen for a track with no local synced lyrics — never
/// in bulk or in the background. Returns the raw LRC text (parse it with
/// parseLrc), or null for no match / any network or server failure.
const _maxResponseBytes = 300 * 1024;

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
    if (response.statusCode != 200) {
      AppLog.info('lyrics', 'lookup miss', {'status': response.statusCode});
      return null;
    }
    // The response is trusted enough to display and store, but not enough
    // to let it size the database/UI without a limit — a compromised or
    // just-misbehaving server could otherwise hand back an arbitrarily
    // large body. 300 KB is generously above any real LRC file (even a
    // long, word-by-word karaoke-style one).
    if (response.bodyBytes.length > _maxResponseBytes) {
      AppLog.warn('lyrics', 'response too large', {
        'bytes': response.bodyBytes.length,
      });
      return null;
    }
    final synced = jsonDecode(utf8.decode(response.bodyBytes))['syncedLyrics'];
    final found = synced is String && synced.trim().isNotEmpty;
    AppLog.info('lyrics', 'lookup ${found ? 'hit' : 'no synced lyrics'}');
    return found ? synced : null;
  } catch (e) {
    // Only the error type: a network error's text can echo the request.
    AppLog.warn('lyrics', 'lookup failed', {'error': e.runtimeType});
    return null;
  } finally {
    if (client == null) c.close();
  }
}
