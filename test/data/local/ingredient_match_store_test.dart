import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';
import 'package:hearth/domain/foods/no_match_rule.dart';

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

  noMatchTests(() => db, () => matches, now);

  // No id: the store derives one from the household and the wording, so two
  // phones deciding the same thing land on the same row rather than on two
  // the unique index will not accept.
  Future<void> remember(String text, String foodId) => matches.remember(
    householdId: household,
    ingredientString: text,
    foodId: foodId,
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
    // Same wording, so the same derived id: the correction replaces the row
    // rather than sitting beside it.
    await remember('evoo', 'food-butter');

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

/// Wordings that need no food at all (spec §5.3).
///
/// Shares the file's own database rather than opening a second one: two
/// `HearthDatabase` instances in one test file is what drift's
/// multiple-databases warning is about, and the warning was right.
void noMatchTests(
  HearthDatabase Function() database,
  IngredientMatchStore Function() matches,
  DateTime now,
) {
  Future<void> markNoMatch(String wording) => matches().rememberNoMatch(
    householdId: 'household-1',
    ingredientString: wording,
    updatedAt: now,
  );

  group('one row, three answers', () {
    test('a wording marked as needing no food comes back marked', () async {
      await markNoMatch('fish sauce');
      final NoMatchRules rules = await matches().noMatchRules('household-1');

      expect(rules.marked, contains('fish sauce'));
      expect(rules.covers('fish sauce'), isTrue);
    });

    test('it is not a food match, so it stays out of that map', () async {
      await markNoMatch('salt');
      expect(await matches().allFor('household-1'), isEmpty);
      expect(
        await matches().rememberedFoodId(
          householdId: 'household-1',
          ingredientString: 'salt',
        ),
        isNull,
      );
    });

    test('a built-in turned back off is a row answering neither', () async {
      await matches().rememberNeedsMatch(
        householdId: 'household-1',
        ingredientString: 'water',
        updatedAt: now,
      );
      final NoMatchRules rules = await matches().noMatchRules('household-1');

      expect(rules.unmarked, contains('water'));
      expect(rules.covers('water'), isFalse);
      expect(rules.covers('salt'), isTrue, reason: 'the rest still stand');
    });
  });

  group('a wording keeps one answer', () {
    test('a food match replaces a no-match rule', () async {
      await database()
          .into(database().foods)
          .insert(
            FoodsCompanion.insert(
              id: 'food-1',
              name: 'Fish sauce',
              updatedAt: now,
            ),
          );
      await markNoMatch('fish sauce');
      await matches().remember(
        householdId: 'household-1',
        ingredientString: 'fish sauce',
        foodId: 'food-1',
        updatedAt: now,
      );

      expect(await matches().allFor('household-1'), <String, String>{
        'fish sauce': 'food-1',
      });
      expect(
        (await matches().noMatchRules('household-1')).marked,
        isNot(contains('fish sauce')),
      );
    });

    test('and a no-match rule replaces a food match', () async {
      await database()
          .into(database().foods)
          .insert(
            FoodsCompanion.insert(
              id: 'food-1',
              name: 'Fish sauce',
              updatedAt: now,
            ),
          );
      await matches().remember(
        householdId: 'household-1',
        ingredientString: 'fish sauce',
        foodId: 'food-1',
        updatedAt: now,
      );
      await markNoMatch('fish sauce');

      expect(await matches().allFor('household-1'), isEmpty);
      expect(
        (await matches().noMatchRules('household-1')).marked,
        contains('fish sauce'),
      );
    });

    test('the database refuses a row claiming both', () async {
      // The CHECK that replaced the NOT NULL. A row answering a food *and*
      // no-match is a bug, and this is where it stops.
      await database()
          .into(database().foods)
          .insert(
            FoodsCompanion.insert(id: 'food-1', name: 'Salt', updatedAt: now),
          );
      await expectLater(
        database()
            .into(database().ingredientMatches)
            .insert(
              IngredientMatchesCompanion.insert(
                id: 'bad',
                householdId: 'household-1',
                ingredientString: 'salt',
                foodId: const Value<String?>('food-1'),
                needsNoMatch: const Value<bool>(true),
                updatedAt: now,
              ),
            ),
        throwsA(anything),
      );
    });
  });
}
