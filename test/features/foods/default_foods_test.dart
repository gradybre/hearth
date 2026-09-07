import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// A household's standing choices (spec §5.3).
///
/// Brendan buys the same things. Every import used to ask him again which
/// ground beef he meant, because no tier could answer: `remembered` needs
/// wording he has matched before, `mostUsed` needs a history a fresh import
/// does not have, and the best guess wants a name match that "96/4 Ground
/// Beef" and "1 lb lean ground beef" never make.
Food beef({bool isDefault = true}) => aFood(
  'Maverick Ranch 96/4 Ground Beef',
  id: 'food-beef',
  servingOptions: <ServingOption>[
    aServing(amount: 100, unit: Units.gram, macros: const Macros(kcal: 130)),
  ],
  isDefault: isDefault,
);

/// Each with a cup serving, so a matched line resolves rather than being
/// flagged for a unit the food does not know — that is a different feature's
/// failure mode and would mask this one.
Food milk(String name, String id, double kcal) => aFood(
  name,
  id: id,
  isDefault: true,
  servingOptions: <ServingOption>[
    aServing(
      amount: 1,
      unit: Units.cup,
      macros: Macros(kcal: kcal),
    ),
  ],
);

List<Food> milks() => <Food>[
  milk('Whole milk', 'milk-whole', 149),
  milk('2% milk', 'milk-2', 122),
  milk('Non-fat milk', 'milk-0', 83),
];

Future<void> openFoods(WidgetTester tester, List<Food> foods) async {
  await pumpHearthApp(tester, foods: foods);
  await tester.tap(find.text('Foods').last);
  await pumpFrames(tester);
}

/// Opens the recipe editor with one ingredient line typed in.
Future<void> openRecipeWith(
  WidgetTester tester, {
  required String line,
  required List<Food> foods,
}) async {
  await pumpHearthApp(tester, foods: foods);
  await addRecipeVia(tester, 'Write a recipe');
  await pumpFrames(tester);
  await tester.enterText(
    find.byWidgetPredicate(
      (Widget w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
    ),
    line,
  );
  await pumpFrames(tester, frames: 12);
}

void main() {
  sweepTests();
  editingExistingTests();
  zeroCalorieTests();

  group('marking a food', () {
    testWidgets('the editor offers it, and it survives a save', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pumpHearthApp(tester);
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Add a food by hand'));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField).first, 'Whole milk');
      await tester.tap(find.text('Use this by default'));
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester, frames: 12);

      // Read straight off the table rather than through a household filter:
      // what matters here is that the mark reached the row at all.
      final List<FoodRow> rows = await db.select(db.foods).get();
      expect(rows.single.name, 'Whole milk');
      expect(rows.single.isDefault, isTrue);
    });

    testWidgets('the library says which ones are marked', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, <Food>[beef(), aFood('Butter', id: 'f-butter')]);

      // Icon and word together, never colour alone (§6.3).
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.textContaining('Default  ·  '), findsOneWidget);
    });

    testWidgets('and can list only those', (WidgetTester tester) async {
      await openFoods(tester, <Food>[beef(), aFood('Butter', id: 'f-butter')]);

      await tester.tap(find.text('Defaults'));
      await pumpFrames(tester);

      expect(find.byType(FoodCard), findsOneWidget);
      expect(find.text('Butter'), findsNothing);
    });
  });

  group('a line a default answers', () {
    testWidgets('matches itself, with nobody asked', (
      WidgetTester tester,
    ) async {
      await openRecipeWith(
        tester,
        line: '1 lb lean ground beef',
        foods: <Food>[beef()],
      );

      expect(
        find.text('Maverick Ranch 96/4 Ground Beef'),
        findsOneWidget,
        reason: 'the row should show the food, not "tap to match"',
      );
      expect(find.text('tap to match a food'), findsNothing);
    });

    testWidgets('but a grade it contradicts is left alone', (
      WidgetTester tester,
    ) async {
      // Being helpful here would put the wrong macros in a day.
      await openRecipeWith(
        tester,
        line: '1 lb 88% ground beef',
        foods: <Food>[beef()],
      );

      expect(find.text('tap to match a food'), findsOneWidget);
    });

    testWidgets('and an unmarked food gets no such treatment', (
      WidgetTester tester,
    ) async {
      await openRecipeWith(
        tester,
        line: '1 lb lean ground beef',
        foods: <Food>[beef(isDefault: false)],
      );

      expect(find.text('tap to match a food'), findsOneWidget);
    });
  });

  group('a line several defaults answer', () {
    testWidgets('is not guessed at', (WidgetTester tester) async {
      // "milk" against a fridge holding whole, 2% and non-fat has genuinely
      // not said which.
      await openRecipeWith(tester, line: '1 cup milk', foods: milks());

      expect(find.text('tap to match a food'), findsOneWidget);
    });

    testWidgets('offers them all when the row is tapped', (
      WidgetTester tester,
    ) async {
      await openRecipeWith(tester, line: '1 cup milk', foods: milks());

      await tester.tap(find.text('tap to match a food'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Your defaults for'), findsOneWidget);
      expect(find.text('Whole milk'), findsOneWidget);
      expect(find.text('2% milk'), findsOneWidget);
      expect(find.text('Non-fat milk'), findsOneWidget);
      // And adding a different one as usual is still right there.
      expect(find.text('Everything else'), findsOneWidget);
      expect(find.byTooltip('Scan a barcode'), findsOneWidget);
    });

    testWidgets('a line that says which resolves on its own', (
      WidgetTester tester,
    ) async {
      await openRecipeWith(tester, line: '1 cup whole milk', foods: milks());

      expect(find.text('Whole milk'), findsOneWidget);
      expect(find.text('tap to match a food'), findsNothing);
    });
  });
}

/// Applying defaults to recipes already saved (spec §5.3, CLAUDE.md rule 4).
void sweepTests() {
  Recipe chilli() => aRecipe(
    title: 'Chilli',
    id: 'recipe-chilli',
    ingredients: <RecipeIngredient>[
      anIngredient('lean ground beef', id: 'ing-beef'),
      anIngredient('salt', id: 'ing-salt'),
    ],
  );

  Future<HearthDatabase> openRecipes(
    WidgetTester tester, {
    required List<Food> foods,
    List<Recipe> recipes = const <Recipe>[],
  }) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: foods,
      recipes: recipes,
    );
    await pumpFrames(tester);
    return db;
  }

  group('the sweep', () {
    testWidgets('is offered only when it would find something', (
      WidgetTester tester,
    ) async {
      // A button that can only ever say "nothing to do" teaches people not to
      // press it.
      await openRecipes(
        tester,
        foods: <Food>[beef(isDefault: false)],
        recipes: <Recipe>[chilli()],
      );
      expect(
        find.byTooltip('Apply defaults to unmatched ingredients'),
        findsNothing,
      );
    });

    testWidgets('proposes what it would change, and changes nothing yet', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openRecipes(
        tester,
        foods: <Food>[beef()],
        recipes: <Recipe>[chilli()],
      );

      await tester.tap(
        find.byTooltip('Apply defaults to unmatched ingredients'),
      );
      await pumpFrames(tester);

      expect(find.text('Chilli'), findsOneWidget);
      expect(find.text('lean ground beef'), findsOneWidget);
      expect(find.text('→ Maverick Ranch 96/4 Ground Beef'), findsOneWidget);
      // The line with no default is not proposed at all.
      expect(find.text('salt'), findsNothing);

      // Nothing written until Apply.
      final List<RecipeIngredientRow> before = await db
          .select(db.recipeIngredients)
          .get();
      expect(before.every((RecipeIngredientRow r) => r.foodId == null), isTrue);
    });

    testWidgets('writes only what is still ticked', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openRecipes(
        tester,
        foods: <Food>[beef()],
        recipes: <Recipe>[chilli()],
      );
      await tester.tap(
        find.byTooltip('Apply defaults to unmatched ingredients'),
      );
      await pumpFrames(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Apply 1'));
      await pumpFrames(tester, frames: 15);

      final RecipeIngredientRow beefRow =
          (await db.select(db.recipeIngredients).get()).firstWhere(
            (RecipeIngredientRow r) => r.id == 'ing-beef',
          );
      expect(beefRow.foodId, 'food-beef');
    });

    testWidgets('unticking a line leaves it alone', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openRecipes(
        tester,
        foods: <Food>[beef()],
        recipes: <Recipe>[chilli()],
      );
      await tester.tap(
        find.byTooltip('Apply defaults to unmatched ingredients'),
      );
      await pumpFrames(tester);

      await tester.tap(find.text('lean ground beef'));
      await pumpFrames(tester);

      // Nothing left ticked, so there is nothing to apply.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply 0'))
            .onPressed,
        isNull,
      );

      final RecipeIngredientRow beefRow =
          (await db.select(db.recipeIngredients).get()).firstWhere(
            (RecipeIngredientRow r) => r.id == 'ing-beef',
          );
      expect(beefRow.foodId, isNull);
    });
  });
}

/// Confirming a food really is zero, rather than missing its numbers
/// (spec §5.5).
void zeroCalorieTests() {
  Future<void> openNewFood(WidgetTester tester) async {
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Add a food by hand'));
    await pumpFrames(tester);
  }

  group('the zero-calorie confirmation', () {
    testWidgets('is offered when a food has nothing on it', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester);
      await openNewFood(tester);

      // A blank draft opens on 100 g with no macros, which is exactly the
      // state where "is that zero, or is it missing?" is a real question.
      expect(find.text('This really is 0 calories'), findsOneWidget);
    });

    testWidgets('and hidden once the food has real numbers', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester);
      await openNewFood(tester);

      // The macro fields carry their label above them rather than inside, so
      // the field is reached through the labelled widget it belongs to.
      await tester.enterText(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text('kcal'),
                    matching: find.byType(Column),
                  )
                  .first,
              matching: find.byType(TextField),
            )
            .first,
        '120',
      );
      await pumpFrames(tester);

      expect(find.text('This really is 0 calories'), findsNothing);
    });

    testWidgets('survives the save, so the warning stays cleared', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pumpHearthApp(tester);
      await openNewFood(tester);

      await tester.enterText(find.byType(TextField).first, 'Black coffee');
      await pumpFrames(tester);
      await tester.tap(find.text('This really is 0 calories'));
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester, frames: 12);

      final List<FoodRow> rows = await db.select(db.foods).get();
      expect(rows.single.name, 'Black coffee');
      expect(rows.single.isZeroCalorie, isTrue);
    });

    testWidgets('an unconfirmed empty food is still flagged in the list', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, <Food>[
        aFood(
          'Mystery import',
          id: 'food-mystery',
          servingOptions: <ServingOption>[
            aServing(amount: 100, unit: Units.gram, macros: Macros.zero),
          ],
        ),
      ]);
      await tester.tap(find.text('Needs attention'));
      await pumpFrames(tester);

      expect(find.text('Mystery import'), findsOneWidget);
    });

    testWidgets('and a confirmed one is not', (WidgetTester tester) async {
      await openFoods(tester, <Food>[
        aFood(
          'Black coffee',
          id: 'food-coffee',
          isZeroCalorie: true,
          servingOptions: <ServingOption>[
            aServing(amount: 1, unit: Units.cup, macros: Macros.zero),
          ],
        ),
      ]);
      await tester.tap(find.text('Needs attention'));
      await pumpFrames(tester);

      expect(find.text('Black coffee'), findsNothing);
    });
  });
}

/// Editing an existing food, which is where Brendan hit it (spec §5.5).
void editingExistingTests() {
  testWidgets('marking an existing food default sticks through a save', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      // With a serving: a food without one fails validation and never
      // reaches the save at all, which would make this test pass or fail for
      // a reason that has nothing to do with the flag.
      foods: <Food>[
        aFood(
          'Maverick Ranch 96/4 Ground Beef',
          id: 'food-beef',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 130),
            ),
          ],
        ),
      ],
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Maverick Ranch 96/4 Ground Beef'));
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.text('Use this by default'));
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 12);

    final FoodRow saved = await (db.select(
      db.foods,
    )..where(($FoodsTable f) => f.id.equals('food-beef'))).getSingle();
    expect(saved.isDefault, isTrue);
  });

  testWidgets('and unmarking it sticks too', (WidgetTester tester) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[
        aFood(
          'Whole milk',
          id: 'food-milk',
          isDefault: true,
          servingOptions: <ServingOption>[
            aServing(
              amount: 1,
              unit: Units.cup,
              macros: const Macros(kcal: 149),
            ),
          ],
        ),
      ],
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    // The editor reads the food through a provider, so it needs frames to
    // get past its spinner before the switch is the food's own value.
    await tester.tap(find.text('Whole milk'));
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.text('Use this by default'));
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 12);

    final FoodRow saved = await (db.select(
      db.foods,
    )..where(($FoodsTable f) => f.id.equals('food-milk'))).getSingle();
    expect(saved.isDefault, isFalse);
  });
}
