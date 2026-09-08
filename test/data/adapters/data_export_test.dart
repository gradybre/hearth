import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/week_template.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// Never being locked in (spec §7.4).
void main() {
  late HearthDatabase db;
  late DataExport export;
  late RecipeStore recipes;
  late FoodStore foods;
  late PlanRepository plans;
  final DateTime clock = DateTime.utc(2026, 9, 3, 12);

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    recipes = RecipeStore(db);
    foods = FoodStore(db);
    plans = PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: PendingWriteStore(db),
      userId: 'user-1',
      clock: () => clock,
    );
    export = DataExport(
      database: db,
      recipes: recipes,
      foods: foods,
      clock: () => clock,
    );

    await recipes.upsert(
      aRecipe(
        id: 'recipe-1',
        title: 'Chilli',
        ingredients: <RecipeIngredient>[anIngredient('ground beef', amount: 1)],
      ),
      updatedAt: clock,
    );
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>> run() =>
      export.asJson(householdId: 'household-1', userId: 'user-1');

  test('says what it is and when it was taken', () async {
    final Map<String, Object?> json = await run();

    expect(json['format'], 'hearth-export');
    expect(json['version'], DataExport.formatVersion);
    expect(json['exported_at'], '2026-09-03T12:00:00.000Z');
  });

  test('carries the recipe library whole', () async {
    final Map<String, Object?> json = await run();

    final List<Object?> out = json['recipes']! as List<Object?>;
    expect(out, hasLength(1));
    expect((out.single! as Map<String, Object?>)['title'], 'Chilli');
    // Its parts too, not just the header.
    expect((out.single! as Map<String, Object?>)['ingredients'], isNotEmpty);
  });

  test('and a recipe you binned, because you still wrote it', () async {
    // An export whose promise is "you are never locked in" should not quietly
    // drop the ones you deleted — every log pointing at one would otherwise
    // resolve to nothing.
    await recipes.softDelete('recipe-1', updatedAt: clock);

    final List<Object?> out = (await run())['recipes']! as List<Object?>;
    expect(out, hasLength(1));
    expect((out.single! as Map<String, Object?>)['is_deleted'], isTrue);
  });

  test('a logged meal keeps its frozen snapshot, verbatim', () async {
    // The §4 non-negotiable, and the sharpest form of it: log a meal, then
    // change the recipe underneath. An export that recalculated from the
    // recipe as it stands today would be a record of a past that never
    // happened.
    await plans.add(
      date: clock,
      slot: MealSlot.dinner,
      refType: PlanRefType.recipe,
      refId: 'recipe-1',
      servings: 2,
      loggedMacros: const Macros(kcal: 500, proteinG: 40, carbG: 30, fatG: 20),
      // This test is not about coverage; saying so beats letting the
      // repository infer a completeness nothing checked.
      loggedCoverage: const NutrientCoverage.notRecorded(),
    );

    await recipes.upsert(
      aRecipe(
        id: 'recipe-1',
        title: 'Chilli, now with double everything',
        ingredients: <RecipeIngredient>[
          anIngredient('ground beef', amount: 99),
        ],
      ),
      updatedAt: clock,
    );

    final List<Object?> entries =
        (await run())['meal_plan_entries']! as List<Object?>;
    final Map<String, Object?> entry = entries.single! as Map<String, Object?>;

    expect(entry['is_logged'], isTrue);
    final Map<String, Object?> snapshot =
        entry['macro_snapshot']! as Map<String, Object?>;
    // 500 a serving, two servings — what was actually eaten, and untouched by
    // the edit above.
    expect(snapshot['kcal'], 1000);
    // Real JSON, not a string holding JSON — the file is meant to be read.
    expect(entry['macro_snapshot'], isA<Map<String, Object?>>());
  });

  test('another person\'s plan is not in your export', () async {
    // Plans and logs are private per user (§5.1), household or not.
    final PlanRepository theirs = PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: PendingWriteStore(db),
      userId: 'user-2',
      clock: () => clock,
    );
    await theirs.add(
      date: clock,
      slot: MealSlot.lunch,
      refType: PlanRefType.recipe,
      refId: 'recipe-1',
      servings: 1,
    );

    final Map<String, Object?> json = await run();
    expect(json['meal_plan_days'], isEmpty);
    expect(json['meal_plan_entries'], isEmpty);
  });

  test('a food and its serving options come along', () async {
    await foods.upsert(
      Food(
        id: 'food-1',
        householdId: 'household-1',
        name: 'Ground beef',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[
          ServingOption(
            id: 'serving-1',
            label: '100 g',
            amount: Quantity.of(100, Units.gram),
            macros: const Macros(kcal: 250, proteinG: 26, carbG: 0, fatG: 15),
            isReference: true,
          ),
        ],
      ),
      updatedAt: clock,
    );

    final List<Object?> out = (await run())['foods']! as List<Object?>;
    expect(out, hasLength(1));
    expect((out.single! as Map<String, Object?>)['name'], 'Ground beef');
    expect(
      (out.single! as Map<String, Object?>)['serving_options'],
      isNotEmpty,
    );
  });

  test('the global catalogue is left out', () async {
    // Not yours, not your data, and it would dwarf everything that is.
    await foods.upsert(
      const Food(
        id: 'global-1',
        name: 'Generic apple',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[],
      ),
      updatedAt: clock,
    );

    final List<Object?> out = (await run())['foods']! as List<Object?>;
    expect(out, isEmpty);
  });

  test('it says plainly that photos are not in it', () async {
    expect(await run(), containsPair('note', contains('photos are not')));
  });

  test('the file is named for the day and is real JSON', () async {
    final ExportedFile file = await export.build(
      householdId: 'household-1',
      userId: 'user-1',
    );

    expect(file.name, 'hearth-2026-09-03.json');
    expect(jsonDecode(file.contents), isA<Map<String, Object?>>());
    // Indented, because a person may open it.
    expect(file.contents, contains('\n  "version"'));
    expect(file.bytes, greaterThan(0));
  });

  group('what the export claims about itself (spec §7.4, R12)', () {
    test('a food it points at comes with it, global or not', () async {
      // Referential closure, and the case that breaks it: a restaurant's
      // published food is *global* — world-readable, written server-side —
      // so it is not in the household's library and was left out. A log
      // entry pointing at one then resolved to nothing at all, and the file
      // said "everything else Hearth holds is here" over the top of it.
      await foods.upsert(
        const Food(
          id: 'chipotle-bowl',
          name: 'Burrito bowl',
          brand: 'Chipotle',
          source: FoodSource.restaurant,
          servingOptions: <ServingOption>[],
        ),
        updatedAt: clock,
      );
      await plans.add(
        date: clock,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'chipotle-bowl',
        servings: 1,
        loggedMacros: const Macros(
          kcal: 700,
          proteinG: 30,
          carbG: 80,
          fatG: 25,
        ),
        loggedCoverage: const NutrientCoverage.notRecorded(),
      );

      final List<Object?> out = (await run())['foods']! as List<Object?>;
      final Iterable<Map<String, Object?>> byId = out
          .cast<Map<String, Object?>>()
          .where((Map<String, Object?> f) => f['id'] == 'chipotle-bowl');

      expect(
        byId,
        hasLength(1),
        reason: 'a log pointing at a food nobody exported resolves to nothing',
      );
      expect(
        byId.single['is_global'],
        isTrue,
        reason: 'marked as somebody else\'s definition, not the household\'s',
      );
    });

    test('and one a recipe is matched to, the same way', () async {
      await foods.upsert(
        const Food(
          id: 'global-beef',
          name: 'Ground beef',
          source: FoodSource.manual,
          servingOptions: <ServingOption>[],
        ),
        updatedAt: clock,
      );
      await recipes.upsert(
        aRecipe(
          id: 'recipe-1',
          title: 'Chilli',
          ingredients: <RecipeIngredient>[
            anIngredient('ground beef', amount: 1, foodId: 'global-beef'),
          ],
        ),
        updatedAt: clock,
      );

      final List<Object?> out = (await run())['foods']! as List<Object?>;
      expect(
        out.cast<Map<String, Object?>>().map(
          (Map<String, Object?> f) => f['id'],
        ),
        contains('global-beef'),
      );
    });

    test('but the rest of the catalogue stays where it is', () async {
      // Closure, not a copy of the world. A global food nothing points at is
      // not the household's data and would dwarf what is.
      await foods.upsert(
        const Food(
          id: 'unreferenced',
          name: 'Generic apple',
          source: FoodSource.manual,
          servingOptions: <ServingOption>[],
        ),
        updatedAt: clock,
      );

      final List<Object?> out = (await run())['foods']! as List<Object?>;
      expect(out, isEmpty);
    });

    test('all seven targets, not the four that fit on a ring', () async {
      // Fibre, sodium and cholesterol were lifted out of the deferred list
      // deliberately (§5.6). An export that drops them loses a decision
      // somebody made, silently.
      await db
          .into(db.macroTargets)
          .insert(
            MacroTargetsCompanion.insert(
              id: 'targets-1',
              userId: 'user-1',
              weekStartDate: DateTime.utc(2026, 8, 31),
              kcal: 2400,
              proteinG: 180,
              carbG: 240,
              fatG: 80,
              fiberG: const Value<double?>(30),
              sodiumMg: const Value<double?>(2300),
              cholesterolMg: const Value<double?>(300),
              updatedAt: clock,
            ),
          );

      final Map<String, Object?> targets =
          ((await run())['macro_targets']! as List<Object?>).single!
              as Map<String, Object?>;

      expect(targets['fiber_g'], 30);
      expect(targets['sodium_mg'], 2300);
      expect(targets['cholesterol_mg'], 300);
    });

    test('a saved week is in it', () async {
      // Templates are somebody's work — a week they built and kept. They were
      // not exported at all.
      await db
          .into(db.planTemplates)
          .insert(
            PlanTemplatesCompanion.insert(
              id: 'template-1',
              userId: 'user-1',
              name: 'Usual week',
              // A real entry, encoded the way the app encodes one. A shape
              // invented here would be dropped by the domain's own reader,
              // and the reference check below would then pass on nothing.
              entries: Value<String>(
                WeekTemplate(
                  id: 'template-1',
                  name: 'Usual week',
                  entries: const <TemplateEntry>[
                    TemplateEntry(
                      weekday: 3,
                      slot: MealSlot.dinner,
                      refType: PlanRefType.recipe,
                      refId: 'recipe-1',
                      servings: 2,
                    ),
                  ],
                  updatedAt: clock,
                ).encodeEntries(),
              ),
              updatedAt: clock,
            ),
          );

      final List<Object?> saved =
          (await run())['plan_templates']! as List<Object?>;
      final Map<String, Object?> template =
          saved.single! as Map<String, Object?>;

      expect(template['name'], 'Usual week');
      expect(
        template['entries'],
        isA<List<Object?>>(),
        reason: 'real JSON, not a string holding JSON — the file is read',
      );
      // And what it points at counts as a reference — so the check below has
      // something to be right about.
      final Map<String, Object?> manifest =
          (await run())['manifest']! as Map<String, Object?>;
      expect(manifest['missing_references'], isEmpty);
    });

    test('a saved week naming a recipe that is gone says so', () async {
      await db
          .into(db.planTemplates)
          .insert(
            PlanTemplatesCompanion.insert(
              id: 'template-3',
              userId: 'user-1',
              name: 'Old week',
              entries: Value<String>(
                WeekTemplate(
                  id: 'template-3',
                  name: 'Old week',
                  entries: const <TemplateEntry>[
                    TemplateEntry(
                      weekday: 1,
                      slot: MealSlot.lunch,
                      refType: PlanRefType.recipe,
                      refId: 'long-gone',
                      servings: 1,
                    ),
                  ],
                  updatedAt: clock,
                ).encodeEntries(),
              ),
              updatedAt: clock,
            ),
          );

      final Map<String, Object?> manifest =
          (await run())['manifest']! as Map<String, Object?>;
      expect(
        (manifest['missing_references']! as List<Object?>).join(' '),
        contains('long-gone'),
      );
    });

    test('and not somebody else\'s saved week', () async {
      await db
          .into(db.planTemplates)
          .insert(
            PlanTemplatesCompanion.insert(
              id: 'template-2',
              userId: 'user-2',
              name: 'Their week',
              updatedAt: clock,
            ),
          );

      expect((await run())['plan_templates'], isEmpty);
    });

    test('the manifest counts what is in the file', () async {
      final Map<String, Object?> json = await run();
      final Map<String, Object?> manifest =
          json['manifest']! as Map<String, Object?>;
      final Map<String, Object?> counts =
          manifest['counts']! as Map<String, Object?>;

      expect(counts['recipes'], 1);
      expect(
        counts.keys,
        containsAll(<String>['foods', 'meal_plan_entries', 'plan_templates']),
        reason: 'a section with no count is a section nobody can check',
      );
    });

    test('and names what it left out rather than implying nothing', () async {
      final Map<String, Object?> manifest =
          (await run())['manifest']! as Map<String, Object?>;

      expect(
        (manifest['excluded']! as List<Object?>).join(' '),
        contains('photo'),
      );
      expect(
        manifest['complete'],
        isNotNull,
        reason: 'whether this is all of it is a fact, not an implication',
      );
    });

    test('an unsent change makes the file say it may be behind', () async {
      // "Everything Hearth holds" is a claim about the server as well as this
      // phone, and a queue with something in it is proof it is not true yet.
      await PendingWriteStore(db).enqueue(
        entityTable: 'recipes',
        entityId: 'recipe-1',
        operation: WriteOperation.upsert,
        payload: const <String, Object?>{'id': 'recipe-1'},
        queuedAt: clock,
      );

      final Map<String, Object?> manifest =
          (await run())['manifest']! as Map<String, Object?>;

      expect(manifest['complete'], isFalse);
      expect('${manifest['note']}', contains('not been sent'));
    });

    test('a reference it could not resolve is named, not hidden', () async {
      // A recipe deleted from under a log, on a device that has not caught
      // up. Saying so beats a file that looks whole and is not.
      await plans.add(
        date: clock,
        slot: MealSlot.breakfast,
        refType: PlanRefType.recipe,
        refId: 'recipe-that-never-arrived',
        servings: 1,
        loggedMacros: const Macros(kcal: 100, proteinG: 1, carbG: 1, fatG: 1),
        loggedCoverage: const NutrientCoverage.notRecorded(),
      );

      final Map<String, Object?> manifest =
          (await run())['manifest']! as Map<String, Object?>;

      expect(
        (manifest['missing_references']! as List<Object?>).join(' '),
        contains('recipe-that-never-arrived'),
      );
    });

    test('it no longer claims to hold everything', () async {
      // The sentence this whole change is about. It was false in five
      // separate ways and it was the first thing a reader saw.
      expect(
        '${(await run())['note']}',
        isNot(contains('Everything else Hearth holds is here')),
      );
    });
  });
}
