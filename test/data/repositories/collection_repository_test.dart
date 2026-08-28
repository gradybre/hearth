import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/collection_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/repositories/collection_repository.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/fixtures.dart';

void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late RecipeStore recipes;
  late CollectionRepository repository;
  DateTime clock = DateTime.utc(2026, 8, 27, 18, 30);
  int nextId = 0;

  setUp(() async {
    clock = DateTime.utc(2026, 8, 27, 18, 30);
    nextId = 0;
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    recipes = RecipeStore(db);
    repository = CollectionRepository(
      database: db,
      store: CollectionStore(db),
      queue: queue,
      householdId: 'household-1',
      userId: 'user-1',
      clock: () => clock,
      idFactory: () => 'id-${nextId++}',
    );

    // Favourites and memberships carry foreign keys onto recipes, so the
    // recipes have to exist first.
    for (final String id in <String>['recipe-1', 'recipe-2']) {
      await recipes.upsert(
        aRecipe(
          id: id,
          title: id,
          // A distinct section id per recipe: the default fixture section is
          // shared, and section ids are unique in the table.
          sections: <RecipeSection>[aSection(id: 'section-$id')],
        ),
        updatedAt: clock,
      );
    }
  });

  tearDown(() => db.close());

  group('favourites', () {
    test('toggling on then off leaves nothing behind', () async {
      expect(await repository.toggleFavorite('recipe-1'), isTrue);
      expect(await repository.favoriteIds(), <String>{'recipe-1'});

      expect(await repository.toggleFavorite('recipe-1'), isFalse);
      expect(await repository.favoriteIds(), isEmpty);
    });

    test('favouriting twice does not create two rows', () async {
      await repository.toggleFavorite('recipe-1');
      await repository.toggleFavorite('recipe-1');
      await repository.toggleFavorite('recipe-1');
      expect(await repository.favoriteIds(), <String>{'recipe-1'});
    });

    test(
      'a favourite is queued for sync as the user, not the household',
      () async {
        await repository.toggleFavorite('recipe-1');
        final List<PendingWrite> pending = await queue.pending();
        final PendingWrite write = pending.single;

        expect(write.entityTable, CollectionRepository.favoritesTable);
        expect(write.operation, WriteOperation.upsert);
        expect(write.payload['user_id'], 'user-1');
        expect(write.payload['recipe_id'], 'recipe-1');
        expect(
          write.payload.containsKey('household_id'),
          isFalse,
          reason: 'favouriting is personal — §8.2 scopes it to the user',
        );
      },
    );

    test('un-favouriting queues a delete, not an upsert', () async {
      await repository.toggleFavorite('recipe-1');
      await repository.toggleFavorite('recipe-1');
      final List<PendingWrite> pending = await queue.pending();
      expect(pending.last.operation, WriteOperation.delete);
    });

    test('another user\'s favourites are not mine', () async {
      final CollectionRepository partner = CollectionRepository(
        database: db,
        store: CollectionStore(db),
        queue: queue,
        householdId: 'household-1',
        userId: 'user-2',
        clock: () => clock,
      );

      await partner.toggleFavorite('recipe-1');

      expect(await partner.favoriteIds(), <String>{'recipe-1'});
      expect(
        await repository.favoriteIds(),
        isEmpty,
        reason: 'hearts are private even inside a shared household',
      );
    });
  });

  group('collections', () {
    test('a created collection starts empty and is readable back', () async {
      final String id = await repository.createCollection('  Weeknight  ');
      final List<CollectionSummary> all = await repository.collections();

      expect(all.single.id, id);
      expect(all.single.name, 'Weeknight', reason: 'the name is trimmed');
      expect(all.single.size, 0);
    });

    test('a recipe can live in two cookbooks at once', () async {
      final String weeknight = await repository.createCollection('Weeknight');
      final String favourites = await repository.createCollection('Paella');

      await repository.toggleMembership(
        collectionId: weeknight,
        recipeId: 'recipe-1',
      );
      await repository.toggleMembership(
        collectionId: favourites,
        recipeId: 'recipe-1',
      );

      expect(await repository.collectionsOf('recipe-1'), <String>{
        weeknight,
        favourites,
      });
    });

    test('removing a recipe from a cookbook leaves the recipe alone', () async {
      final String id = await repository.createCollection('Weeknight');
      await repository.toggleMembership(collectionId: id, recipeId: 'recipe-1');
      await repository.toggleMembership(collectionId: id, recipeId: 'recipe-1');

      expect(await repository.collectionsOf('recipe-1'), isEmpty);
      expect(await recipes.byId('recipe-1'), isNotNull);
    });

    test('deleting a cookbook keeps every recipe that was in it', () async {
      // A collection holds no history, so it is a real delete — but it must
      // not take the library with it.
      final String id = await repository.createCollection('Weeknight');
      await repository.toggleMembership(collectionId: id, recipeId: 'recipe-1');

      await repository.deleteCollection(id);

      expect(await repository.collections(), isEmpty);
      expect(await repository.collectionsOf('recipe-1'), isEmpty);

      final Recipe? survivor = await recipes.byId('recipe-1');
      expect(survivor, isNotNull);
      expect(survivor!.isDeleted, isFalse);
    });

    test('renaming keeps the id, so memberships survive', () async {
      final String id = await repository.createCollection('Weeknite');
      await repository.toggleMembership(collectionId: id, recipeId: 'recipe-1');

      await repository.renameCollection(id, 'Weeknight');

      final List<CollectionSummary> all = await repository.collections();
      expect(all.single.name, 'Weeknight');
      expect(all.single.recipeIds, <String>{'recipe-1'});
    });

    test('the membership map covers the whole library in one read', () async {
      final String id = await repository.createCollection('Weeknight');
      await repository.toggleMembership(collectionId: id, recipeId: 'recipe-2');

      expect(await CollectionStore(db).membership(), <String, Set<String>>{
        'recipe-2': <String>{id},
      });
    });

    test('collections are queued for sync against the household', () async {
      final String id = await repository.createCollection('Weeknight');
      final List<PendingWrite> pending = await queue.pending();
      final PendingWrite write = pending.single;

      expect(write.entityTable, CollectionRepository.collectionsTable);
      expect(write.entityId, id);
      expect(write.payload['household_id'], 'household-1');
    });
  });
}
