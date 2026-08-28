import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import 'hearth_database.dart';

/// Where a recipe's hero photo lives on this device (spec §5.2).
///
/// The bytes go on disk and only the file name goes in the database. Storing
/// an absolute path would break on the next install — iOS moves an app's
/// container — and storing the image itself in sqlite would drag several
/// megabytes through every query that touches a recipe.
class RecipePhotoStore {
  RecipePhotoStore(this._db, {required Future<Directory> Function() directory})
    : _directory = directory;

  /// A photo larger than this is refused rather than quietly stored.
  ///
  /// The mobile picker downscales before handing anything over; the desktop
  /// one cannot, so a full-resolution import is the case this catches. Better
  /// a clear no than a library that quietly grows by 40 MB a recipe.
  static const int maxBytes = 12 * 1024 * 1024;

  final HearthDatabase _db;
  final Future<Directory> Function() _directory;

  Future<Directory> _photosDir() async {
    final Directory dir = Directory(
      '${(await _directory()).path}/recipe_photos',
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes the photo and points the recipe at it, replacing any it had.
  Future<void> save({
    required String recipeId,
    required Uint8List bytes,
    required String extension,
    required DateTime now,
  }) async {
    if (bytes.lengthInBytes > maxBytes) {
      throw const PhotoTooLarge();
    }

    // The name carries the timestamp so a replacement lands on a new file:
    // overwriting in place leaves Flutter's image cache showing the old one.
    final String fileName =
        '$recipeId-${now.microsecondsSinceEpoch}.$extension';
    final Directory dir = await _photosDir();
    await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);

    final String? previous = await fileNameFor(recipeId);
    await _db
        .into(_db.recipePhotos)
        .insertOnConflictUpdate(
          RecipePhotoRow(
            recipeId: recipeId,
            fileName: fileName,
            updatedAt: now,
          ),
        );
    if (previous != null && previous != fileName) {
      await _deleteFile(previous);
    }
  }

  Future<String?> fileNameFor(String recipeId) async {
    final RecipePhotoRow? row =
        await (_db.select(_db.recipePhotos)
              ..where(($RecipePhotosTable p) => p.recipeId.equals(recipeId)))
            .getSingleOrNull();
    return row?.fileName;
  }

  /// The photo on disk, or null when there is none — or when the row survived
  /// a file that did not, which a reinstall can do.
  Future<File?> fileFor(String recipeId) async {
    final String? name = await fileNameFor(recipeId);
    if (name == null) return null;
    final File file = File('${(await _photosDir()).path}/$name');
    return file.existsSync() ? file : null;
  }

  Future<void> remove(String recipeId) async {
    final String? name = await fileNameFor(recipeId);
    await (_db.delete(
      _db.recipePhotos,
    )..where(($RecipePhotosTable p) => p.recipeId.equals(recipeId))).go();
    if (name != null) await _deleteFile(name);
  }

  /// Every recipe's photo file name, for a library that shows thumbnails.
  Stream<Map<String, String>> watchAll() => _db
      .select(_db.recipePhotos)
      .watch()
      .map(
        (List<RecipePhotoRow> rows) => <String, String>{
          for (final RecipePhotoRow row in rows) row.recipeId: row.fileName,
        },
      );

  /// The directory photos are resolved against, for a widget that has a file
  /// name and needs the file.
  Future<Directory> photosDirectory() => _photosDir();

  Future<void> _deleteFile(String fileName) async {
    final File file = File('${(await _photosDir()).path}/$fileName');
    if (file.existsSync()) await file.delete();
  }
}

/// Thrown when a picked photo is too big to keep.
class PhotoTooLarge implements Exception {
  const PhotoTooLarge();

  @override
  String toString() => 'That photo is too large to add.';
}
