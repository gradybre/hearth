import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'data_export.dart';

/// Handing the export to the operating system (spec §7.4).
///
/// The only file in the app that touches `share_plus`, so swapping the share
/// sheet for a save dialog later is one class rather than a search (rule 7).
///
/// The file is written to the temporary directory rather than to app support:
/// once it has been shared it is the OS's copy that matters, and a growing
/// pile of dated exports inside the app is a leak nobody would ever look for.
class SharePlusFileShare implements FileShare {
  const SharePlusFileShare();

  @override
  Future<void> share(ExportedFile file) async {
    final Directory dir = await getTemporaryDirectory();
    final File written = File('${dir.path}/${file.name}');
    await written.writeAsString(file.contents, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(written.path, mimeType: 'application/json')],
        fileNameOverrides: <String>[file.name],
      ),
    );
  }
}
