import 'dart:io';
import 'dart:typed_data';

import '../local/hearth_database.dart';
import '../local/recipe_photo_store.dart';
import '../remote/photo_storage.dart';
import 'binary_export_artifact.dart';
import 'data_export.dart';

class ArchivePhotoRead {
  const ArchivePhotoRead.available(this.bytes, this.extension) : reason = null;
  const ArchivePhotoRead.unavailable(this.reason)
    : bytes = null,
      extension = null;

  final Uint8List? bytes;
  final String? extension;
  final String? reason;
}

abstract interface class ArchivePhotoReader {
  Future<ArchivePhotoRead> read(
    ExportPhotoReference reference, {
    bool Function()? isCurrent,
  });
}

/// Reads only a captured, household-scoped photo identity. It never visits a
/// recipe source URL, and never asks fileFor(recipeId) for a later photograph.
class StoredArchivePhotoReader implements ArchivePhotoReader {
  StoredArchivePhotoReader({
    required HearthDatabase database,
    required RecipePhotoStore photos,
    PhotoStorage? storage,
  }) : _db = database,
       _photos = photos,
       _storage = storage;

  final HearthDatabase _db;
  final RecipePhotoStore _photos;
  final PhotoStorage? _storage;

  @override
  Future<ArchivePhotoRead> read(
    ExportPhotoReference reference, {
    bool Function()? isCurrent,
  }) async {
    ensureArchiveCurrent(isCurrent);
    final RecipeRow? recipe =
        await (_db.select(_db.recipes)
              ..where(($RecipesTable r) => r.id.equals(reference.recipeId)))
            .getSingleOrNull();
    ensureArchiveCurrent(isCurrent);
    if (recipe == null || recipe.householdId != reference.householdId) {
      return const ArchivePhotoRead.unavailable(
        'The captured recipe is no longer available in this household.',
      );
    }

    final bool pendingLocal =
        reference.localFileName != null && reference.localRemotePath == null;
    final bool matchingLocal =
        pendingLocal || reference.localRemotePath == reference.remotePath;
    if (reference.localFileName != null && matchingLocal) {
      final ArchivePhotoRead? local = await _readLocal(reference, isCurrent);
      ensureArchiveCurrent(isCurrent);
      if (local != null) return local;
      // A pending local replacement is not the recipe's older remote image.
      if (pendingLocal) {
        return const ArchivePhotoRead.unavailable(
          'The photo captured on this device is no longer available.',
        );
      }
    }

    final String? path = reference.remotePath;
    if (path == null || !_safeRemotePath(path, reference.recipeId)) {
      return const ArchivePhotoRead.unavailable(
        'No supported photo reference was recorded for this recipe.',
      );
    }
    if (_storage == null) {
      return const ArchivePhotoRead.unavailable(
        'The photo is not on this device and downloading is unavailable.',
      );
    }
    try {
      ensureArchiveCurrent(isCurrent);
      final Uint8List bytes = await _storage.download(path);
      ensureArchiveCurrent(isCurrent);
      if (bytes.isEmpty || bytes.lengthInBytes > RecipePhotoStore.maxBytes) {
        return const ArchivePhotoRead.unavailable(
          'The photo is empty or exceeds the supported photo size.',
        );
      }
      return ArchivePhotoRead.available(bytes, path.split('.').last);
    } on ArchivePreparationCancelled {
      rethrow;
    } on PhotoObjectMissing {
      return const ArchivePhotoRead.unavailable(
        'The captured photo is no longer in household storage.',
      );
    } catch (_) {
      ensureArchiveCurrent(isCurrent);
      return const ArchivePhotoRead.unavailable(
        'The photo could not be downloaded. It may be offline or unavailable.',
      );
    }
  }

  Future<ArchivePhotoRead?> _readLocal(
    ExportPhotoReference reference,
    bool Function()? isCurrent,
  ) async {
    final String name = reference.localFileName!;
    if (!isSafeExportFileName(name) ||
        !name.startsWith('${reference.recipeId}-') ||
        !_extensions.contains(name.split('.').last.toLowerCase())) {
      return null;
    }
    try {
      if (!await _localIdentityMatches(reference)) return null;
      ensureArchiveCurrent(isCurrent);
      final Directory directory = await _photos.photosDirectory();
      ensureArchiveCurrent(isCurrent);
      final String root = await directory.resolveSymbolicLinks();
      ensureArchiveCurrent(isCurrent);
      final File file = File('$root/$name');
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      ensureArchiveCurrent(isCurrent);
      if (await file.length() > RecipePhotoStore.maxBytes) return null;
      ensureArchiveCurrent(isCurrent);
      final Uint8List bytes = await file.readAsBytes();
      ensureArchiveCurrent(isCurrent);
      if (bytes.isEmpty || bytes.lengthInBytes > RecipePhotoStore.maxBytes) {
        return null;
      }
      if (!await _localIdentityMatches(reference)) return null;
      ensureArchiveCurrent(isCurrent);
      return ArchivePhotoRead.available(
        bytes,
        name.split('.').last.toLowerCase(),
      );
    } on ArchivePreparationCancelled {
      rethrow;
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> _localIdentityMatches(ExportPhotoReference reference) async {
    final RecipePhotoRow? row =
        await (_db.select(_db.recipePhotos)..where(
              ($RecipePhotosTable p) => p.recipeId.equals(reference.recipeId),
            ))
            .getSingleOrNull();
    return row != null &&
        row.fileName == reference.localFileName &&
        row.updatedAt == reference.localUpdatedAt;
  }

  static const Set<String> _extensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };

  static bool _safeRemotePath(String path, String recipeId) =>
      RecipePhotoPath.recipeIdOf(path) == recipeId &&
      RegExp(
        r'^[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9_-]*\.(jpg|jpeg|png|webp|heic|heif)$',
      ).hasMatch(path);
}
