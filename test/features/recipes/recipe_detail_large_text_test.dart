import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

Future<void> _reach(WidgetTester tester, String text) async {
  final Finder matches = find.text(text);
  if (matches.evaluate().isEmpty) {
    final ScrollableState scrollable = tester.state(
      find
          .byWidgetPredicate(
            (Widget w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    scrollable.position.jumpTo(0);
    await pumpFrames(tester);
    await tester.scrollUntilVisible(
      matches,
      160,
      scrollable: find
          .byWidgetPredicate(
            (Widget w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
  }
  final Finder finder = matches.last;
  await tester.ensureVisible(finder);
  await pumpFrames(tester);
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _press(WidgetTester tester, String text) async {
  await _reach(tester, text);
  await tester.tap(find.text(text).last);
  await pumpFrames(tester, frames: 12);
}

void main() {
  for (final double textScale in <double>[1, 3]) {
    testWidgets(
      'detail actions and both nutrition bases work at 320 by 568, $textScale text',
      (WidgetTester tester) async {
        final Recipe recipe = aRecipe(
          id: 'supper',
          title: 'Bean supper',
          servings: 4,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'white beans',
              amount: 2,
              unit: Units.can,
              foodId: 'beans',
            ),
          ],
          steps: <RecipeStep>[aStep('Warm the white beans.')],
        );
        await pumpHearthApp(
          tester,
          size: const Size(320, 568),
          textScale: textScale,
          viewPadding: const EdgeInsets.fromLTRB(0, 24, 0, 34),
          recipes: <Recipe>[recipe],
          foods: <Food>[
            aFood(
              'White beans',
              id: 'beans',
              servingOptions: <ServingOption>[
                aServing(
                  amount: 1,
                  unit: Units.can,
                  macros: const Macros(
                    kcal: 400,
                    proteinG: 30,
                    carbG: 60,
                    fatG: 3,
                    fiberG: 12,
                    sodiumMg: 240,
                  ),
                ),
              ],
            ),
          ],
        );
        await pumpFrames(tester);
        await _press(tester, 'Bean supper');
        await _reach(tester, 'Cook');
        await _reach(tester, 'Plan');
        await _press(tester, 'Shop');
        await _press(tester, 'Cancel');
        await _press(tester, 'Whole dish');
        await _reach(
          tester,
          '4 servings · 200 kcal each · 800 kcal whole dish',
        );
        await _press(tester, 'Per serving');
        await _press(tester, '2×');
        await _press(tester, 'Whole dish');
        await _reach(
          tester,
          '8 servings · 200 kcal each · 1600 kcal whole dish',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final double badYield in <double>[double.nan, double.infinity]) {
    testWidgets(
      'malformed yield $badYield remains readable and cannot falsely Shop',
      (WidgetTester tester) async {
        // A provider override models malformed incoming data without asking
        // SQLite to store a non-finite number in a required numeric column.
        final Recipe stored = aRecipe(
          id: 'malformed',
          title: 'Unreadable yield',
        );
        final Recipe malformed = aRecipe(
          id: stored.id,
          title: stored.title,
          servings: badYield,
          ingredients: <RecipeIngredient>[
            anIngredient('beans', amount: 1, unit: Units.can),
          ],
        );
        await pumpHearthApp(
          tester,
          recipes: <Recipe>[stored],
          extraOverrides: [
            recipeByIdProvider(stored.id)
                .overrideWith((Ref ref) async => malformed),
          ],
        );
        await pumpFrames(tester);
        await _press(tester, stored.title);
        expect(find.text('Yield not set'), findsOneWidget);
        expect(
          find.text('Set a recipe yield to see nutrition per serving.'),
          findsOneWidget,
        );
        await _press(tester, 'Shop');
        expect(find.textContaining('positive recipe yield'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Add to the list'),
              )
              .onPressed,
          isNull,
        );
        await _press(tester, 'Cancel');
        expect(find.byType(RecipeDetailScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
