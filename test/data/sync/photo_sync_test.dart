import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/recipe_photo_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/repositories/recipe_repository.dart';
import 'package:hearth/data/sync/photo_sync.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/fake_photo_storage.dart';
import '../../support/fixtures.dart';

/// Carrying a photo to the other phone (spec §5.2, §7.2).
void main() {
  late HearthDatabase db;
  late Directory dir;
  late RecipePhotoStore photos;
  late RecipeStore recipeStore;
  late RecipeRepository recipes;
  late FakePhotoStorage storage;
  late PhotoSync sync;
  DateTime clock = DateTime.utc(2026, 9, 3, 10);
  int nextObject = 0;

  setUp(() async {
    clock = DateTime.utc(2026, 9, 3, 10);
    nextObject = 0;
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('hearth-photo-sync');
    photos = RecipePhotoStore(db, directory: () async => dir);
    recipeStore = RecipeStore(db);
    recipes = RecipeRepository(
      database: db,
      store: recipeStore,
      queue: PendingWriteStore(db),
      householdId: 'household-1',
      clock: () => clock,
    );
    storage = FakePhotoStorage();
    sync = PhotoSync(
      database: db,
      photos: photos,
      recipes: recipes,
      storage: storage,
      clock: () => clock,
      objectIdFactory: () => 'object-${nextObject++}',
    );

    await recipeStore.upsert(
      aRecipe(id: 'recipe-1', title: 'Chilli'),
      updatedAt: clock,
    );
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Uint8List bytes([int fill = 1]) => Uint8List.fromList(<int>[fill, 2, 3, 4]);

  Future<void> takePhoto({String recipeId = 'recipe-1'}) => photos.save(
    recipeId: recipeId,
    bytes: bytes(),
    extension: 'jpg',
    now: clock,
  );

  Future<RecipePhotoRow?> row([String id = 'recipe-1']) => (db.select(
    db.recipePhotos,
  )..where(($RecipePhotosTable p) => p.recipeId.equals(id))).getSingleOrNull();

  Future<String?> photoUrl([String id = 'recipe-1']) async =>
      (await recipeStore.byId(id))?.photoUrl;

  group('sending a photo up', () {
    test('uploads it and points the recipe at it', () async {
      await takePhoto();

      final PhotoSyncResult result = await sync.push();

      expect(result.uploaded, 1);
      expect(storage.uploaded.single, 'recipe-1/object-0.jpg');
      expect(await photoUrl(), 'recipe-1/object-0.jpg');
      expect((await row())!.remotePath, 'recipe-1/object-0.jpg');
    });

    test('the local mark and the shared field land together', () async {
      // Split apart, a replaced photo briefly reads as stale — remotePath new,
      // photoUrl still old — and the pull would fetch the previous image back
      // over the one just taken.
      await takePhoto();
      await sync.push();

      expect((await row())!.remotePath, await photoUrl());
    });

    test('a photo already up is not sent again', () async {
      await takePhoto();
      await sync.push();
      await sync.push();

      expect(storage.uploaded, hasLength(1));
    });

    test('offline leaves it exactly as it was', () async {
      // Not a failed attempt: five supermarket trips must not exhaust a photo
      // that was never broken.
      await takePhoto();
      storage.offline = true;

      final PhotoSyncResult result = await sync.push();

      expect(result.stoppedBecauseOffline, isTrue);
      expect((await row())!.syncAttempts, 0);
      expect((await row())!.remotePath, isNull);
      expect(await photoUrl(), isNull);
    });

    test('a refusal is counted and eventually given up on', () async {
      await takePhoto();

      for (int i = 0; i < RecipePhotoStore.maxAttempts + 2; i++) {
        storage.failWith = StateError('nope');
        await sync.push();
      }

      // This is the property that terminates the retry loop: writing the
      // attempt count wakes the sync listener, which retries. It stops only
      // because the candidate query filters on being under the limit.
      expect((await row())!.syncAttempts, RecipePhotoStore.maxAttempts);
      expect(await photos.pendingUploads(), isEmpty);
    });

    test(
      'a photo saved under the old larger ceiling is refused once',
      () async {
        // The bucket would reject it five times over; say so instead.
        await photos.save(
          recipeId: 'recipe-1',
          bytes: bytes(),
          extension: 'jpg',
          now: clock,
        );
        final File file = (await photos.fileFor('recipe-1'))!;
        await file.writeAsBytes(
          Uint8List(RecipePhotoStore.maxBytes + 1),
          flush: true,
        );

        await sync.push();

        expect(storage.uploaded, isEmpty);
        expect((await row())!.syncError, contains('too large'));
      },
    );

    test('a row whose file is gone is not retried for ever', () async {
      // A reinstall can leave the row behind. Nothing to send.
      await takePhoto();
      await (await photos.fileFor('recipe-1'))!.delete();

      await sync.push();

      expect(storage.uploaded, isEmpty);
      expect((await row())!.syncAttempts, 1);
    });

    test('every photo taken before sync existed is picked up', () async {
      // The backfill, which needs no code of its own: a row from before the
      // migration has a null remotePath, which is exactly the predicate.
      for (int i = 2; i <= 5; i++) {
        await recipeStore.upsert(
          aRecipe(
            id: 'recipe-$i',
            title: 'R$i',
            sections: <RecipeSection>[aSection(id: 'section-$i')],
          ),
          updatedAt: clock,
        );
        await takePhoto(recipeId: 'recipe-$i');
      }
      await takePhoto();

      // Budgeted, not all at once: a fifty-photo backfill must not be one
      // burst on the first launch after an update.
      await sync.push();
      expect(storage.uploaded, hasLength(PhotoSync.uploadBudget));

      // And the rest come along on the passes that follow, without anyone
      // asking for them.
      await sync.push();
      expect(storage.uploaded, hasLength(5));
      expect(await photos.pendingUploads(), isEmpty);
    });
  });

  group('bringing a photo down', () {
    Future<void> partnerPhoto({String path = 'recipe-1/remote.jpg'}) async {
      storage.objects[path] = bytes(9);
      await recipes.setPhotoUrl('recipe-1', path);
    }

    test('a recipe with a photo this device lacks fetches it', () async {
      await partnerPhoto();

      final PhotoSyncResult result = await sync.pull();

      expect(result.downloaded, 1);
      expect((await photos.fileFor('recipe-1'))!.existsSync(), isTrue);
      expect((await row())!.remotePath, 'recipe-1/remote.jpg');
    });

    test('and is not fetched twice', () async {
      await partnerPhoto();
      await sync.pull();
      await sync.pull();

      expect(storage.downloaded, hasLength(1));
    });

    test('a replaced photo is noticed and re-fetched', () async {
      // Staleness is a string compare, and it works only because every upload
      // writes a fresh object rather than overwriting one.
      await partnerPhoto();
      await sync.pull();

      await partnerPhoto(path: 'recipe-1/newer.jpg');
      await sync.pull();

      expect(storage.downloaded, <String>[
        'recipe-1/remote.jpg',
        'recipe-1/newer.jpg',
      ]);
    });

    test('a missing object does not clear the shared field', () async {
      // One device's failed GET is not evidence about a field both people
      // share: the object may be fine and the failure a proxy hiccup, and
      // clearing it would push a destructive write to a partner who can see
      // the photo perfectly well.
      await partnerPhoto();
      storage.missing.add('recipe-1/remote.jpg');

      await sync.pull();

      expect(await photoUrl(), 'recipe-1/remote.jpg');
      expect((await row())!.syncAttempts, 1);
    });

    test('and stops asking after a few goes', () async {
      await partnerPhoto();
      storage.missing.add('recipe-1/remote.jpg');

      for (int i = 0; i < RecipePhotoStore.maxAttempts + 2; i++) {
        await sync.pull();
      }

      expect((await row())!.syncAttempts, RecipePhotoStore.maxAttempts);
      expect(await photos.pendingDownloads(), isEmpty);
    });

    test('a partner replacing a broken photo unsticks it', () async {
      // Without this, a photo that once 404'd would need someone to clear
      // state by hand before it could ever arrive.
      await partnerPhoto();
      storage.missing.add('recipe-1/remote.jpg');
      for (int i = 0; i < RecipePhotoStore.maxAttempts; i++) {
        await sync.pull();
      }
      expect(await photos.pendingDownloads(), isEmpty);

      await partnerPhoto(path: 'recipe-1/fixed.jpg');

      expect(await photos.pendingDownloads(), hasLength(1));
      await sync.pull();
      expect(storage.downloaded, contains('recipe-1/fixed.jpg'));
    });

    test('offline burns no attempt', () async {
      await partnerPhoto();
      storage.offline = true;

      final PhotoSyncResult result = await sync.pull();

      expect(result.stoppedBecauseOffline, isTrue);
      expect((await row())?.syncAttempts ?? 0, 0);
    });

    test('a soft-deleted recipe is not fetched', () async {
      // It is hidden; fetching its picture is work for nothing.
      await partnerPhoto();
      await recipes.delete('recipe-1');

      await sync.pull();

      expect(storage.downloaded, isEmpty);
    });
  });

  group('a photo taken here but not yet uploaded', () {
    test('is never downloaded over', () async {
      // Review finding: a local-only row (file, no remotePath) read as
      // "stale", so when the partner's photo_url arrived before this
      // device's upload budget reached the recipe, the pull overwrote the
      // never-uploaded local file with the partner's. The local photo was
      // simply gone.
      await takePhoto();
      final File mine = (await photos.fileFor('recipe-1'))!;
      final List<int> myBytes = await mine.readAsBytes();

      storage.objects['recipe-1/theirs.jpg'] = bytes(7);
      await recipes.setPhotoUrl('recipe-1', 'recipe-1/theirs.jpg');

      await sync.pull();

      expect(storage.downloaded, isEmpty);
      expect(await (await photos.fileFor('recipe-1'))!.readAsBytes(), myBytes);
      expect((await row())!.remotePath, isNull);
    });

    test('and its own upload still wins the next push', () async {
      await takePhoto();
      storage.objects['recipe-1/theirs.jpg'] = bytes(7);
      await recipes.setPhotoUrl('recipe-1', 'recipe-1/theirs.jpg');

      await sync.push();

      expect(storage.uploaded, hasLength(1));
      expect(await photoUrl(), storage.uploaded.single);
    });
  });

  group('a replaced photo that keeps failing to download', () {
    test('stops being asked for after the cap', () async {
      // The other half of the same finding: a stale row's attempt count
      // could never become "exhausted" because remotePath != photoUrl kept
      // reading as "changed", so a 404 on the replacement retried on every
      // sync pass for ever.
      storage.objects['recipe-1/first.jpg'] = bytes(1);
      await recipes.setPhotoUrl('recipe-1', 'recipe-1/first.jpg');
      await sync.pull();
      expect(storage.downloaded, hasLength(1));

      await recipes.setPhotoUrl('recipe-1', 'recipe-1/second.jpg');
      storage.missing.add('recipe-1/second.jpg');
      for (int i = 0; i < RecipePhotoStore.maxAttempts + 2; i++) {
        await sync.pull();
      }

      expect((await row())!.syncAttempts, RecipePhotoStore.maxAttempts);
      expect(await photos.pendingDownloads(), isEmpty);
      // And the old photo is still there to show meanwhile.
      expect(await photos.fileFor('recipe-1'), isNotNull);
    });

    test('but a further replacement is tried again', () async {
      storage.objects['recipe-1/first.jpg'] = bytes(1);
      await recipes.setPhotoUrl('recipe-1', 'recipe-1/first.jpg');
      await sync.pull();
      await recipes.setPhotoUrl('recipe-1', 'recipe-1/second.jpg');
      storage.missing.add('recipe-1/second.jpg');
      for (int i = 0; i < RecipePhotoStore.maxAttempts; i++) {
        await sync.pull();
      }
      expect(await photos.pendingDownloads(), isEmpty);

      storage.objects['recipe-1/third.jpg'] = bytes(3);
      await recipes.setPhotoUrl('recipe-1', 'recipe-1/third.jpg');

      expect(await photos.pendingDownloads(), hasLength(1));
      await sync.pull();
      expect(storage.downloaded.last, 'recipe-1/third.jpg');
    });
  });

  group('two phones photographing the same recipe', () {
    test('the later one wins and the other converges on it', () async {
      // Both uploads succeed to distinct paths — a collision is not possible —
      // and last-write-wins on the recipe picks one. This device then sees its
      // own copy is stale and downloads the winner's.
      await takePhoto();
      await sync.push();
      final String mine = (await photoUrl())!;

      storage.objects['recipe-1/theirs.jpg'] = bytes(7);
      await recipes.setPhotoUrl('recipe-1', 'recipe-1/theirs.jpg');

      await sync.pull();

      expect(mine, isNot('recipe-1/theirs.jpg'));
      expect((await row())!.remotePath, 'recipe-1/theirs.jpg');
      expect(storage.downloaded, <String>['recipe-1/theirs.jpg']);
    });
  });
}
