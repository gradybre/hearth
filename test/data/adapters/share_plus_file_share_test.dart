import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/adapters/share_plus_file_share.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory directory;
  const ExportedFile file = ExportedFile(
    name: 'hearth-2026-10-01.json',
    contents: '{"recipe": "Crème brûlée", "version": 2}',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hearth-share-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  for (final MapEntry<ShareResultStatus, FileShareOutcome> outcome
      in <ShareResultStatus, FileShareOutcome>{
        ShareResultStatus.success: FileShareOutcome.actionSelected,
        ShareResultStatus.dismissed: FileShareOutcome.dismissed,
        ShareResultStatus.unavailable: FileShareOutcome.unavailable,
      }.entries) {
    test(
      'reports ${outcome.key.name} without inventing saved status',
      () async {
        final SharePlusFileShare adapter = SharePlusFileShare(
          temporaryDirectory: () async => directory,
          share: (ShareParams params) async => ShareResult('', outcome.key),
        );

        expect(await adapter.share(file), outcome.value);
      },
    );
  }

  test('hands the OS exactly the reviewed UTF-8 file and name', () async {
    ShareParams? received;
    final SharePlusFileShare adapter = SharePlusFileShare(
      temporaryDirectory: () async => directory,
      share: (ShareParams params) async {
        received = params;
        final XFile shared = params.files!.single;
        expect(await shared.readAsBytes(), utf8.encode(file.contents));
        expect(shared.mimeType, 'application/json');
        return const ShareResult('save-action', ShareResultStatus.success);
      },
    );

    await adapter.share(file);

    expect(received!.fileNameOverrides, <String>[file.name]);
    expect(received!.files!.single.name, file.name);
  });

  test(
    'a later export with the same name cannot replace a shared file',
    () async {
      final List<XFile> sharedFiles = <XFile>[];
      final SharePlusFileShare adapter = SharePlusFileShare(
        temporaryDirectory: () async => directory,
        share: (ShareParams params) async {
          sharedFiles.add(params.files!.single);
          return const ShareResult('save-action', ShareResultStatus.success);
        },
      );
      final ExportedFile later = ExportedFile(
        name: file.name,
        contents: '{"recipe": "Later edit", "version": 2}',
      );

      await adapter.share(file);
      await adapter.share(later);

      expect(await sharedFiles.first.readAsString(), file.contents);
      expect(await sharedFiles.last.readAsString(), later.contents);
      expect(sharedFiles.first.path, isNot(sharedFiles.last.path));
    },
  );

  test(
    'platform errors remain errors so the review can offer a retry',
    () async {
      final StateError failure = StateError('share sheet failed');
      final SharePlusFileShare adapter = SharePlusFileShare(
        temporaryDirectory: () async => directory,
        share: (ShareParams params) async => throw failure,
      );

      await expectLater(adapter.share(file), throwsA(same(failure)));
    },
  );

  test('a temporary-file failure does not open a share sheet', () async {
    bool shareOpened = false;
    final StateError failure = StateError('temporary storage unavailable');
    final SharePlusFileShare adapter = SharePlusFileShare(
      temporaryDirectory: () async => throw failure,
      share: (ShareParams params) async {
        shareOpened = true;
        return ShareResult.unavailable;
      },
    );

    await expectLater(adapter.share(file), throwsA(same(failure)));
    expect(shareOpened, isFalse);
  });
}
