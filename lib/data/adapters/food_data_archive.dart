import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

import '../local/recipe_photo_store.dart';
import 'archive_photo_reader.dart';
import 'binary_export_artifact.dart';
import 'data_export.dart';
import 'readable_archive_rows.dart';

export 'binary_export_artifact.dart' show ArchivePreparationCancelled;

@immutable
class ArchiveProgress {
  const ArchiveProgress({
    required this.message,
    this.completedPhotos = 0,
    this.totalPhotos = 0,
  });

  final String message;
  final int completedPhotos;
  final int totalPhotos;
}

@immutable
class ArchiveFileFact {
  const ArchiveFileFact({required this.path, required this.bytes});
  final String path;
  final int bytes;
}

@immutable
class ArchivePhotoFact {
  const ArchivePhotoFact({
    required this.recipeId,
    required this.recipeTitle,
    required this.path,
  });
  final String recipeId;
  final String recipeTitle;
  final String path;
}

@immutable
class ArchivePhotoOmission {
  const ArchivePhotoOmission({
    required this.recipeId,
    required this.recipeTitle,
    required this.reason,
  });
  final String recipeId;
  final String recipeTitle;
  final String reason;
}

/// The immutable facts and exact bytes approved in the archive review.
/// Sharing retains a separate file, so discarding this preparation never
/// removes a receiving application's copy.
@immutable
class PreparedFoodArchive {
  PreparedFoodArchive({
    required this.snapshot,
    required this.name,
    required this.path,
    required this.bytes,
    required List<ArchiveFileFact> files,
    required this.photosRequested,
    required List<ArchivePhotoFact> includedPhotos,
    required List<ArchivePhotoOmission> unavailablePhotos,
    BinaryExportArtifact? artifact,
  }) : files = List<ArchiveFileFact>.unmodifiable(files),
       includedPhotos = List<ArchivePhotoFact>.unmodifiable(includedPhotos),
       unavailablePhotos = List<ArchivePhotoOmission>.unmodifiable(
         unavailablePhotos,
       ),
       _artifact = artifact;

  final ExportSnapshot snapshot;
  final String name;
  final String path;
  final int bytes;
  final List<ArchiveFileFact> files;
  final bool photosRequested;
  final List<ArchivePhotoFact> includedPhotos;
  final List<ArchivePhotoOmission> unavailablePhotos;
  final BinaryExportArtifact? _artifact;

  Future<void> discard() async {
    final BinaryExportArtifact? artifact = _artifact;
    if (artifact == null) return;
    if (artifact.path != path || artifact.name != name) {
      throw StateError('Archive does not own this temporary file.');
    }
    await artifact.discard();
  }
}

/// Creates a readable copy from one export snapshot. Only optional photo
/// bytes are fetched later, using the identities captured with that snapshot.
class FoodDataArchive {
  FoodDataArchive({
    required DataExport dataExport,
    ArchivePhotoReader? photos,
    Future<Directory> Function()? temporaryDirectory,
    Duration photoReadTimeout = const Duration(seconds: 15),
  }) : _dataExport = dataExport,
       _photos = photos,
       _photoReadTimeout = photoReadTimeout,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final DataExport _dataExport;
  final ArchivePhotoReader? _photos;
  final Future<Directory> Function() _temporaryDirectory;
  final Duration _photoReadTimeout;

  Future<ArchivePhotoRead> _readPhoto(
    ExportPhotoReference reference,
    bool Function()? isCurrent,
  ) async {
    final Completer<ArchivePhotoRead> stopped = Completer<ArchivePhotoRead>();
    final Timer deadline = Timer(_photoReadTimeout, () {
      if (!stopped.isCompleted) {
        stopped.complete(
          const ArchivePhotoRead.unavailable(
            'The photo request timed out. Prepare another archive to try again.',
          ),
        );
      }
    });
    final Timer? cancellation = isCurrent == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 100), (_) {
            if (!isCurrent() && !stopped.isCompleted) {
              stopped.completeError(const ArchivePreparationCancelled());
            }
          });
    try {
      // The adapter's network future cannot always be aborted. Its late
      // result/error stays observed by any(), but can no longer write the ZIP.
      return await Future.any<ArchivePhotoRead>(<Future<ArchivePhotoRead>>[
        _photos!.read(reference, isCurrent: isCurrent),
        stopped.future,
      ]);
    } finally {
      deadline.cancel();
      cancellation?.cancel();
    }
  }

  Future<PreparedFoodArchive> prepare({
    required String householdId,
    required String userId,
    bool includePhotos = false,
    void Function(ArchiveProgress)? onProgress,
    bool Function()? isCurrent,
  }) async {
    ensureArchiveCurrent(isCurrent);
    onProgress?.call(const ArchiveProgress(message: 'Reading food data'));
    final ExportSnapshot snapshot = await _dataExport.prepare(
      householdId: householdId,
      userId: userId,
    );
    ensureArchiveCurrent(isCurrent);
    if (snapshot.householdId != householdId || snapshot.userId != userId) {
      throw const ArchivePreparationCancelled();
    }
    final ReadableArchiveRows rows = ReadableArchiveRows(snapshot);
    final String date = snapshot.capturedAt
        .toUtc()
        .toIso8601String()
        .split('T')
        .first;
    final String name = 'hearth-readable-$date.zip';
    final Directory temporary = await _temporaryDirectory();
    ensureArchiveCurrent(isCurrent);
    final BinaryExportArtifact artifact = await BinaryExportArtifact.create(
      temporaryDirectory: temporary,
      name: name,
    );
    _ArchiveWriter? writer;
    try {
      ensureArchiveCurrent(isCurrent);
      writer = _ArchiveWriter(artifact, isCurrent);
      if (!isSafeExportFileName(snapshot.file.name)) {
        throw const FormatException('The original export filename is invalid.');
      }
      await writer.text('original/${snapshot.file.name}', <String>[
        snapshot.file.contents,
      ]);
      onProgress?.call(
        const ArchiveProgress(message: 'Writing readable food data'),
      );
      await writer.text('logs.csv', rows.meals(logged: true));
      await writer.text('plans.csv', rows.meals(logged: false));
      await writer.text('targets.csv', rows.targets());
      await writer.text('foods.csv', rows.foods());
      for (final MapEntry<String, String> recipe in rows.recipes()) {
        await writer.text(recipe.key, <String>[recipe.value]);
      }
      final List<ArchivePhotoFact> included = <ArchivePhotoFact>[];
      final List<ArchivePhotoOmission> unavailable = <ArchivePhotoOmission>[];
      final int totalPhotos = includePhotos
          ? snapshot.photoReferences.length
          : 0;
      if (includePhotos) {
        for (int i = 0; i < snapshot.photoReferences.length; i++) {
          ensureArchiveCurrent(isCurrent);
          final ExportPhotoReference reference = snapshot.photoReferences[i];
          onProgress?.call(
            ArchiveProgress(
              message: 'Preparing recipe photos',
              completedPhotos: i,
              totalPhotos: totalPhotos,
            ),
          );
          final ArchivePhotoRead result;
          if (reference.householdId != householdId ||
              !rows.containsRecipe(reference.recipeId)) {
            result = const ArchivePhotoRead.unavailable(
              'The photo is outside this captured household data.',
            );
          } else if (_photos == null) {
            result = const ArchivePhotoRead.unavailable(
              'Photo access is unavailable on this device.',
            );
          } else {
            result = await _readPhoto(reference, isCurrent);
          }
          ensureArchiveCurrent(isCurrent);
          final bytes = result.bytes;
          final String? extension = result.extension;
          if (bytes != null &&
              bytes.isNotEmpty &&
              bytes.lengthInBytes <= RecipePhotoStore.maxBytes &&
              <String>{
                'jpg',
                'jpeg',
                'png',
                'webp',
                'heic',
                'heif',
              }.contains(extension)) {
            final String path =
                'photos/${safeArchiveStem(i + 1, reference.recipeTitle)}.$extension';
            await writer.bytes(path, bytes);
            included.add(
              ArchivePhotoFact(
                recipeId: reference.recipeId,
                recipeTitle: reference.recipeTitle,
                path: path,
              ),
            );
          } else {
            unavailable.add(
              ArchivePhotoOmission(
                recipeId: reference.recipeId,
                recipeTitle: reference.recipeTitle,
                reason:
                    result.reason ??
                    'The captured photo could not be read safely.',
              ),
            );
          }
        }
      }
      await writer.text(
        'photos-unavailable.csv',
        archiveCsv(<List<Object?>>[
          <Object?>['recipe_id', 'recipe_title', 'reason'],
          for (final ArchivePhotoOmission omission in unavailable)
            <Object?>[omission.recipeId, omission.recipeTitle, omission.reason],
        ]),
      );
      await writer.text('READ-ME.txt', <String>[
        rows.guide(
          photosRequested: includePhotos,
          includedPhotos: included.length,
          unavailablePhotos: unavailable.length,
        ),
      ]);
      await writer.text('archive-manifest.json', <String>[
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'format': 'hearth-readable-archive',
          'version': 1,
          'captured_at': snapshot.capturedAt.toUtc().toIso8601String(),
          'household_id': householdId,
          'user_id': userId,
          'original_json': 'original/${snapshot.file.name}',
          'original_json_unchanged': true,
          'photos_requested': includePhotos,
          'included_photos': <Map<String, Object?>>[
            for (final ArchivePhotoFact photo in included)
              <String, Object?>{
                'recipe_id': photo.recipeId,
                'recipe_title': photo.recipeTitle,
                'path': photo.path,
              },
          ],
          'unavailable_photos': <Map<String, Object?>>[
            for (final ArchivePhotoOmission photo in unavailable)
              <String, Object?>{
                'recipe_id': photo.recipeId,
                'recipe_title': photo.recipeTitle,
                'reason': photo.reason,
              },
          ],
          'files_excluding_this_manifest': <Map<String, Object?>>[
            for (final ArchiveFileFact file in writer.files)
              <String, Object?>{'path': file.path, 'bytes': file.bytes},
          ],
          'note': 'A readable local copy, not a restore file or proof of cloud completeness. See READ-ME.txt and the original JSON manifest.',
        }),
      ]);
      await writer.close();
      ensureArchiveCurrent(isCurrent);
      final int bytes = await File(artifact.path).length();
      ensureArchiveCurrent(isCurrent);
      onProgress?.call(
        ArchiveProgress(
          message: 'Archive ready to review',
          completedPhotos: totalPhotos,
          totalPhotos: totalPhotos,
        ),
      );
      ensureArchiveCurrent(isCurrent);
      return PreparedFoodArchive(
        snapshot: snapshot,
        name: name,
        path: artifact.path,
        bytes: bytes,
        files: writer.files,
        photosRequested: includePhotos,
        includedPhotos: included,
        unavailablePhotos: unavailable,
        artifact: artifact,
      );
    } catch (_) {
      try {
        await writer?.close();
      } finally {
        await artifact.discard();
      }
      rethrow;
    }
  }
}

/// Each member is staged separately and streamed into a file-backed encoder.
/// Photo data is released between members; the completed ZIP is never held
/// as one in-memory byte buffer.
class _ArchiveWriter {
  _ArchiveWriter(this.artifact, this.isCurrent) {
    _encoder.create(artifact.path);
  }

  final BinaryExportArtifact artifact;
  final bool Function()? isCurrent;
  final ZipFileEncoder _encoder = ZipFileEncoder();
  final List<ArchiveFileFact> files = <ArchiveFileFact>[];
  bool _closed = false;

  File get _part => File('${artifact.directory.path}/member.tmp');

  Future<void> text(String name, Iterable<String> chunks) async {
    ensureArchiveCurrent(isCurrent);
    final IOSink sink = _part.openWrite(encoding: utf8);
    try {
      int count = 0;
      for (final String chunk in chunks) {
        sink.write(chunk);
        if (++count % 128 == 0) {
          await sink.flush();
          ensureArchiveCurrent(isCurrent);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    ensureArchiveCurrent(isCurrent);
    await _add(name);
  }

  Future<void> bytes(String name, List<int> bytes) async {
    ensureArchiveCurrent(isCurrent);
    await _part.writeAsBytes(bytes, flush: true);
    ensureArchiveCurrent(isCurrent);
    await _add(name);
  }

  Future<void> _add(String name) async {
    final int bytes = await _part.length();
    ensureArchiveCurrent(isCurrent);
    await _encoder.addFile(_part, name);
    ensureArchiveCurrent(isCurrent);
    files.add(ArchiveFileFact(path: name, bytes: bytes));
    await _part.delete();
    ensureArchiveCurrent(isCurrent);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _encoder.close();
  }
}
