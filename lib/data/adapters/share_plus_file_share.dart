import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'archive_file_share.dart';
import 'binary_export_artifact.dart';
import 'data_export.dart';
import 'food_data_archive.dart';

/// Handing the export to the operating system (spec §7.4).
///
/// The only file in the app that touches `share_plus`, so swapping the share
/// sheet for a save dialog later is one class rather than a search (rule 7).
///
/// Files stay in temporary storage so the receiving app can finish reading
/// them after the share sheet closes. Each share has its own directory; two
/// reviewed exports on the same day must not overwrite each other's bytes.
class SharePlusFileShare implements FileShare, ArchiveFileShare {
  const SharePlusFileShare({
    Future<Directory> Function()? temporaryDirectory,
    Future<ShareResult> Function(ShareParams)? share,
    Future<File> Function(File source, String target)? copyArchive,
  }) : _temporaryDirectory = temporaryDirectory,
       _share = share,
       _copyArchive = copyArchive;

  final Future<Directory> Function()? _temporaryDirectory;
  final Future<ShareResult> Function(ShareParams)? _share;
  final Future<File> Function(File source, String target)? _copyArchive;

  @override
  Future<FileShareOutcome> shareArchive(
    PreparedFoodArchive archive, {
    bool Function()? isCurrent,
  }) async {
    ensureArchiveCurrent(isCurrent);
    if (!isSafeExportFileName(archive.name) || !archive.name.endsWith('.zip')) {
      throw ArgumentError.value(archive.name, 'archive.name');
    }
    final Directory temporary =
        await (_temporaryDirectory ?? getTemporaryDirectory)();
    ensureArchiveCurrent(isCurrent);
    final BinaryExportArtifact retained = await BinaryExportArtifact.create(
      temporaryDirectory: temporary,
      name: archive.name,
    );
    bool handoffStarted = false;
    try {
      ensureArchiveCurrent(isCurrent);
      final File source = File(archive.path);
      final File written =
          await (_copyArchive?.call(source, retained.path) ??
              source.copy(retained.path));
      ensureArchiveCurrent(isCurrent);
      // There is no await between this guard and the platform invocation.
      // Once handed off, another app may read the file even after an error.
      handoffStarted = true;
      final ShareResult result = await (_share ?? SharePlus.instance.share)(
        ShareParams(
          files: <XFile>[XFile(written.path, mimeType: 'application/zip')],
          fileNameOverrides: <String>[archive.name],
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => FileShareOutcome.actionSelected,
        ShareResultStatus.dismissed => FileShareOutcome.dismissed,
        ShareResultStatus.unavailable => FileShareOutcome.unavailable,
      };
    } finally {
      if (!handoffStarted) await retained.discard();
    }
  }

  @override
  Future<FileShareOutcome> share(ExportedFile file) async {
    final Directory temporary =
        await (_temporaryDirectory ?? getTemporaryDirectory)();
    final Directory dir = await temporary.createTemp('hearth-export-');
    final File written = File('${dir.path}/${file.name}');
    await written.writeAsString(file.contents, flush: true);

    final ShareResult result = await (_share ?? SharePlus.instance.share)(
      ShareParams(
        files: <XFile>[XFile(written.path, mimeType: 'application/json')],
        fileNameOverrides: <String>[file.name],
      ),
    );
    // Success means the OS reported an action selection, not a saved file.
    return switch (result.status) {
      ShareResultStatus.success => FileShareOutcome.actionSelected,
      ShareResultStatus.dismissed => FileShareOutcome.dismissed,
      ShareResultStatus.unavailable => FileShareOutcome.unavailable,
    };
  }
}
