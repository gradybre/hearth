import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/scale_control.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// A meal you order rather than cook (spec §5.2).
///
/// Structurally a recipe, so it plans, logs and repeats like anything else.
/// What it is not is something you shop for, scale, or cook along to — and
/// each of those is asserted here, because each is a place a burrito bowl
/// could quietly start behaving like a pot of chilli.
void main() {
  Recipe burritoBowl() => aRecipe(
    id: 'r-bowl',
    title: 'My usual bowl',
    servings: 1,
    kind: RecipeKind.eatenOut,
    ingredients: <RecipeIngredient>[
      anIngredient('chicken', amount: 4, unit: Units.ounce),
      anIngredient('white rice', amount: 4, unit: Units.ounce),
    ],
  );

  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    title: 'Chilli',
    servings: 4,
    ingredients: <RecipeIngredient>[
      anIngredient('ground beef', amount: 1, unit: Units.pound),
    ],
    steps: <RecipeStep>[aStep('Brown the beef.')],
  );

  Future<void> openRecipe(WidgetTester tester, String title) async {
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text(title));
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('lives in the Recipes tab like anything else', (
    WidgetTester tester,
  ) async {
    // Not a separate section and not hidden. A tab that quietly omitted a
    // third of what you eat would be worse than useless.
    await pumpHearthApp(tester, recipes: <Recipe>[burritoBowl(), chilli()]);
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);

    expect(find.text('My usual bowl'), findsOneWidget);
    expect(find.text('Chilli'), findsOneWidget);
  });

  testWidgets('and the chip narrows to it rather than hiding it', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, recipes: <Recipe>[burritoBowl(), chilli()]);
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);

    await tester.tap(find.text('Eaten out'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('My usual bowl'), findsOneWidget);
    expect(find.text('Chilli'), findsNothing);
  });

  testWidgets('a recipe you cook offers a cook-along and a scale', (
    WidgetTester tester,
  ) async {
    // The controls exist, so their absence in the next two tests means
    // something. Asserted separately because one test may only pump one app.
    await pumpHearthApp(tester, recipes: <Recipe>[chilli()]);
    await openRecipe(tester, 'Chilli');

    expect(find.widgetWithText(FloatingActionButton, 'Cook'), findsOneWidget);
    expect(find.byType(ScaleControl), findsOneWidget);
  });

  testWidgets('a meal you ordered offers no cook-along', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, recipes: <Recipe>[burritoBowl()]);
    await openRecipe(tester, 'My usual bowl');

    expect(find.widgetWithText(FloatingActionButton, 'Cook'), findsNothing);
  });

  testWidgets('and no scaling — you cannot order a bigger bowl', (
    WidgetTester tester,
  ) async {
    // Doubling one would silently double its macros against a portion nobody
    // served.
    await pumpHearthApp(tester, recipes: <Recipe>[burritoBowl()]);
    await openRecipe(tester, 'My usual bowl');

    expect(find.byType(ScaleControl), findsNothing);
    // But its nutrition is still there — the numbers are the whole point.
    expect(find.text('Nutrition per serving'), findsOneWidget);
  });

  testWidgets('the editor can mark one, and it saves as eaten out', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester);
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('New recipe'));
    await pumpFrames(tester);

    await tester.enterText(find.byType(TextField).first, 'My usual bowl');
    await pumpFrames(tester);

    final Finder toggle = find.byType(Switch);
    await tester.ensureVisible(toggle);
    await pumpFrames(tester);
    await tester.tap(toggle);
    await pumpFrames(tester);

    // Said in the editor, because "never goes on the shopping list" is the
    // consequence nobody would guess from the words "eaten out".
    expect(
      find.textContaining('Never goes on the shopping list'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);

    final List<RecipeRow> rows = await db.select(db.recipes).get();
    expect(rows.single.title, 'My usual bowl');
    expect(rows.single.kind, 'eaten_out');
  });

  /// Chipotle's menu, as the seed writes it: global, branded, restaurant.
  Food component(String name, double ounces, Macros macros) => aFood(
    name,
    id: 'f-${name.toLowerCase()}',
    brand: 'Chipotle',
    source: FoodSource.restaurant,
    servingOptions: <ServingOption>[
      aServing(amount: ounces, unit: Units.ounce, macros: macros),
    ],
  );

  List<Food> chipotleMenu() => <Food>[
    component('Chicken', 4, const Macros(kcal: 180, proteinG: 32, fatG: 7)),
    component(
      'Cilantro-Lime White Rice',
      4,
      const Macros(kcal: 210, proteinG: 4, carbG: 40, fatG: 4),
    ),
    component(
      'Black Beans',
      4,
      const Macros(kcal: 130, proteinG: 8, carbG: 22, fatG: 1.5),
    ),
  ];

  Future<void> typeIngredients(WidgetTester tester, String lines) async {
    await tester.enterText(
      find.byWidgetPredicate(
        (Widget w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
      ),
      lines,
    );
    await pumpFrames(tester, frames: 12);
  }

  Future<void> markEatenOut(WidgetTester tester) async {
    // `scrollUntilVisible`, not `ensureVisible`: the editor is a lazy
    // ListView and the switch sits below the ingredient rows, so with a few
    // lines typed it has not been built yet and there is no element to scroll
    // to.
    final Finder toggle = find.byType(Switch);
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    await tester.tap(toggle);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('a bowl builds itself once you say you ate out', (
    WidgetTester tester,
  ) async {
    // The whole of building one: paste the lines, flip the switch. No tap per
    // component to confirm a decision already made by saying it was eaten
    // out.
    await pumpHearthApp(tester, foods: chipotleMenu());
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('New recipe'));
    await pumpFrames(tester);

    await typeIngredients(
      tester,
      '4 oz chicken\n4 oz white rice\n4 oz black beans',
    );
    // Nothing yet: this is still a recipe somebody might be cooking.
    expect(find.text('tap to match a food'), findsNWidgets(3));

    await markEatenOut(tester);

    expect(find.text('tap to match a food'), findsNothing);
    expect(find.text('Chicken'), findsWidgets);
    expect(find.text('Cilantro-Lime White Rice'), findsWidgets);
    expect(find.text('Black Beans'), findsWidgets);
  });

  testWidgets('and flipping it back asks the question again', (
    WidgetTester tester,
  ) async {
    // What Hearth matched, Hearth matched against a library that is now the
    // wrong one. Leaving a burrito's chicken attached to a recipe somebody
    // has just said they cook would be a wrong macro nobody chose.
    await pumpHearthApp(tester, foods: chipotleMenu());
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('New recipe'));
    await pumpFrames(tester);

    await typeIngredients(tester, '4 oz chicken');
    await markEatenOut(tester);
    expect(find.text('tap to match a food'), findsNothing);

    await markEatenOut(tester);

    expect(find.text('tap to match a food'), findsOneWidget);
  });

  testWidgets('its components are picked from the library by hand', (
    WidgetTester tester,
  ) async {
    // The other half of excluding restaurant foods from automatic matching:
    // they are still perfectly pickable, and the picker searches brand as
    // well as name, so "chipotle" finds the whole menu in one query.
    await pumpHearthApp(
      tester,
      foods: <Food>[
        aFood(
          'Chicken',
          id: 'f-chipotle-chicken',
          brand: 'Chipotle',
          source: FoodSource.restaurant,
          servingOptions: <ServingOption>[
            aServing(
              amount: 4,
              unit: Units.ounce,
              macros: const Macros(kcal: 180, proteinG: 32),
            ),
          ],
        ),
      ],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('New recipe'));
    await pumpFrames(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (Widget w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
      ),
      '4 oz chicken',
    );
    await pumpFrames(tester, frames: 12);

    // Not matched for you, which is the whole point of the exclusion.
    expect(find.text('tap to match a food'), findsOneWidget);

    await tester.tap(find.text('tap to match a food'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Chicken  ·  Chipotle'), findsOneWidget);
  });
}
