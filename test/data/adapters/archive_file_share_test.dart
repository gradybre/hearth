import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/archive_file_share.dart';
import 'package:hearth/data/adapters/binary_export_artifact.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/adapters/food_data_archive.dart';
import 'package:hearth/data/adapters/share_plus_file_share.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archive-share-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<PreparedFoodArchive> prepare(List<int> bytes) async {
    final BinaryExportArtifact artifact = await BinaryExportArtifact.create(
      temporaryDirectory: directory,
      name: 'hearth-readable-2026-10-01.zip',
    );
    await File(artifact.path).writeAsBytes(bytes);
    return _prepared(artifact.path, bytes.length, artifact: artifact);
  }

  test('hands off the reviewed bytes with ZIP MIME and preserves receiving copy after discard', () async {
    final PreparedFoodArchive prepared = await prepare(<int>[
      80,
      75,
      3,
      4,
      1,
      2,
      3,
    ]);
    String? sharedPath;
    final ArchiveFileShare share = SharePlusFileShare(
      temporaryDirectory: () async => directory,
      share: (ShareParams params) async {
        final XFile file = params.files!.single;
        sharedPath = file.path;
        expect(file.mimeType, 'application/zip');
        expect(params.fileNameOverrides, <String>[prepared.name]);
        expect(sharedPath, isNot(prepared.path));
        await prepared.discard();
        expect(await file.readAsBytes(), <int>[80, 75, 3, 4, 1, 2, 3]);
        return const ShareResult('selected', ShareResultStatus.success);
      },
    );
    expect(await share.shareArchive(prepared), FileShareOutcome.actionSelected);
    expect(await File(sharedPath!).exists(), isTrue);
    expect(await File(prepared.path).exists(), isFalse);
  });

  for (final MapEntry<ShareResultStatus, FileShareOutcome> status
      in <ShareResultStatus, FileShareOutcome>{
        ShareResultStatus.dismissed: FileShareOutcome.dismissed,
        ShareResultStatus.unavailable: FileShareOutcome.unavailable,
      }.entries) {
    test('archive receipt preserves ${status.key.name}', () async {
      final PreparedFoodArchive prepared = await prepare(<int>[1, 2]);
      final SharePlusFileShare share = SharePlusFileShare(
        temporaryDirectory: () async => directory,
        share: (_) async => ShareResult('', status.key),
      );
      expect(await share.shareArchive(prepared), status.value);
    });
  }

  test('same-name shares never replace a receiving application file', () async {
    final List<XFile> files = <XFile>[];
    final SharePlusFileShare share = SharePlusFileShare(
      temporaryDirectory: () async => directory,
      share: (ShareParams params) async {
        files.add(params.files!.single);
        return ShareResult.unavailable;
      },
    );
    final PreparedFoodArchive first = await prepare(<int>[1]);
    final PreparedFoodArchive second = await prepare(<int>[2]);
    await share.shareArchive(first);
    await share.shareArchive(second);
    await first.discard();
    await second.discard();
    expect(files.first.path, isNot(files.last.path));
    expect(await files.first.readAsBytes(), <int>[1]);
    expect(await files.last.readAsBytes(), <int>[2]);
  });

  test(
    'missing preparation and unsafe names never open a share callback',
    () async {
      bool opened = false;
      final SharePlusFileShare share = SharePlusFileShare(
        temporaryDirectory: () async => directory,
        share: (_) async {
          opened = true;
          return ShareResult.unavailable;
        },
      );
      await expectLater(
        share.shareArchive(_prepared('${directory.path}/missing.zip', 0)),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        share.shareArchive(
          _prepared('${directory.path}/missing.zip', 0, name: '../outside.zip'),
        ),
        throwsArgumentError,
      );
      expect(opened, isFalse);
    },
  );

  test(
    'platform failure remains an error instead of an invented receipt',
    () async {
      final StateError failure = StateError('synthetic platform refusal');
      final SharePlusFileShare share = SharePlusFileShare(
        temporaryDirectory: () async => directory,
        share: (_) async => throw failure,
      );
      await expectLater(
        share.shareArchive(await prepare(<int>[1])),
        throwsA(same(failure)),
      );
    },
  );

  test('discard requires its own artifact identity and never follows a substituted directory link', () async {
    final BinaryExportArtifact artifact = await BinaryExportArtifact.create(
      temporaryDirectory: directory,
      name: 'owned.zip',
    );
    final File unrelated = await File('${directory.path}/unrelated.txt')
        .writeAsString('keep');
    await expectLater(
      _prepared(unrelated.path, 4, artifact: artifact).discard(),
      throwsStateError,
    );
    expect(await unrelated.readAsString(), 'keep');
    final String owned = artifact.directory.path;
    await artifact.directory.delete();
    final Directory other = await Directory('${directory.path}/other').create();
    final File protected = await File('${other.path}/protected.txt')
        .writeAsString('keep too');
    await Link(owned).create(other.path);
    await artifact.discard();
    expect(await protected.readAsString(), 'keep too');
  });
  test('identity expiry during copy refuses platform hand-off and removes only the unused copy', () async {
    final PreparedFoodArchive prepared = await prepare(<int>[1, 2, 3]);
    bool current = true;
    bool platformOpened = false;
    String? copiedPath;
    final SharePlusFileShare share = SharePlusFileShare(
      temporaryDirectory: () async => directory,
      copyArchive: (File source, String target) async {
        final File copied = await source.copy(target);
        copiedPath = copied.path;
        current = false;
        return copied;
      },
      share: (_) async {
        platformOpened = true;
        return ShareResult.unavailable;
      },
    );
    Object? failure;
    try {
      await share.shareArchive(prepared, isCurrent: () => current);
    } catch (error) {
      failure = error;
    }
    expect(
      platformOpened,
      isFalse,
      reason: 'Identity changed before platform hand-off began.',
    );
    expect(failure, isA<ArchivePreparationCancelled>());
    expect(await File(copiedPath!).exists(), isFalse);
    expect(await File(copiedPath!).parent.exists(), isFalse);
    expect(await File(prepared.path).readAsBytes(), <int>[1, 2, 3]);
  });

  test(
    'identity expiry while locating temporary storage creates no retained file',
    () async {
      final PreparedFoodArchive prepared = await prepare(<int>[1]);
      bool current = true;
      bool opened = false;
      final SharePlusFileShare share = SharePlusFileShare(
        temporaryDirectory: () async {
          current = false;
          return directory;
        },
        share: (_) async {
          opened = true;
          return ShareResult.unavailable;
        },
      );
      await expectLater(
        share.shareArchive(prepared, isCurrent: () => current),
        throwsA(isA<ArchivePreparationCancelled>()),
      );
      expect(opened, isFalse);
      expect(await directory.list().toList(), hasLength(1));
    },
  );

  test(
    'identity expiry after platform hand-off cannot recall the receiving copy',
    () async {
      final PreparedFoodArchive prepared = await prepare(<int>[1]);
      bool current = true;
      String? copiedPath;
      final SharePlusFileShare share = SharePlusFileShare(
        temporaryDirectory: () async => directory,
        share: (ShareParams params) async {
          copiedPath = params.files!.single.path;
          current = false;
          return const ShareResult('selected', ShareResultStatus.success);
        },
      );
      expect(
        await share.shareArchive(prepared, isCurrent: () => current),
        FileShareOutcome.actionSelected,
      );
      await prepared.discard();
      expect(await File(copiedPath!).readAsBytes(), <int>[1]);
    },
  );
}

PreparedFoodArchive _prepared(
  String path,
  int bytes, {
  String name = 'hearth-readable-2026-10-01.zip',
  BinaryExportArtifact? artifact,
}) => PreparedFoodArchive(
  snapshot: ExportSnapshot(
    file: const ExportedFile(name: 'fixture.json', contents: '{}'),
    householdId: 'synthetic-home',
    userId: 'synthetic-user',
    capturedAt: DateTime.utc(2026, 10, 1),
    counts: const <String, int>{},
    loggedDayStart: null,
    loggedDayEnd: null,
    pendingChanges: 0,
    exclusions: const <String>[],
    missingReferences: const <String>[],
  ),
  name: name,
  path: path,
  bytes: bytes,
  files: const <ArchiveFileFact>[],
  photosRequested: false,
  includedPhotos: const <ArchivePhotoFact>[],
  unavailablePhotos: const <ArchivePhotoOmission>[],
  artifact: artifact,
);
