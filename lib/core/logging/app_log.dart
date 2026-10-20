import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

/// Structured, privacy-safe application log: one JSON object per line in
/// `<app support dir>/logs/mysticjam.log`, rotated at 1 MB (one previous
/// file kept).
///
/// Privacy rule: logs describe *what happened*, never *whose music it was* —
/// counts, durations, status codes, error types. Callers should not pass file
/// names, titles, artists or lyrics; as a safety net every string that does
/// get through is scrubbed of file paths/URIs and truncated (see [scrub]).
///
/// Before [init] (and in tests) nothing is written, so logging is always safe
/// to call.
class AppLog {
  AppLog._();

  static const _maxBytes = 1024 * 1024;
  static const _maxStringLength = 200;

  static File? _file;
  static int _writesSinceRotateCheck = 0;

  /// Receives every formatted line (tests use this to observe output).
  @visibleForTesting
  static void Function(String line)? testSink;

  static String? get logFilePath => _file?.path;

  static Future<void> init({Directory? directory}) async {
    try {
      final base = directory ?? await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'logs'));
      await dir.create(recursive: true);
      _file = File(p.join(dir.path, 'mysticjam.log'));
      _rotateIfNeeded();
    } catch (_) {
      _file = null; // no log file is better than no app
    }
  }

  static void debug(String tag, String message, [Map<String, Object?>? f]) =>
      _write(LogLevel.debug, tag, message, f);
  static void info(String tag, String message, [Map<String, Object?>? f]) =>
      _write(LogLevel.info, tag, message, f);
  static void warn(String tag, String message, [Map<String, Object?>? f]) =>
      _write(LogLevel.warn, tag, message, f);
  static void error(String tag, String message, [Map<String, Object?>? f]) =>
      _write(LogLevel.error, tag, message, f);

  /// Logs an exception by *type* plus a scrubbed message, never the raw
  /// message (exception text routinely embeds file paths).
  static void exception(
    String tag,
    String message,
    Object error, [
    StackTrace? stack,
  ]) => _write(LogLevel.error, tag, message, {
    'error': error.runtimeType.toString(),
    'detail': error.toString(),
    if (stack != null)
      'stack': stack.toString().split('\n').take(6).join(' | '),
  });

  // A path may contain spaces ("/home/me/My Music/a.flac"), so an unquoted
  // path is taken to run to the next ": " / ", " / "; " / closing bracket or
  // the end. That can swallow a little surrounding text: it errs on the side
  // of removing too much, never too little.
  static final _fileUri = RegExp(r'file:/{1,3}[^\s)\]\x27"]*');
  static final _quotedPath = RegExp(r'''(['"])(?:/|[A-Za-z]:\\)[^\n]*?\1''');
  static final _posixPath = RegExp(
    r'(?<![\w.:])/(?=\S)[^\n]*?(?=[:;,]\s|[)\]]|$)',
  );
  static final _windowsPath = RegExp(
    r'(?<![\w.])[A-Za-z]:\\[^\n]*?(?=[:;,]\s|[)\]]|$)',
  );

  // Applied before the path regexes run, not after — this text can come
  // from a thrown exception whose message embeds network/response content
  // (e.g. an HTTP client error), so it isn't bounded by anything this app
  // controls. Capping it first keeps the regex work below proportional to
  // a fixed size instead of to however much text a remote server chose to
  // send, however that text is shaped.
  static const _maxScrubInputLength = 4000;

  /// Removes anything that looks like a file path or file URI and truncates.
  static String scrub(String input) {
    var s = input.length > _maxScrubInputLength
        ? input.substring(0, _maxScrubInputLength)
        : input;
    s = s
        .replaceAll(_fileUri, '<path>')
        .replaceAllMapped(_quotedPath, (m) => '${m[1]}<path>${m[1]}')
        .replaceAll(_posixPath, '<path>')
        .replaceAll(_windowsPath, '<path>');
    if (s.length > _maxStringLength) s = '${s.substring(0, _maxStringLength)}…';
    return s;
  }

  /// One log line as JSON. Public for tests.
  @visibleForTesting
  static String format(
    LogLevel level,
    String tag,
    String message,
    Map<String, Object?>? fields, {
    DateTime? now,
  }) {
    final safe = <String, Object?>{};
    fields?.forEach((k, v) {
      safe[k] = switch (v) {
        null || num() || bool() => v,
        Enum() => v.name,
        _ => scrub(v.toString()),
      };
    });
    return jsonEncode({
      't': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'level': level.name,
      'tag': tag,
      'msg': scrub(message),
      if (safe.isNotEmpty) ...safe,
    });
  }

  static void _write(
    LogLevel level,
    String tag,
    String message,
    Map<String, Object?>? fields,
  ) {
    final line = format(level, tag, message, fields);
    testSink?.call(line);
    if (kDebugMode) debugPrint(line);
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync('$line\n', mode: FileMode.append);
      if (++_writesSinceRotateCheck >= 200) _rotateIfNeeded();
    } catch (_) {
      // Logging must never take the app down.
    }
  }

  static void _rotateIfNeeded() {
    _writesSinceRotateCheck = 0;
    final file = _file;
    if (file == null || !file.existsSync() || file.lengthSync() < _maxBytes) {
      return;
    }
    file.renameSync('${file.path}.1');
  }

  /// Hooks Flutter's and the platform's uncaught-error callbacks so crashes
  /// leave a (scrubbed) trace. Keeps the default console output too.
  static void installErrorHooks() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      exception(
        'flutter',
        'uncaught framework error',
        details.exception,
        details.stack,
      );
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      exception('platform', 'uncaught async error', error, stack);
      return false; // still report it as unhandled
    };
  }
}
