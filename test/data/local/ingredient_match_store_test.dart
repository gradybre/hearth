import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';

import '../../support/fixtures.dart';

void main() {
  late HearthDatabase db;
  late IngredientMatchStore matches;
  final DateTime now = DateTime.utc(2026, 8, 27, 12);
  const String household = 'household-1';

  setUp(() async {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    matches = IngredientMatchStore(db);
    // The match table has a foreign key onto foods, so the food has to exist.
    await FoodStore(db).upsert(
      aFood('Olive oil', id: 'food-oil').withHousehold(household),
      updatedAt: now,
    );
    await FoodStore(db).upsert(
      aFood('Butter', id: 'food-butter').withHousehold(household),
      updatedAt: now,
    );
  });

  tearDown(() => db.close());

  Future<void> remember(String text, String foodId, {String id = 'm1'}) =>
      matches.remember(
        householdId: household,
        ingredientString: text,
        foodId: foodId,
        id: id,
        updatedAt: now,
      );

  test('a remembered match is found again', () async {
    await remember('evoo', 'food-oil');
    expect(
      await matches.rememberedFoodId(
        householdId: household,
        ingredientString: 'evoo',
      ),
      'food-oil',
    );
  });

  test('matching ignores case and punctuation', () async {
    // "EVOO", "evoo", and "evoo." are the same correction.
    await remember('EVOO', 'food-oil');
    for (final String variant in <String>['evoo', '  Evoo ', 'evoo.']) {
      expect(
        await matches.rememberedFoodId(
          householdId: household,
          ingredientString: variant,
        ),
        'food-oil',
        reason: variant,
      );
    }
  });

  test('correcting a match replaces the earlier one', () async {
    await remember('evoo', 'food-oil');
    await remember('evoo', 'food-butter', id: 'm2');

    expect(
      await matches.rememberedFoodId(
        householdId: household,
        ingredientString: 'evoo',
      ),
      'food-butter',
    );
    expect(await matches.allFor(household), hasLength(1));
  });

  test('another household never sees the correction', () async {
    await remember('evoo', 'food-oil');
    expect(
      await matches.rememberedFoodId(
        householdId: 'someone-else',
        ingredientString: 'evoo',
      ),
      isNull,
    );
  });

  test('forgetting removes it', () async {
    await remember('evoo', 'food-oil');
    await matches.forget(householdId: household, ingredientString: 'EVOO.');
    expect(
      await matches.rememberedFoodId(
        householdId: household,
        ingredientString: 'evoo',
      ),
      isNull,
    );
  });

  test('deleting the food removes the dangling match', () async {
    await remember('evoo', 'food-oil');
    await db.delete(db.foods).go();
    expect(await matches.allFor(household), isEmpty);
  });

  test('an empty string is never remembered', () async {
    await remember('   ', 'food-oil');
    expect(await matches.allFor(household), isEmpty);
  });
}
