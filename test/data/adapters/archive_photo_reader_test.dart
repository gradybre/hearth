import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/archive_photo_reader.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/adapters/food_data_archive.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_photo_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/remote/photo_storage.dart';
import 'package:hearth/data/remote/remote_gateway.dart';

import '../../support/fixtures.dart';

final DateTime _at = DateTime.utc(2026, 10, 1, 12);

void main() {
  late HearthDatabase db;
  late Directory directory;
  late RecipeStore recipes;
  late RecipePhotoStore photos;
  late _Storage storage;
  late StoredArchivePhotoReader reader;

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('archive-photo-test-');
    recipes = RecipeStore(db);
    photos = RecipePhotoStore(db, directory: () async => directory);
    storage = _Storage();
    reader = StoredArchivePhotoReader(
      database: db,
      photos: photos,
      storage: storage,
    );
    await recipes.upsert(
      aRecipe(id: 'recipe-1', householdId: 'home'),
      updatedAt: _at,
    );
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<ExportPhotoReference> capture() async => (await DataExport(
    database: db,
    recipes: recipes,
    foods: FoodStore(db),
    clock: () => _at,
  ).prepare(householdId: 'home', userId: 'me')).photoReferences.single;

  Future<void> remote(String path) =>
      (db.update(db.recipes)
            ..where(($RecipesTable r) => r.id.equals('recipe-1')))
          .write(RecipesCompanion(photoUrl: Value<String?>(path)));

  test('pending local photo is captured and read without a download', () async {
    await photos.save(
      recipeId: 'recipe-1',
      bytes: Uint8List.fromList(<int>[1, 2]),
      extension: 'png',
      now: _at,
    );
    final ExportPhotoReference captured = await capture();
    final ArchivePhotoRead result = await reader.read(captured);
    expect(result.bytes, <int>[1, 2]);
    expect(result.extension, 'png');
    expect(storage.paths, isEmpty);
  });

  test('replacing a captured local photo never substitutes the replacement or older remote', () async {
    await remote('recipe-1/old.jpg');
    await photos.save(
      recipeId: 'recipe-1',
      bytes: Uint8List.fromList(<int>[1]),
      extension: 'png',
      now: _at,
    );
    final ExportPhotoReference captured = await capture();
    await photos.save(
      recipeId: 'recipe-1',
      bytes: Uint8List.fromList(<int>[2]),
      extension: 'png',
      now: _at.add(const Duration(seconds: 1)),
    );
    final ArchivePhotoRead result = await reader.read(captured);
    expect(result.bytes, isNull);
    expect(result.reason, contains('no longer available'));
    expect(storage.paths, isEmpty);
  });

  test(
    'a matching cache is used, while a stale cache downloads captured identity',
    () async {
      await remote('recipe-1/old.jpg');
      await photos.saveDownloaded(
        recipeId: 'recipe-1',
        path: 'recipe-1/old.jpg',
        bytes: Uint8List.fromList(<int>[3]),
        now: _at,
      );
      expect((await reader.read(await capture())).bytes, <int>[3]);
      expect(storage.paths, isEmpty);
      await remote('recipe-1/new.jpg');
      final ExportPhotoReference captured = await capture();
      await remote('recipe-1/even-newer.jpg');
      final ArchivePhotoRead result = await reader.read(captured);
      expect(result.bytes, <int>[7, 8]);
      expect(storage.paths, <String>['recipe-1/new.jpg']);
    },
  );

  for (final Object error in <Object>[
    const PhotoObjectMissing('recipe-1/object.jpg'),
    const RemoteUnavailable('offline'),
  ]) {
    test(
      '${error.runtimeType} produces an omission with no raw error details',
      () async {
        await remote('recipe-1/object.jpg');
        storage.downloadAction = (_) async => throw error;
        final ArchivePhotoRead result = await reader.read(await capture());
        expect(result.bytes, isNull);
        expect(result.reason, isNotEmpty);
        expect(result.reason, isNot(contains('recipe-1/object.jpg')));
      },
    );
  }

  for (final String path in <String>[
    'other-recipe/object.jpg',
    'https://example.com/photo.jpg',
    '../object.jpg',
    'recipe-1/../object.jpg',
    'recipe-1/%2e%2e.jpg',
    r'recipe-1\object.jpg',
    'recipe-1/object.svg',
    'recipe-1/.jpg',
  ]) {
    test('untrusted photo path is never fetched: $path', () async {
      await remote(path);
      final ArchivePhotoRead result = await reader.read(await capture());
      expect(result.bytes, isNull);
      expect(storage.paths, isEmpty);
    });
  }

  test('a recipe outside the captured household cannot expose local or remote bytes', () async {
    await remote('recipe-1/object.jpg');
    final ExportPhotoReference captured = await capture();
    await (db.update(db.recipes)
          ..where(($RecipesTable r) => r.id.equals('recipe-1')))
        .write(const RecipesCompanion(householdId: Value<String>('other')));
    expect((await reader.read(captured)).bytes, isNull);
    expect(storage.paths, isEmpty);
  });

  test(
    'local path traversal and symlinks cannot read outside the photo directory',
    () async {
      final File privateFile = await File('${directory.path}/private.txt')
          .writeAsString('private fixture');
      for (final String name in <String>[
        '../private.txt',
        'recipe-1-link.jpg',
      ]) {
        if (name.endsWith('.jpg')) {
          await Link('${(await photos.photosDirectory()).path}/$name')
              .create(privateFile.path);
        }
        await db
            .into(db.recipePhotos)
            .insertOnConflictUpdate(
              RecipePhotoRow(
                recipeId: 'recipe-1',
                fileName: name,
                syncAttempts: 0,
                updatedAt: _at,
              ),
            );
        final ArchivePhotoRead result = await reader.read(await capture());
        expect(result.bytes, isNull);
        expect(storage.paths, isEmpty);
      }
      expect(await privateFile.readAsString(), 'private fixture');
    },
  );

  test(
    'oversized download is an omission, not an archive-sized allocation',
    () async {
      await remote('recipe-1/object.jpg');
      storage.downloadAction = (_) async =>
          Uint8List(RecipePhotoStore.maxBytes + 1);
      final ArchivePhotoRead result = await reader.read(await capture());
      expect(result.bytes, isNull);
      expect(result.reason, contains('size'));
    },
  );

  test(
    'account cancellation after authenticated download refuses the bytes',
    () async {
      await remote('recipe-1/object.jpg');
      final ExportPhotoReference captured = await capture();
      bool current = true;
      final Completer<Uint8List> pending = Completer<Uint8List>();
      final Completer<void> started = Completer<void>();
      storage.downloadAction = (_) {
        started.complete();
        return pending.future;
      };
      final Future<ArchivePhotoRead> work = reader.read(
        captured,
        isCurrent: () => current,
      );
      final Future<void> expectation = expectLater(
        work,
        throwsA(isA<ArchivePreparationCancelled>()),
      );
      await started.future;
      current = false;
      pending.complete(Uint8List.fromList(<int>[1]));
      await expectation;
    },
  );
}

class _Storage extends Fake implements PhotoStorage {
  final List<String> paths = <String>[];
  Future<Uint8List> Function(String)? downloadAction;
  @override
  Future<Uint8List> download(String path) {
    paths.add(path);
    return downloadAction?.call(path) ??
        Future<Uint8List>.value(Uint8List.fromList(<int>[7, 8]));
  }
}
