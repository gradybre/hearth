import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../local/hearth_database.dart';
import '../local/recipe_photo_store.dart';
import '../remote/photo_storage.dart';
import '../remote/remote_gateway.dart';
import '../repositories/recipe_repository.dart';

/// What one photo pass got through.
class PhotoSyncResult {
  const PhotoSyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.failed = 0,
    this.stoppedBecauseOffline = false,
  });

  final int uploaded;
  final int downloaded;
  final int failed;
  final bool stoppedBecauseOffline;
}

/// Carrying recipe photos between the two phones (spec §5.2, §7.2).
///
/// Runs inside the sync pass that already happens rather than on a schedule of
/// its own: a pass that has already woken the radio and authenticated can move
/// bytes for free, and there is still no polling timer anywhere in the app.
/// It runs *last*, because a missing photo blocks neither cooking nor logging,
/// and because the recipe row has to reach the server before the storage
/// policy will admit an object underneath it.
///
/// Deliberately **not** routed through [PendingWriteStore]. Its payload is
/// JSON in a text column, so a 4 MB photo would become ~5.5 MB of base64
/// dragged through every sync pass; and `hasPendingFor` matches on entity id
/// alone, so one stuck photo would freeze all sync for that recipe for ever.
class PhotoSync {
  PhotoSync({
    required HearthDatabase database,
    required RecipePhotoStore photos,
    required RecipeRepository recipes,
    required PhotoStorage storage,
    DateTime Function()? clock,
    String Function()? objectIdFactory,
  }) : _db = database,
       _photos = photos,
       _recipes = recipes,
       _storage = storage,
       _now = clock ?? DateTime.now,
       _newObjectId = objectIdFactory ?? const Uuid().v4;

  /// Uploads per pass. Lower than the download budget on purpose: a pass that
  /// uploads is spending the user's uplink, and a fifty-photo backfill spread
  /// across the day's ordinary syncs beats one burst on first launch.
  static const int uploadBudget = 3;
  static const int downloadBudget = 10;

  final HearthDatabase _db;
  final RecipePhotoStore _photos;
  final RecipeRepository _recipes;
  final PhotoStorage _storage;
  final DateTime Function() _now;
  final String Function() _newObjectId;

  /// Sends up photos this device has and the household does not.
  Future<PhotoSyncResult> push() async {
    int uploaded = 0;
    int failed = 0;

    for (final RecipePhotoRow row in await _photos.pendingUploads(
      limit: uploadBudget,
    )) {
      final File? file = await _photos.fileFor(row.recipeId);
      if (file == null) {
        // The row outlived its file — a reinstall can do this. Nothing to
        // send, and the download side will repair it if the household has a
        // copy.
        await _photos.markSyncFailed(
          recipeId: row.recipeId,
          error: 'The file is no longer on this device.',
        );
        failed++;
        continue;
      }

      final Uint8List bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > RecipePhotoStore.maxBytes) {
        // Saved under an older, larger ceiling. The bucket would refuse it
        // five times over; say so once instead.
        await _photos.markSyncFailed(
          recipeId: row.recipeId,
          error: 'This photo is too large to share. Replace it to sync it.',
        );
        failed++;
        continue;
      }

      final String path = RecipePhotoPath.build(
        recipeId: row.recipeId,
        objectId: _newObjectId(),
        extension: row.fileName!.split('.').last,
      );

      try {
        await _storage.upload(
          path: path,
          bytes: bytes,
          contentType: RecipePhotoPath.contentTypeOf(path),
        );
      } on RemoteUnavailable {
        // Offline is not a failed attempt. Burning one would mean five
        // supermarket trips could exhaust a photo that was never broken.
        return PhotoSyncResult(
          uploaded: uploaded,
          failed: failed,
          stoppedBecauseOffline: true,
        );
      } on Object catch (error) {
        await _photos.markSyncFailed(recipeId: row.recipeId, error: '$error');
        failed++;
        continue;
      }

      // One transaction. Split apart, a replaced photo briefly reads as stale
      // — remotePath new, photoUrl still old — and the download side would
      // fetch the *previous* image over the one just taken.
      await _db.transaction(() async {
        await _photos.markUploaded(recipeId: row.recipeId, path: path);
        await _recipes.setPhotoUrl(row.recipeId, path);
      });
      uploaded++;
    }

    return PhotoSyncResult(uploaded: uploaded, failed: failed);
  }

  /// Fetches photos the household has and this device does not.
  Future<PhotoSyncResult> pull() async {
    int downloaded = 0;
    int failed = 0;

    for (final ({String recipeId, String path}) want
        in await _photos.pendingDownloads(limit: downloadBudget)) {
      final Uint8List bytes;
      try {
        bytes = await _storage.download(want.path);
      } on RemoteUnavailable {
        return PhotoSyncResult(
          downloaded: downloaded,
          failed: failed,
          stoppedBecauseOffline: true,
        );
      } on PhotoObjectMissing {
        // Recorded so it stops retrying — but photo_url is deliberately left
        // alone. One device's failed GET is not evidence about a shared
        // field: the object may be fine and the failure a proxy hiccup, and
        // clearing it would push a destructive write to a partner who can see
        // the photo perfectly well.
        await _photos.markSyncFailed(
          recipeId: want.recipeId,
          error: 'That photo is no longer in storage.',
          path: want.path,
        );
        failed++;
        continue;
      } on Object catch (error) {
        await _photos.markSyncFailed(
          recipeId: want.recipeId,
          error: '$error',
          path: want.path,
        );
        failed++;
        continue;
      }

      await _photos.saveDownloaded(
        recipeId: want.recipeId,
        path: want.path,
        bytes: bytes,
        now: _now(),
      );
      downloaded++;
    }

    return PhotoSyncResult(downloaded: downloaded, failed: failed);
  }
}
