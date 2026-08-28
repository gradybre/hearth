import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_photo_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/fixtures.dart';

void main() {
  late HearthDatabase db;
  late RecipePhotoStore store;
  late Directory root;

  final DateTime t0 = DateTime.utc(2026, 8, 28, 18);
  Uint8List bytes(int length) =>
      Uint8List.fromList(List<int>.filled(length, 7));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hearth_photos');
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = RecipePhotoStore(db, directory: () async => root);

    // Photos hang off recipes, so the recipes have to exist first.
    for (final String id in <String>['ribs', 'curry']) {
      await RecipeStore(db).upsert(
        aRecipe(
          id: id,
          title: id,
          sections: <RecipeSection>[aSection(id: 'section-$id')],
        ),
        updatedAt: t0,
      );
    }
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('keeping a photo', () {
    test('the bytes land on disk and the recipe points at them', () async {
      await store.save(
        recipeId: 'ribs',
        bytes: bytes(64),
        extension: 'jpg',
        now: t0,
      );

      final File? file = await store.fileFor('ribs');
      expect(file, isNotNull);
      expect(await file!.length(), 64);
    });

    test('only the file name is stored, never an absolute path', () async {
      // An absolute path is a promise the device stops keeping: iOS moves an
      // app's container between installs.
      await store.save(
        recipeId: 'ribs',
        bytes: bytes(8),
        extension: 'jpg',
        now: t0,
      );

      final String name = (await store.fileNameFor('ribs'))!;
      expect(name, isNot(contains('/')));
      expect(name, endsWith('.jpg'));
    });

    test('replacing writes a new file and removes the old one', () async {
      // A new name on replace, because overwriting in place leaves Flutter's
      // image cache showing the photo that was there before.
      await store.save(
        recipeId: 'ribs',
        bytes: bytes(8),
        extension: 'jpg',
        now: t0,
      );
      final String first = (await store.fileNameFor('ribs'))!;

      await store.save(
        recipeId: 'ribs',
        bytes: bytes(16),
        extension: 'jpg',
        now: t0.add(const Duration(seconds: 1)),
      );
      final String second = (await store.fileNameFor('ribs'))!;

      expect(second, isNot(first));
      expect(File('${root.path}/recipe_photos/$first').existsSync(), isFalse);
      expect(await (await store.fileFor('ribs'))!.length(), 16);
    });

    test('photos do not bleed between recipes', () async {
      await store.save(
        recipeId: 'ribs',
        bytes: bytes(8),
        extension: 'jpg',
        now: t0,
      );

      expect(await store.fileFor('curry'), isNull);
    });

    test('every photo is listed for the library at once', () async {
      await store.save(
        recipeId: 'ribs',
        bytes: bytes(8),
        extension: 'jpg',
        now: t0,
      );
      await store.save(
        recipeId: 'curry',
        bytes: bytes(8),
        extension: 'png',
        now: t0,
      );

      expect(await store.watchAll().first, hasLength(2));
    });
  });

  group('removing a photo', () {
    test('takes the file with it, not just the row', () async {
      await store.save(
        recipeId: 'ribs',
        bytes: bytes(8),
        extension: 'jpg',
        now: t0,
      );
      final String name = (await store.fileNameFor('ribs'))!;

      await store.remove('ribs');

      expect(await store.fileNameFor('ribs'), isNull);
      expect(
        File('${root.path}/recipe_photos/$name').existsSync(),
        isFalse,
        reason: 'an orphaned file would sit on disk forever',
      );
    });

    test('removing one a recipe never had is not an error', () async {
      await store.remove('curry');
      expect(await store.fileFor('curry'), isNull);
    });
  });

  group('when the row outlives the file', () {
    test('reading reports no photo rather than a broken one', () async {
      // A reinstall brings the database back before the images.
      await store.save(
        recipeId: 'ribs',
        bytes: bytes(8),
        extension: 'jpg',
        now: t0,
      );
      await File(
        '${root.path}/recipe_photos/${await store.fileNameFor('ribs')}',
      ).delete();

      expect(await store.fileFor('ribs'), isNull);
    });
  });

  group('size', () {
    test('an oversized photo is refused, not quietly stored', () async {
      // The desktop picker cannot downscale, so a full-resolution import is
      // what this catches. Better a clear no than a library growing by 40 MB
      // a recipe.
      expect(
        () => store.save(
          recipeId: 'ribs',
          bytes: bytes(RecipePhotoStore.maxBytes + 1),
          extension: 'jpg',
          now: t0,
        ),
        throwsA(isA<PhotoTooLarge>()),
      );
    });

    test('and nothing is left behind when it is refused', () async {
      await expectLater(
        () => store.save(
          recipeId: 'ribs',
          bytes: bytes(RecipePhotoStore.maxBytes + 1),
          extension: 'jpg',
          now: t0,
        ),
        throwsA(isA<PhotoTooLarge>()),
      );
      expect(await store.fileNameFor('ribs'), isNull);
    });
  });
}
