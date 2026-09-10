import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Knowing what you picked (spec §5.2, review §7.6 and N03).
///
/// The whole of the selected state was a floating button reading "Build (3)":
/// a count and a verb, no total, and no way to see the three without
/// scrolling the menu again. On a 44-row menu the first pick is thirty rows
/// above the fold by the time you make the third, and the picks are what the
/// day's nutrition gets costed from.
void main() {
  Food item(String name, {String? section, int? order, Macros? macros}) =>
      aFood(
        name,
        id: 'f-chopt-${name.toLowerCase().replaceAll(' ', '-')}',
        brand: 'Chopt',
        source: FoodSource.restaurant,
        menuGroup: section,
        menuOrder: order,
        servingOptions: <ServingOption>[
          aServing(
            amount: 4,
            unit: Units.ounce,
            macros: macros ?? const Macros(kcal: 100, proteinG: 10),
          ),
        ],
      );

  List<Food> menu() => <Food>[
    item(
      'Harvest Bowl',
      section: 'Warm bowls',
      order: 1,
      macros: const Macros(kcal: 690, proteinG: 26),
    ),
    item(
      'Kale Caesar',
      section: 'Salads',
      order: 2,
      macros: const Macros(kcal: 520, proteinG: 18),
    ),
    item(
      'Guacamole',
      section: 'Toppings',
      order: 3,
      macros: const Macros(kcal: 150, proteinG: 2),
    ),
  ];

  Future<void> openMenu(WidgetTester tester, {List<Recipe>? recipes}) async {
    await pumpHearthApp(
      tester,
      foods: menu(),
      recipes: recipes ?? const <Recipe>[],
      // Tall enough that the three rows fit under the search field and the
      // chip rail. What is under test is the summary, and a test that has to
      // scroll to reach a row is one scroll away from testing the list.
      size: const Size(390, 1200),
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await addRecipeVia(tester, 'Eat out');
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Chopt'));
    await pumpFrames(tester, frames: 12);
  }

  Future<void> pick(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await pumpFrames(tester, frames: 12);
  }

  group('the summary', () {
    testWidgets('counts what is picked and what it comes to', (
      WidgetTester tester,
    ) async {
      await openMenu(tester);
      await pick(tester, 'Harvest Bowl');
      await pick(tester, 'Guacamole');

      expect(find.text('2 items · 840 kcal'), findsOneWidget);
      expect(find.text('Review meal'), findsOneWidget);
    });

    testWidgets('and says nothing at all until something is picked', (
      WidgetTester tester,
    ) async {
      // The same as the floating button it replaces: an empty meal has no
      // summary to show and no action to offer.
      await openMenu(tester);

      expect(find.text('Review meal'), findsNothing);
      expect(find.textContaining('items ·'), findsNothing);
    });

    testWidgets('a row with no published nutrition is counted, not hidden', (
      WidgetTester tester,
    ) async {
      // Under-reporting is the one thing a running total must not do. A menu
      // row the chain never published a figure for is said out loud rather
      // than quietly summed as zero (spec §5.5).
      await pumpHearthApp(
        tester,
        size: const Size(390, 1200),
        foods: <Food>[
          item(
            'Harvest Bowl',
            section: 'Warm bowls',
            order: 1,
            macros: const Macros(kcal: 690, proteinG: 26),
          ),
          aFood(
            'Seasonal special',
            id: 'f-chopt-special',
            brand: 'Chopt',
            source: FoodSource.restaurant,
            menuGroup: 'Warm bowls',
            menuOrder: 2,
          ),
        ],
      );
      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await addRecipeVia(tester, 'Eat out');
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Chopt'));
      await pumpFrames(tester, frames: 12);

      await pick(tester, 'Harvest Bowl');
      await pick(tester, 'Seasonal special');

      expect(find.textContaining('1 unknown'), findsOneWidget);
    });
  });

  group('what you picked', () {
    testWidgets('opens without scrolling the menu again', (
      WidgetTester tester,
    ) async {
      await openMenu(tester);
      await pick(tester, 'Kale Caesar');
      await pick(tester, 'Guacamole');

      await tester.tap(find.text('2 items · 670 kcal'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('What you picked'), findsOneWidget);
      expect(find.text('Kale Caesar'), findsWidgets);
      expect(find.text('Guacamole'), findsWidgets);
    });

    testWidgets('and a pick can be dropped from it', (
      WidgetTester tester,
    ) async {
      await openMenu(tester);
      await pick(tester, 'Kale Caesar');
      await pick(tester, 'Guacamole');

      await tester.tap(find.text('2 items · 670 kcal'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Drop Guacamole').first);
      await pumpFrames(tester, frames: 20);

      expect(find.text('1 item · 520 kcal'), findsOneWidget);
    });
  });

  group('your usual orders', () {
    Recipe usual() => aRecipe(
      id: 'r-usual',
      title: 'My usual bowl',
      kind: RecipeKind.eatenOut,
      notes: 'Chopt',
      ingredients: <RecipeIngredient>[
        anIngredient('Harvest Bowl', foodId: 'f-chopt-harvest-bowl'),
      ],
    );

    testWidgets('are offered above the menu', (WidgetTester tester) async {
      await openMenu(tester, recipes: <Recipe>[usual()]);

      expect(find.text('Your usual orders'), findsOneWidget);
      expect(find.text('My usual bowl'), findsOneWidget);
    });

    testWidgets('and are not offered when there are none', (
      WidgetTester tester,
    ) async {
      await openMenu(tester);

      expect(find.text('Your usual orders'), findsNothing);
    });

    testWidgets('a cooked recipe is not one of them', (
      WidgetTester tester,
    ) async {
      await openMenu(
        tester,
        recipes: <Recipe>[
          aRecipe(
            id: 'r-home',
            title: 'Guacamole at home',
            ingredients: <RecipeIngredient>[
              anIngredient('Guacamole', foodId: 'f-chopt-guacamole'),
            ],
          ),
        ],
      );

      expect(find.text('Your usual orders'), findsNothing);
    });
  });
}
