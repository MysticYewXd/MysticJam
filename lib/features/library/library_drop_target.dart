import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_providers.dart';
import '../../core/library/library_scanner.dart';
import '../../core/logging/app_log.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/theme_provider.dart';

/// Result of importing dropped items, for the confirmation message.
class DropImportResult {
  final int added;
  final int failed;
  const DropImportResult(this.added, this.failed);
}

/// Adds everything dropped on the window: a folder is scanned recursively
/// (like Add Folder), loose files are filtered to supported media (like Add
/// Files). Items that don't exist any more or aren't media are skipped.
Future<DropImportResult> importDroppedPaths(
  LibraryScanner scanner,
  List<String> paths, {
  void Function(String folder)? onFolderImported,
}) async {
  var added = 0;
  var failed = 0;
  final files = <String>[];
  for (final path in paths) {
    if (FileSystemEntity.isDirectorySync(path)) {
      final result = await scanner.scanDirectory(path);
      added += result.addedCount;
      failed += result.failedPaths.length;
      onFolderImported?.call(path);
    } else if (File(path).existsSync()) {
      files.add(path);
    }
  }
  if (files.isNotEmpty) {
    final result = await scanner.scanFiles(files);
    added += result.addedCount;
    failed += result.failedPaths.length;
  }
  return DropImportResult(added, failed);
}

/// Wraps the app body so music dropped from a file manager is added to the
/// library, with a hint overlay while something is being dragged over.
class LibraryDropTarget extends ConsumerStatefulWidget {
  final Widget child;

  const LibraryDropTarget({super.key, required this.child});

  @override
  ConsumerState<LibraryDropTarget> createState() => _LibraryDropTargetState();
}

class _LibraryDropTargetState extends ConsumerState<LibraryDropTarget> {
  bool _dragging = false;

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    final paths = [for (final f in details.files) f.path];
    if (paths.isEmpty) return;
    AppLog.info('drop', 'received', {'items': paths.length});

    final messenger = ScaffoldMessenger.of(context);
    final settings = ref.read(appSettingsProvider.notifier);
    final result = await importDroppedPaths(
      ref.read(libraryScannerProvider),
      paths,
      onFolderImported: settings.addImportedFolder,
    );
    final text = result.added == 0
        ? 'No new songs found in what you dropped'
        : 'Added ${result.added} ${result.added == 1 ? 'song' : 'songs'}';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.failed == 0
              ? text
              : '$text (${result.failed} could not be read)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colors.primary.withValues(alpha: 0.14),
                    border: Border.all(color: theme.colors.primary, width: 2),
                    borderRadius: BorderRadius.circular(
                      theme.shapes.cornerRadius * 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Drop music to add it to your library',
                    style: theme.typography.display(
                      24,
                      color: theme.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
