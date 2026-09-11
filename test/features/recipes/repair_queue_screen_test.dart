import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The nutrition repair queue (review N04).
///
/// The three gap kinds have always been on a recipe's own macros and the
/// editor has always been able to fix one. What there was no way to do was
/// ask the library: finding the recipes with unmatched lines meant opening
/// every recipe in turn, so a half-matched import sat there quietly costing
/// every day it was logged on.
void main() {
  Food flour() => aFood(
    'Plain flour',
    id: 'f-flour',
    servingOptions: <ServingOption>[
      aServing(
        id: 's-flour',
        amount: 100,
        unit: Units.gram,
        macros: const Macros(kcal: 364, proteinG: 10, carbG: 76, fatG: 1),
      ),
    ],
  );

  Recipe broken() => aRecipe(
    id: 'r-broken',
    title: 'Half-matched lasagne',
    sections: <RecipeSection>[
      aSection(
        id: 's1',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'flour',
            amount: 200,
            unit: Units.gram,
            foodId: 'f-flour',
            sectionId: 's1',
          ),
          anIngredient(
            'ricotta',
            amount: 250,
            unit: Units.gram,
            sectionId: 's1',
          ),
          anIngredient('nutmeg', sectionId: 's1'),
        ],
      ),
    ],
  );

  Recipe whole() => aRecipe(
    id: 'r-whole',
    title: 'Flour and nothing else',
    sections: <RecipeSection>[
      aSection(
        id: 's2',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'flour',
            amount: 500,
            unit: Units.gram,
            foodId: 'f-flour',
            sectionId: 's2',
          ),
        ],
      ),
    ],
  );

  Future<void> openRepair(
    WidgetTester tester, {
    List<Recipe> recipes = const <Recipe>[],
    List<Food> foods = const <Food>[],
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    await pumpHearthApp(
      tester,
      size: size,
      textScale: scale,
      recipes: recipes,
      foods: foods,
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Nutrition repair'));
    await pumpFrames(tester, frames: 12);
  }

  group('getting there', () {
    testWidgets('it is a labelled row in the library\'s own menu', (
      WidgetTester tester,
    ) async {
      // The corner carried two icon-only buttons with their meaning in a
      // tooltip — a hover, on a device with no pointer (review §6.2.6, the
      // complaint Foods answered in #64).
      await pumpHearthApp(tester, recipes: <Recipe>[broken()]);
      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Nutrition repair'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and the household icon that duplicated Settings is gone', (
      WidgetTester tester,
    ) async {
      // The shell carries Settings on every screen since #58 and #61, so a
      // second door to it in this corner — labelled "Household", which is
      // not what it opens — was the duplicate §6.2.1 is about.
      await pumpHearthApp(tester, recipes: <Recipe>[broken()]);
      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);

      expect(find.byTooltip('Household'), findsNothing);
    });
  });

  group('what it lists', () {
    testWidgets('a recipe with gaps, and what kind they are', (
      WidgetTester tester,
    ) async {
      await openRepair(
        tester,
        recipes: <Recipe>[broken(), whole()],
        foods: <Food>[flour()],
      );

      expect(find.text('Half-matched lasagne'), findsOneWidget);
      expect(find.textContaining('1 not matched to a food'), findsOneWidget);
      expect(find.textContaining('1 with no amount'), findsOneWidget);
      // And names them, so the row says which lines rather than only how many.
      expect(find.textContaining('ricotta'), findsOneWidget);
    });

    testWidgets('and leaves a finished recipe out of it', (
      WidgetTester tester,
    ) async {
      await openRepair(
        tester,
        recipes: <Recipe>[broken(), whole()],
        foods: <Food>[flour()],
      );

      expect(find.text('Flour and nothing else'), findsNothing);
    });

    testWidgets('a food that cannot be logged at all', (
      WidgetTester tester,
    ) async {
      await openRepair(
        tester,
        foods: <Food>[aFood('Half an import', id: 'f-empty')],
      );

      expect(find.text('Foods that cannot be logged'), findsOneWidget);
      expect(find.textContaining('Half an import'), findsOneWidget);
      expect(find.textContaining('no serving'), findsOneWidget);
    });

    testWidgets('an empty library has nothing to repair', (
      WidgetTester tester,
    ) async {
      await openRepair(tester);

      expect(find.text('Nothing to repair'), findsOneWidget);
    });
  });

  group('the fixes are direct', () {
    testWidgets('a recipe row opens the editor, where a line is matched', (
      WidgetTester tester,
    ) async {
      await openRepair(
        tester,
        recipes: <Recipe>[broken()],
        foods: <Food>[flour()],
      );

      await tester.tap(find.text('Half-matched lasagne'));
      await pumpFrames(tester, frames: 20);

      // The editor, not the recipe page: the page shows the gap, the editor
      // is where an ingredient is matched.
      expect(find.text('ricotta'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    });

    testWidgets('and a food row opens that food', (WidgetTester tester) async {
      await openRepair(
        tester,
        foods: <Food>[aFood('Half an import', id: 'f-empty')],
      );

      await tester.tap(find.textContaining('Half an import'));
      await pumpFrames(tester, frames: 20);

      expect(find.widgetWithText(TextField, 'Half an import'), findsOneWidget);
    });
  });

  testWidgets('a row is on screen at twice the text on a small phone', (
    WidgetTester tester,
  ) async {
    // The same rule this screen's siblings were held to (review §6.2.4): a
    // sentence survives if it describes a consequence the label cannot. Three
    // section blurbs put 260 points of prose above the first row here, which
    // is the fault, not the fix.
    await openRepair(
      tester,
      recipes: <Recipe>[broken()],
      foods: <Food>[flour()],
      size: const Size(320, 568),
      scale: 2,
    );

    // The repair queue is a pushed route, so there is no tab bar: the bottom
    // of the screen is the fold. Half of it is the bar — being on screen by a
    // hair is not the point, and with the three section blurbs the first row
    // started 424 points down a 568-point screen, which is three quarters of
    // a repair list given over to explaining itself.
    const double fold = 568;
    final double firstRow = tester
        .getTopLeft(find.text('Half-matched lasagne'))
        .dy;
    expect(
      firstRow,
      lessThan(fold / 2),
      reason: 'the first row starts $firstRow points down of $fold',
    );
  });

  testWidgets('a food nothing says fibre about is listed, but not as a fault', (
    WidgetTester tester,
  ) async {
    // §5.6 has fibre, sodium and cholesterol as optional and nullable, so a
    // food that never stated them is being honest rather than broken. Listed
    // for somebody who wants those totals; not counted as something wrong.
    await openRepair(
      tester,
      recipes: <Recipe>[whole()],
      foods: <Food>[flour()],
    );

    expect(
      find.text('Foods that never said fibre, sodium or cholesterol'),
      findsOneWidget,
    );
    expect(find.textContaining('Plain flour'), findsOneWidget);
    expect(find.textContaining('things to fix'), findsNothing);
    expect(find.textContaining('Nothing is wrong'), findsOneWidget);
  });
}
