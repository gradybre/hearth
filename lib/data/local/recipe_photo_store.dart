import 'dart:io';

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
  ///
  /// **Must equal the recipe-photos bucket's `file_size_limit`**, which a
  /// schema guard asserts. Equality is the point: a photo that saves locally
  /// always uploads, so there is no third state where an image lives on one
  /// device for ever for reasons the user cannot see. It came down from 12 MB
  /// when photos started leaving the device — 12 MB over LTE is a minute,
  /// unresumable, and restarts from zero, for a file the phone picker never
  /// produces (it downscales to a few hundred KB).
  static const int maxBytes = 4 * 1024 * 1024;

  /// How many times a failing upload or download is retried before it stops.
  ///
  /// There has to be a ceiling, and not only for politeness: writing the
  /// attempt count wakes the sync listener, which retries, which writes the
  /// count again. The loop terminates *only* because [pendingUploads] and
  /// [pendingDownloads] filter on being under this.
  static const int maxAttempts = 5;

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
            // remotePath is deliberately left null. A freshly taken photo has
            // never been uploaded, and a *replaced* one must forget the object
            // it used to be — otherwise it reads as cached-and-current and the
            // new bytes never leave the phone.
            syncAttempts: 0,
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
          for (final RecipePhotoRow row in rows)
            if (row.fileName case final String name) row.recipeId: name,
        },
      );

  /// One recipe's photo row, for a screen that wants to say how sharing went.
  Stream<RecipePhotoRow?> watchRow(String recipeId) =>
      (_db.select(_db.recipePhotos)
            ..where(($RecipePhotosTable p) => p.recipeId.equals(recipeId)))
          .watchSingleOrNull();

  /// The directory photos are resolved against, for a widget that has a file
  /// name and needs the file.
  Future<Directory> photosDirectory() => _photosDir();

  // ── The sync pass's side of the table (spec §7.2) ─────────────────────────

  /// Photos taken here that the household has not got yet.
  ///
  /// `remotePath is null` is the whole predicate, which is why the backfill
  /// needs no code: every row that existed before photo sync has a null one,
  /// and is indistinguishable from a photo taken thirty seconds ago.
  Future<List<RecipePhotoRow>> pendingUploads({int limit = 3}) =>
      (_db.select(_db.recipePhotos)
            ..where(
              ($RecipePhotosTable p) =>
                  p.remotePath.isNull() &
                  p.fileName.isNotNull() &
                  p.syncAttempts.isSmallerThanValue(maxAttempts),
            )
            ..orderBy(<OrderClauseGenerator<$RecipePhotosTable>>[
              ($RecipePhotosTable p) => OrderingTerm(
                expression: p.updatedAt,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(limit))
          .get();

  /// What this device is missing, newest recipe first.
  ///
  /// A row is a candidate when it holds no file, or holds a file for a
  /// different object than the one the recipe now points at. The attempt count
  /// stops a broken object retrying for ever — but a *changed* `photoUrl`
  /// clears the way again regardless, so a partner replacing a bad photo
  /// unsticks it without anyone clearing state by hand.
  Future<List<({String recipeId, String path})>> pendingDownloads({
    int limit = 10,
  }) async {
    final List<TypedResult> rows =
        await (_db.select(_db.recipes).join(<Join<HasResultSet, dynamic>>[
                leftOuterJoin(
                  _db.recipePhotos,
                  _db.recipePhotos.recipeId.equalsExp(_db.recipes.id),
                ),
              ])
              ..where(
                _db.recipes.photoUrl.isNotNull() &
                    _db.recipes.isDeleted.equals(false),
              )
              ..orderBy(<OrderingTerm>[
                OrderingTerm(
                  expression: _db.recipes.updatedAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();

    final List<({String recipeId, String path})> wanted =
        <({String recipeId, String path})>[];
    for (final TypedResult row in rows) {
      final RecipeRow recipe = row.readTable(_db.recipes);
      final RecipePhotoRow? photo = row.readTableOrNull(_db.recipePhotos);
      final String path = recipe.photoUrl!;

      final bool cached = photo?.remotePath == path && photo?.fileName != null;
      final bool changed = photo != null && photo.remotePath != path;
      final bool exhausted =
          (photo?.syncAttempts ?? 0) >= maxAttempts && !changed;
      if (cached || exhausted) continue;

      wanted.add((recipeId: recipe.id, path: path));
      if (wanted.length >= limit) break;
    }
    return wanted;
  }

  /// Records that the local file is now a copy of [path].
  ///
  /// Called inside the same transaction as the recipe's `photoUrl` write. Split
  /// apart, a replacement briefly reads as stale and the *old* photo gets
  /// downloaded over the new one.
  Future<void> markUploaded({required String recipeId, required String path}) =>
      (_db.update(
        _db.recipePhotos,
      )..where(($RecipePhotosTable p) => p.recipeId.equals(recipeId))).write(
        RecipePhotosCompanion(
          remotePath: Value<String?>(path),
          syncAttempts: const Value<int>(0),
          syncError: const Value<String?>(null),
        ),
      );

  /// Stores a photo pulled down from the household's bucket.
  Future<void> saveDownloaded({
    required String recipeId,
    required String path,
    required Uint8List bytes,
    required DateTime now,
  }) async {
    final String fileName =
        '$recipeId-${now.microsecondsSinceEpoch}.'
        '${path.split('.').last}';
    final Directory dir = await _photosDir();
    await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);

    final String? previous = await fileNameFor(recipeId);
    await _db
        .into(_db.recipePhotos)
        .insertOnConflictUpdate(
          RecipePhotoRow(
            recipeId: recipeId,
            fileName: fileName,
            remotePath: path,
            syncAttempts: 0,
            updatedAt: now,
          ),
        );
    if (previous != null && previous != fileName) await _deleteFile(previous);
  }

  /// One more failed go, with what went wrong.
  Future<void> markSyncFailed({
    required String recipeId,
    required String error,
    String? path,
  }) async {
    final RecipePhotoRow? row =
        await (_db.select(_db.recipePhotos)
              ..where(($RecipePhotosTable p) => p.recipeId.equals(recipeId)))
            .getSingleOrNull();

    if (row == null) {
      // A download that failed before anything local existed still has to be
      // remembered, or it retries for ever.
      await _db
          .into(_db.recipePhotos)
          .insert(
            RecipePhotoRow(
              recipeId: recipeId,
              remotePath: path,
              syncAttempts: 1,
              syncError: error,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
      return;
    }

    await (_db.update(
      _db.recipePhotos,
    )..where(($RecipePhotosTable p) => p.recipeId.equals(recipeId))).write(
      RecipePhotosCompanion(
        syncAttempts: Value<int>(row.syncAttempts + 1),
        syncError: Value<String?>(error),
      ),
    );
  }

  /// How much photo work is outstanding, for the sync trigger.
  Stream<int> watchPendingWork() => _db
      .select(_db.recipePhotos)
      .watch()
      .map(
        (List<RecipePhotoRow> rows) => rows
            .where(
              (RecipePhotoRow r) =>
                  r.remotePath == null && r.syncAttempts < maxAttempts,
            )
            .length,
      );

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
