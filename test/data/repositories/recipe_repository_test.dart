import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/repositories/recipe_repository.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

void main() {
  late HearthDatabase db;
  late PendingWriteStore queue;
  late RecipeRepository repository;
  DateTime clock = DateTime.utc(2026, 8, 27, 12);

  setUp(() {
    clock = DateTime.utc(2026, 8, 27, 12);
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    repository = RecipeRepository(
      database: db,
      store: RecipeStore(db),
      queue: queue,
      householdId: 'household-1',
      clock: () => clock,
    );
  });

  tearDown(() => db.close());

  Recipe simple({String id = 'recipe-1'}) => aRecipe(
    id: id,
    sections: <RecipeSection>[
      aSection(
        id: '$id-sec',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'olive oil',
            id: '$id-ing',
            amount: 2,
            unit: Units.tbsp,
            sectionId: '$id-sec',
          ),
        ],
      ),
    ],
  );

  group('saving', () {
    test('a saved recipe is readable immediately, with no network', () async {
      await repository.save(simple());
      final List<Recipe> all = await repository.all();
      expect(all.single.id, 'recipe-1');
    });

    test('every save is queued for sync', () async {
      // The invariant that matters: a recipe can never be visible on the
      // device without also being scheduled to reach the server (spec §7.1).
      await repository.save(simple());

      final List<PendingWrite> pending = await queue.pending();
      expect(pending, hasLength(1));
      expect(pending.single.entityTable, 'recipes');
      expect(pending.single.entityId, 'recipe-1');
      expect(pending.single.operation, WriteOperation.upsert);
    });

    test('the queued payload carries the whole aggregate', () async {
      await repository.save(simple());
      final Map<String, Object?> payload =
          (await queue.pending()).single.payload;

      expect(payload['id'], 'recipe-1');
      expect(payload['household_id'], 'household-1');
      expect((payload['sections']! as List<Object?>), hasLength(1));
      expect((payload['ingredients']! as List<Object?>), hasLength(1));

      final Map<String, Object?> ingredient =
          (payload['ingredients']! as List<Object?>).single
              as Map<String, Object?>;
      expect(ingredient['name'], 'olive oil');
      expect(ingredient['quantity_kind'], 'volume');
      expect(ingredient['quantity_unit'], 'tbsp');
    });

    test('the household is stamped, not taken from the caller', () async {
      // Trusting an incoming household would let a bug write a row this user
      // could not read back through RLS.
      await repository.save(
        aRecipe(
          id: 'recipe-2',
          householdId: 'someone-elses-household',
          sections: <RecipeSection>[],
        ),
      );

      final Map<String, Object?> payload =
          (await queue.pending()).single.payload;
      expect(payload['household_id'], 'household-1');
      expect(await repository.byId('recipe-2'), isNotNull);
    });

    test('re-saving supersedes the earlier queued write', () async {
      await repository.save(simple());
      clock = clock.add(const Duration(minutes: 5));
      await repository.save(simple());

      expect(await queue.count(), 1);
    });
  });

  group('deleting', () {
    test('is soft, and the recipe stays resolvable by id', () async {
      await repository.save(simple());
      await repository.delete('recipe-1');

      expect(await repository.all(), isEmpty);
      // A past log referencing this recipe must still resolve (spec §4).
      final Recipe? deleted = await repository.byId('recipe-1');
      expect(deleted, isNotNull);
      expect(deleted!.isDeleted, isTrue);
    });

    test('is queued as an update, never a row removal', () async {
      await repository.save(simple());
      await repository.delete('recipe-1');

      final PendingWrite write = (await queue.pending()).single;
      expect(write.operation, WriteOperation.upsert);
      expect(write.payload['is_deleted'], isTrue);
    });

    test('deleting an unknown recipe queues nothing', () async {
      await repository.delete('never-existed');
      expect(await queue.count(), 0);
    });
  });

  test('watchAll emits the recipe once it is saved', () async {
    // emitsThrough rather than skip(1): whether the initial empty emission
    // lands before or after the save is a race, and either order is fine.
    final Future<void> sawIt = expectLater(
      repository.watchAll(),
      emitsThrough(
        predicate<List<Recipe>>(
          (List<Recipe> recipes) =>
              recipes.length == 1 && recipes.single.id == 'recipe-1',
          'a list containing recipe-1',
        ),
      ),
    );

    await repository.save(simple());
    await sawIt;
  });
}
