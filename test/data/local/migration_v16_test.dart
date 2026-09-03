import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';

import '../../support/fixtures.dart';

/// The one-shot re-keying that turns a hyphen into a separator (schema v16).
///
/// Worth its own file because it runs exactly once, on a real device, over
/// data that took months to accumulate — and unlike everything else here, a
/// mistake is not something the next launch puts right. The rows are inserted
/// raw rather than through the store, because the store would normalise them
/// on the way in and there would be nothing left to migrate.
void main() {
  late HearthDatabase db;
  const String household = 'household-1';
  final DateTime now = DateTime.utc(2026, 9, 3, 12);

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    await FoodStore(db).upsert(
      aFood('Sun-dried tomatoes', id: 'food-old').withHousehold(household),
      updatedAt: now,
    );
    await FoodStore(db).upsert(
      aFood('Sun dried tomatoes', id: 'food-new').withHousehold(household),
      updatedAt: now,
    );
  });

  tearDown(() => db.close());

  /// A row as it was written before v16, bypassing the store's normalisation.
  Future<void> oldRow({
    required String id,
    required String wording,
    required String foodId,
    required DateTime updatedAt,
    String householdId = household,
  }) => db
      .into(db.ingredientMatches)
      .insert(
        IngredientMatchesCompanion.insert(
          id: id,
          householdId: householdId,
          ingredientString: wording,
          foodId: Value<String?>(foodId),
          updatedAt: updatedAt,
        ),
      );

  Future<List<IngredientMatchRow>> matches() =>
      db.select(db.ingredientMatches).get();

  test('the two spellings collapse to one row, newest answer kept', () async {
    await oldRow(
      id: 'old',
      wording: 'sun-dried tomatoes',
      foodId: 'food-old',
      updatedAt: now.subtract(const Duration(days: 10)),
    );
    await oldRow(
      id: 'new',
      wording: 'sun dried tomatoes',
      foodId: 'food-new',
      updatedAt: now,
    );

    await db.renormaliseForV16();

    final List<IngredientMatchRow> after = await matches();
    expect(after, hasLength(1));
    expect(after.single.ingredientString, 'sun dried tomatoes');
    expect(after.single.foodId, 'food-new');
  });

  test('a row that needs no re-keying is left exactly as it was', () async {
    await oldRow(
      id: 'plain',
      wording: 'olive oil',
      foodId: 'food-old',
      updatedAt: now,
    );

    await db.renormaliseForV16();

    final List<IngredientMatchRow> after = await matches();
    expect(after.single.id, 'plain');
    expect(after.single.ingredientString, 'olive oil');
    // Compared as an instant: Drift stores local time, so a UTC fixture reads
    // back shifted by the zone offset while naming the same moment.
    expect(after.single.updatedAt.isAtSameMomentAs(now), isTrue);
  });

  test('another household is never merged into yours', () async {
    // The unique key is per household, and so is the collision.
    await oldRow(
      id: 'mine',
      wording: 'sun-dried tomatoes',
      foodId: 'food-old',
      updatedAt: now,
    );
    await oldRow(
      id: 'theirs',
      wording: 'sun dried tomatoes',
      foodId: 'food-new',
      updatedAt: now,
      householdId: 'household-2',
    );

    await db.renormaliseForV16();

    expect(await matches(), hasLength(2));
  });

  test('a wording that normalises to nothing is dropped', () async {
    // It was never findable — no query could ever produce the empty key.
    await oldRow(
      id: 'junk',
      wording: '---',
      foodId: 'food-old',
      updatedAt: now,
    );

    await db.renormaliseForV16();

    expect(await matches(), isEmpty);
  });

  test('running it twice changes nothing the second time', () async {
    // Drift runs the step once, but a half-finished upgrade that is retried
    // must not merge away a row it already kept.
    await oldRow(
      id: 'old',
      wording: 'sun-dried tomatoes',
      foodId: 'food-old',
      updatedAt: now.subtract(const Duration(days: 1)),
    );
    await oldRow(
      id: 'new',
      wording: 'sun dried tomatoes',
      foodId: 'food-new',
      updatedAt: now,
    );

    await db.renormaliseForV16();
    final List<IngredientMatchRow> once = await matches();
    await db.renormaliseForV16();

    expect(await matches(), hasLength(once.length));
    expect((await matches()).single.foodId, once.single.foodId);
  });

  group('an in-flight shopping list keeps its ticks', () {
    Future<void> list() => db
        .into(db.shoppingLists)
        .insert(
          ShoppingListRow(
            id: 'list-1',
            householdId: household,
            fromDate: now,
            toDate: now.add(const Duration(days: 6)),
            status: 'draft',
            updatedAt: now,
          ),
        );

    Future<void> item({
      required String id,
      required String key,
      String? foodId,
      bool checked = true,
    }) => db
        .into(db.shoppingListItems)
        .insert(
          ShoppingItemRow(
            id: id,
            listId: 'list-1',
            itemKey: key,
            foodId: foodId,
            name: key,
            checked: checked,
            isManual: false,
            hasUnquantified: false,
            sortOrder: 0,
            sourceRecipeIds: '',
            plannedRest: '[]',
            updatedAt: now,
          ),
        );

    test(
      'an unmatched line is re-keyed so the next rebuild finds it',
      () async {
        // Without this the rebuild sees a new line and silently drops the tick.
        await list();
        await item(id: 'i1', key: 'sun-dried tomatoes');

        await db.renormaliseForV16();

        final ShoppingItemRow row =
            (await db.select(db.shoppingListItems).get()).single;
        expect(row.itemKey, 'sun dried tomatoes');
        expect(row.checked, isTrue);
      },
    );

    test('two lines that collide after re-keying become one', () async {
      // Review finding: the re-key had no merge step for shopping items. Two
      // rows sharing (list, key) derive the same id, so the next save would
      // insert both under one primary key and fail — and on the server the
      // unique (shopping_list_id, item_key) refused the migration outright.
      await list();
      await item(id: 'i1', key: 'sun-dried tomatoes', checked: false);
      await item(id: 'i2', key: 'sun dried tomatoes');

      await db.renormaliseForV16();

      final List<ShoppingItemRow> left = await db
          .select(db.shoppingListItems)
          .get();
      expect(left, hasLength(1));
      expect(left.single.itemKey, 'sun dried tomatoes');
    });

    test(
      'a matched line is left alone, because its key is a food id',
      () async {
        await list();
        await item(id: 'i2', key: 'food-old', foodId: 'food-old');

        await db.renormaliseForV16();

        expect(
          (await db.select(db.shoppingListItems).get()).single.itemKey,
          'food-old',
        );
      },
    );
  });
}
