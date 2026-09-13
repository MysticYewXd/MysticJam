import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/database.dart';
import '../library/library_providers.dart';
import '../playback/playback_controller.dart';

const _channelName = 'com.musicplayer.music_player/files';

/// Receives file paths handed over from the native Linux runner — either a
/// command-line launch (`music_player /path/to/song.mp3`) or a file
/// manager "Open With" association (see linux/runner/my_application.cc's
/// open() and linux/mysticjam.desktop's MimeType list). Scans each path
/// into the library if it isn't already indexed, then plays them.
///
/// This is also how a *second* launch's file reaches this (the first,
/// already-running) instance: GLib's single-instance machinery forwards it
/// here over D-Bus rather than starting a second process — see
/// my_application.cc's doc comments for the native half of this.
class FileOpenChannel {
  final Ref ref;
  static const _channel = MethodChannel(_channelName);

  FileOpenChannel(this.ref) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'openFiles') return;
    final paths = (call.arguments as List).cast<String>();
    if (paths.isEmpty) return;

    final scanner = ref.read(libraryScannerProvider);
    final repo = ref.read(libraryRepositoryProvider);
    final scanResult = await scanner.scanFiles(paths);

    // Order isn't guaranteed to exactly match the paths passed in (the id
    // lookup below is a plain WHERE...IN query) — acceptable for this: the
    // overwhelmingly common case is opening a single file, where ordering
    // is moot; opening several at once from a file manager is rare enough
    // not to be worth a more careful ordered lookup.
    final ids = await repo.getTrackIdsForPaths(scanResult.allPaths);
    if (ids.isEmpty) return;

    final tracks = <Track>[];
    for (final id in ids) {
      final track = await repo.getTrackById(id);
      if (track != null) tracks.add(track);
    }
    if (tracks.isEmpty) return;

    final controller = ref.read(playbackControllerProvider.notifier);
    await controller.playFromQueue(tracks, 0);
  }
}

/// Set up once, for the life of the app — read this (e.g. via ref.watch)
/// once during startup (see app.dart) purely to trigger its creation; the
/// listener it registers is what matters, not its return value.
final fileOpenChannelProvider = Provider<FileOpenChannel>((ref) {
  return FileOpenChannel(ref);
});
