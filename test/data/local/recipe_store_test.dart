import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

void main() {
  late HearthDatabase db;
  late RecipeStore store;
  final DateTime now = DateTime.utc(2026, 8, 27, 12);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = RecipeStore(db);
  });

  tearDown(() => db.close());

  /// Child ids are derived from the recipe id: section and ingredient ids are
  /// primary keys in their own right, so two recipes cannot share them.
  Recipe sauced({String id = 'recipe-1', double servings = 4}) => aRecipe(
    id: id,
    servings: servings,
    sections: <RecipeSection>[
      aSection(
        id: '$id-sec-main',
        name: 'Main',
        sortOrder: 0,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'chicken breast',
            id: '$id-ing-chicken',
            amount: 400,
            unit: Units.gram,
            sectionId: '$id-sec-main',
            sortOrder: 0,
          ),
          anIngredient(
            'salt',
            id: '$id-ing-salt',
            sectionId: '$id-sec-main',
            optional: true,
            sortOrder: 1,
          ),
        ],
        steps: <RecipeStep>[
          aStep(
            'Sear the chicken',
            sectionId: '$id-sec-main',
            timerSeconds: 300,
          ),
        ],
      ),
      aSection(
        id: '$id-sec-sauce',
        name: 'Sauce',
        sortOrder: 1,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'olive oil',
            id: '$id-ing-oil',
            amount: 2,
            unit: Units.tbsp,
            sectionId: '$id-sec-sauce',
            prepNote: 'divided',
            sortOrder: 0,
          ),
        ],
      ),
    ],
  );

  group('round trip', () {
    test('a recipe survives a save and reload intact', () async {
      await store.upsert(sauced(), updatedAt: now);
      final Recipe? loaded = await store.byId('recipe-1');

      expect(loaded, isNotNull);
      expect(loaded!.title, 'Test recipe');
      expect(loaded.servings, 4);
      expect(loaded.sections, hasLength(2));
      expect(loaded.orderedSections.map((RecipeSection s) => s.name), <String>[
        'Main',
        'Sauce',
      ]);
    });

    test(
      'a reloaded recipe carries the timestamp it was written with',
      () async {
        // What the library's recency sort actually reads. The column was
        // written on every save long before anything read it back.
        await store.upsert(sauced(), updatedAt: now);

        // An instant comparison: Drift returns local time, and DateTime's ==
        // also requires the UTC flag to match.
        expect(
          (await store.byId('recipe-1'))!.updatedAt!.isAtSameMomentAs(now),
          isTrue,
        );
      },
    );

    test(
      'quantities keep their exact canonical value and authored unit',
      () async {
        // The stored value must not drift through the database round trip, and
        // the authored unit is what makes a recipe read back as "2 tbsp".
        await store.upsert(sauced(), updatedAt: now);
        final Recipe loaded = (await store.byId('recipe-1'))!;
        final RecipeIngredient oil = loaded.allIngredients.firstWhere(
          (RecipeIngredient i) => i.name == 'olive oil',
        );

        expect(oil.quantity!.preferredUnit, Units.tbsp);
        expect(
          oil.quantity!.canonicalAmount,
          Quantity.of(2, Units.tbsp).canonicalAmount,
        );
        expect(oil.prepNote, 'divided');
      },
    );

    test('an unquantified optional ingredient stays unquantified', () async {
      await store.upsert(sauced(), updatedAt: now);
      final Recipe loaded = (await store.byId('recipe-1'))!;
      final RecipeIngredient salt = loaded.allIngredients.firstWhere(
        (RecipeIngredient i) => i.name == 'salt',
      );

      expect(salt.quantity, isNull);
      expect(salt.isOptional, isTrue);
    });

    test('steps keep their section, order, and timer', () async {
      await store.upsert(sauced(), updatedAt: now);
      final Recipe loaded = (await store.byId('recipe-1'))!;

      expect(loaded.allSteps, hasLength(1));
      expect(loaded.allSteps.single.text, 'Sear the chicken');
      expect(loaded.allSteps.single.timerSeconds, 300);
      expect(loaded.allSteps.single.sectionId, 'recipe-1-sec-main');
    });

    test('an unknown recipe reads back as null', () async {
      expect(await store.byId('nope'), isNull);
    });
  });

  group('replacing an existing recipe', () {
    test('removes children the edit dropped', () async {
      await store.upsert(sauced(), updatedAt: now);

      // Edit it down to a single section with one ingredient.
      final Recipe trimmed = aRecipe(
        id: 'recipe-1',
        servings: 2,
        sections: <RecipeSection>[
          aSection(
            id: 'recipe-1-sec-main',
            ingredients: <RecipeIngredient>[
              anIngredient(
                'chicken breast',
                id: 'recipe-1-ing-chicken',
                amount: 200,
                unit: Units.gram,
                sectionId: 'recipe-1-sec-main',
              ),
            ],
          ),
        ],
      );
      await store.upsert(trimmed, updatedAt: now.add(const Duration(hours: 1)));

      final Recipe loaded = (await store.byId('recipe-1'))!;
      expect(loaded.sections, hasLength(1));
      expect(loaded.allIngredients, hasLength(1));
      expect(loaded.allSteps, isEmpty);
      expect(loaded.servings, 2);
    });

    test('does not leave orphaned rows behind', () async {
      await store.upsert(sauced(), updatedAt: now);
      await store.upsert(
        aRecipe(
          id: 'recipe-1',
          sections: <RecipeSection>[aSection(id: 'recipe-1-sec-main')],
        ),
        updatedAt: now,
      );

      final int ingredients = await db
          .select(db.recipeIngredients)
          .get()
          .then((List<RecipeIngredientRow> r) => r.length);
      final int steps = await db
          .select(db.recipeSteps)
          .get()
          .then((List<RecipeStepRow> r) => r.length);

      expect(ingredients, 0);
      expect(steps, 0);
    });
  });

  group('listing', () {
    test('scopes to the household', () async {
      await store.upsert(sauced(), updatedAt: now);
      await db
          .into(db.recipes)
          .insert(
            RecipesCompanion.insert(
              id: 'other',
              householdId: 'someone-else',
              title: 'Not ours',
              servings: 2,
              updatedAt: now,
            ),
          );

      final List<Recipe> mine = await store.all(householdId: 'household-1');
      expect(mine.map((Recipe r) => r.id), <String>['recipe-1']);
    });

    test('hides soft-deleted recipes but keeps them retrievable', () async {
      await store.upsert(sauced(), updatedAt: now);
      await store.softDelete('recipe-1', updatedAt: now);

      expect(await store.all(householdId: 'household-1'), isEmpty);
      expect(
        (await store.all(
          householdId: 'household-1',
          includeDeleted: true,
        )).single.id,
        'recipe-1',
      );
      // Still resolvable by id, which is what a past log needs (spec §4).
      expect((await store.byId('recipe-1'))!.isDeleted, isTrue);
    });

    test('orders by most recently edited', () async {
      await store.upsert(sauced(), updatedAt: now);
      await store.upsert(
        sauced(id: 'recipe-2'),
        updatedAt: now.add(const Duration(minutes: 5)),
      );

      final List<Recipe> all = await store.all(householdId: 'household-1');
      expect(all.map((Recipe r) => r.id), <String>['recipe-2', 'recipe-1']);
    });
  });

  test('deleting a recipe cascades to its children', () async {
    await store.upsert(sauced(), updatedAt: now);
    await db.delete(db.recipes).go();

    expect(await db.select(db.recipeSections).get(), isEmpty);
    expect(await db.select(db.recipeIngredients).get(), isEmpty);
    expect(await db.select(db.recipeSteps).get(), isEmpty);
  });
}
