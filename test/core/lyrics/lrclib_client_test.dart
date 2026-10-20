import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:music_player/core/logging/app_log.dart';
import 'package:music_player/core/lyrics/lrclib_client.dart';

void main() {
  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test(
    'returns the synced lyrics and sends artist, title, duration, UA',
    () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return json({'syncedLyrics': '[00:01.00]Héllo', 'plainLyrics': 'x'});
      });

      final lrc = await fetchSyncedLyrics(
        artist: 'Some Artist',
        title: 'Some Title',
        durationSec: 187,
        client: client,
      );

      expect(lrc, '[00:01.00]Héllo');
      expect(seen.url.host, 'lrclib.net');
      expect(seen.url.path, '/api/get');
      expect(seen.url.queryParameters, {
        'artist_name': 'Some Artist',
        'track_name': 'Some Title',
        'duration': '187',
      });
      expect(seen.headers['User-Agent'], startsWith('MysticJam'));
    },
  );

  test('omits duration when unknown', () async {
    late http.Request seen;
    final client = MockClient((r) async {
      seen = r;
      return json({'syncedLyrics': '[00:01.00]a'});
    });
    await fetchSyncedLyrics(artist: 'A', title: 'T', client: client);
    expect(seen.url.queryParameters.containsKey('duration'), isFalse);
  });

  test(
    'null for 404, missing/empty syncedLyrics, bad body and network errors',
    () async {
      Future<String?> run(MockClient c) =>
          fetchSyncedLyrics(artist: 'A', title: 'T', client: c);

      expect(
        await run(MockClient((_) async => json({'message': 'no'}, 404))),
        isNull,
      );
      expect(
        await run(MockClient((_) async => json({'plainLyrics': 'only plain'}))),
        isNull,
      );
      expect(
        await run(MockClient((_) async => json({'syncedLyrics': null}))),
        isNull,
      );
      expect(
        await run(MockClient((_) async => json({'syncedLyrics': '  '}))),
        isNull,
      );
      expect(
        await run(MockClient((_) async => http.Response('not json', 200))),
        isNull,
      );
      expect(
        await run(
          MockClient((_) async => throw http.ClientException('offline')),
        ),
        isNull,
      );
    },
  );

  test('logs the outcome without the artist or title', () async {
    final lines = <String>[];
    AppLog.testSink = lines.add;
    addTearDown(() => AppLog.testSink = null);

    await fetchSyncedLyrics(
      artist: 'Very Private Artist',
      title: 'Very Private Title',
      client: MockClient((_) async => json({'syncedLyrics': '[00:01.00]x'})),
    );
    await fetchSyncedLyrics(
      artist: 'Very Private Artist',
      title: 'Very Private Title',
      client: MockClient(
        (_) async =>
            throw http.ClientException('offline for Very Private Artist'),
      ),
    );

    expect(lines, hasLength(2));
    expect(lines.join(), contains('lookup hit'));
    expect(lines.join(), contains('lookup failed'));
    expect(lines.join(), isNot(contains('Private')));
  });

  test('an oversized response is rejected instead of stored', () async {
    final big = 'x' * (301 * 1024);
    final client = MockClient((_) async => json({'syncedLyrics': big}));
    final lrc = await fetchSyncedLyrics(
      artist: 'A',
      title: 'T',
      client: client,
    );
    expect(lrc, isNull);
  });

  test('a response just under the limit is accepted', () async {
    final ok = 'x' * (250 * 1024);
    final client = MockClient((_) async => json({'syncedLyrics': ok}));
    final lrc = await fetchSyncedLyrics(
      artist: 'A',
      title: 'T',
      client: client,
    );
    expect(lrc, ok);
  });
}
