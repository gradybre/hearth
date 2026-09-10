import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// What the logging picker is searching (review §7's picker scopes).
///
/// The list is three different things stacked: what the household has saved,
/// and — underneath, in the same scroll — what the nutrition sources
/// returned. "Recipes" and "Foods" named the *kind* and never the *scope*,
/// which is the distinction that matters when the next heading down is
/// "Elsewhere" and those rows write to the library when you pick one.
void main() {
  testWidgets('the saved groups say whose they are', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[aRecipe(id: 'r-1', title: 'Oat pancakes')],
      foods: <Food>[
        aFood(
          'Oats',
          id: 'f-oats',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 380, proteinG: 13),
            ),
          ],
        ),
      ],
    );
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Add to breakfast').first);
    await pumpFrames(tester, frames: 12);

    expect(find.text('Your recipes'), findsOneWidget);
    expect(find.text('Your foods'), findsOneWidget);

    // Not asserted: that the bare words are gone from the screen. They are
    // not, and should not be — "Recipes" and "Foods" are two of the four
    // navigation tabs underneath the sheet, and a finder that demanded their
    // absence was failing on the tab bar rather than on anything this test
    // is about.
  });
}
