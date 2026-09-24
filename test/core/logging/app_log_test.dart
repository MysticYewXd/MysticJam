import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/logging/app_log.dart';

void main() {
  group('scrub removes file paths and URIs, keeps ordinary text', () {
    final cases = {
      'Failed to open /home/mystic/Music/Song.flac': 'Failed to open <path>',
      'Failed to open /home/mystic/My Music/Song One.flac: no such file':
          'Failed to open <path>: no such file',
      "Cannot open file, path = '/tmp/My Dir/a b.mp3' (OS Error: x)":
          "Cannot open file, path = '<path>' (OS Error: x)",
      'bad uri file:///home/me/x%20y.mp3 here': 'bad uri <path> here',
      r'C:\Users\Me\Music\a b.mp3: denied': '<path>: denied',
      'read (file:///home/me/lib/a.dart:12:5)': 'read (<path>)',
      'either and/or 50 / 100 and 1/2': 'either and/or 50 / 100 and 1/2',
      'package:music_player/core/x.dart 3:4':
          'package:music_player/core/x.dart 3:4',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(AppLog.scrub(input), expected));
    });

    test('long text is truncated', () {
      expect(AppLog.scrub('a' * 500).length, lessThanOrEqualTo(201));
    });

    test('no fragment of a private path survives', () {
      const secret = 'Secret Album/Top Secret Song.flac';
      final out = AppLog.scrub('failed: /home/me/Music/$secret: eof');
      expect(out, isNot(contains('Secret')));
      expect(out, isNot(contains('home')));
    });
  });

  group('format', () {
    final when = DateTime.utc(2026, 9, 21, 12, 30);

    test('is one JSON object with time, level, tag, msg and fields', () {
      final line = AppLog.format(LogLevel.info, 'scan', 'finished', {
        'added': 12,
        'ok': true,
        'nothing': null,
      }, now: when);
      expect(line.contains('\n'), isFalse);
      expect(jsonDecode(line), {
        't': '2026-09-21T12:30:00.000Z',
        'level': 'info',
        'tag': 'scan',
        'msg': 'finished',
        'added': 12,
        'ok': true,
        'nothing': null,
      });
    });

    test('string fields are scrubbed, enums are logged by name', () {
      final m =
          jsonDecode(
                AppLog.format(LogLevel.warn, 't', 'm', {
                  'where': '/home/me/private/x.flac',
                  'level': LogLevel.error,
                }, now: when),
              )
              as Map;
      expect(m['where'], '<path>');
      expect(m['level'], 'error');
    });

    test('the message itself is scrubbed too', () {
      final m =
          jsonDecode(
                AppLog.format(
                  LogLevel.error,
                  't',
                  'crash in /home/me/x.dart',
                  null,
                ),
              )
              as Map;
      expect(m['msg'], 'crash in <path>');
    });
  });

  group('file output', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mysticjam_log_'));
    tearDown(() {
      AppLog.testSink = null;
      dir.deleteSync(recursive: true);
    });

    test('nothing is written before init', () {
      AppLog.info('x', 'not initialised');
      expect(dir.listSync(), isEmpty);
    });

    test('init creates logs/mysticjam.log and lines are appended', () async {
      await AppLog.init(directory: dir);
      AppLog.info('scan', 'one', {'n': 1});
      AppLog.warn('scan', 'two');
      final lines = File('${dir.path}/logs/mysticjam.log').readAsLinesSync();
      expect(lines, hasLength(2));
      expect(jsonDecode(lines[0])['msg'], 'one');
      expect(jsonDecode(lines[1])['level'], 'warn');
      expect(AppLog.logFilePath, endsWith('logs/mysticjam.log'));
    });

    test('an oversized log is rotated to .1 on init', () async {
      final logs = Directory('${dir.path}/logs')..createSync();
      File(
        '${logs.path}/mysticjam.log',
      ).writeAsStringSync('x' * (1024 * 1024 + 10));
      await AppLog.init(directory: dir);
      expect(File('${logs.path}/mysticjam.log.1').existsSync(), isTrue);
      AppLog.info('a', 'b');
      expect(
        File('${logs.path}/mysticjam.log').readAsStringSync(),
        contains('"msg":"b"'),
      );
    });

    test(
      'exceptions log the type and a scrubbed detail, never the raw text',
      () async {
        final lines = <String>[];
        AppLog.testSink = lines.add;
        AppLog.exception(
          'db',
          'open failed',
          FileSystemException('Cannot open', '/home/me/Secret/music.db'),
        );
        final m = jsonDecode(lines.single) as Map;
        expect(m['error'], 'FileSystemException');
        expect(lines.single, isNot(contains('Secret')));
      },
    );

    test('uncaught framework errors are logged, scrubbed', () {
      final lines = <String>[];
      AppLog.testSink = lines.add;
      final oldOnError = FlutterError.onError;
      final oldDispatcher = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = oldOnError;
        PlatformDispatcher.instance.onError = oldDispatcher;
      });
      FlutterError.onError = (_) {};
      AppLog.installErrorHooks();

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('bad state at /home/me/Private/a.flac'),
        ),
      );
      expect(lines, hasLength(1));
      expect(lines.single, contains('StateError'));
      expect(lines.single, isNot(contains('Private')));
    });
  });

  group('scrub input is size-bounded before the regexes run', () {
    test('a very large string is still handled (no hang) and capped', () {
      final huge = '/a/b/c ' * 200000; // ~1.4 MB of path-shaped text
      final sw = Stopwatch()..start();
      final out = AppLog.scrub(huge);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(out.length, lessThanOrEqualTo(201));
    });

    test('pathological repeated-path input completes quickly', () {
      final input = ('"/x/y/z" ' * 5000) + ('C:\\a\\b\\c ' * 5000);
      final sw = Stopwatch()..start();
      AppLog.scrub(input);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });
}
