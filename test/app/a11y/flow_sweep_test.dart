import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';

/// The app at large text, a step or two past the tabs (spec §6.3).
///
/// The screen sweep visits four tabs. Everything found on a small phone so
/// far has been past one of them — a sheet opened, an item chosen, a row
/// long-pressed — including one that put both actions of a long-pressed meal
/// off the bottom of the screen, so it could be neither edited nor removed.
///
/// The surfaces are declared in `swept_surfaces.dart` rather than written out
/// here, and a guard reads `lib/` and fails when something opens a sheet this
/// list does not mention. This file is now the *walking*; that file is the
/// *knowing*, and the knowing is the half that kept going missing.
void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    title: 'Slow chilli with all the trimmings',
    servings: 4,
  );

  Food yoghurt() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'o1',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 160, proteinG: 15, carbG: 8, fatG: 8),
      ),
    ],
  );

  /// One restaurant, one row: enough for the eat-out builder to have a menu
  /// and a meal, so the sheet that lists what you picked can be swept at 3x
  /// like everything else.
  Food menuItem() => aFood(
    'Harvest Bowl',
    id: 'f-chopt-harvest',
    brand: 'Chopt',
    source: FoodSource.restaurant,
    menuGroup: 'Warm bowls',
    menuOrder: 1,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'o-bowl',
        label: '1 bowl',
        amount: Quantity.of(1, Units.item),
        macros: const Macros(kcal: 690, proteinG: 26, carbG: 78, fatG: 30),
      ),
    ],
  );

  MealPlanEntry breakfast() => const MealPlanEntry(
    id: 'e1',
    dayId: 'day-1',
    slot: MealSlot.breakfast,
    refType: PlanRefType.recipe,
    refId: 'r-chilli',
    servings: 1,
  );

  Future<void> openApp(
    WidgetTester tester, {
    required Size size,
    required double scale,
  }) => pumpHearthApp(
    tester,
    size: size,
    recipes: <Recipe>[chilli()],
    foods: <Food>[yoghurt(), menuItem()],
    // A shopping list with something on it. The list screen has two shapes —
    // an empty one still leads with its setup — and `Manage list`, which is
    // what the sweep is here for, exists only in the other.
    shoppingLines: <ShoppingLine>[
      ShoppingLine(
        key: 'ground-beef',
        name: 'Ground beef',
        planned: <Quantity>[Quantity.of(2, Units.pound)],
        storeTag: 'Costco',
      ),
    ],
    entries: <MealPlanEntry>[breakfast()],
    targets: const MacroTargets(
      kcal: 2200,
      proteinG: 170,
      carbG: 200,
      fatG: 70,
    ),
    textScale: scale,
  );

  // The sizes the screen sweep uses, at the two scales that matter: ordinary,
  // and the largest iOS offers.
  const List<({Size size, String where})> devices =
      <({Size size, String where})>[
        (size: Size(390, 844), where: 'a phone'),
        (size: Size(320, 568), where: 'a small phone'),
      ];

  for (final ({Size size, String where}) device in devices) {
    for (final double scale in <double>[1.0, 3.0]) {
      final String at = '${scale}x on ${device.where}';

      for (final SweptSurface surface in sweptSurfaces) {
        testWidgets('${surface.name} survives $at', (
          WidgetTester tester,
        ) async {
          await openApp(tester, size: device.size, scale: scale);
          final SweepTools tools = SweepTools(tester);

          await surface.open(tester, tools);

          // Arrived, before anything is claimed about surviving: "no
          // exception" is equally true of a journey that never left the
          // screen it started on.
          expect(
            surface.arrived,
            findsWidgets,
            reason: '${surface.name} never opened at $at',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${surface.name} overflowed at $at',
          );

          // And to its far end, where there is one. A lazy list does not
          // build what is off the screen, and a row that is never built
          // cannot overflow.
          if (surface.farEnd case final Finder farEnd) {
            await tools.bring(farEnd);
            expect(
              tester.takeException(),
              isNull,
              reason: 'the far end of ${surface.name} overflowed at $at',
            );
          }
        });
      }

      testWidgets('a recipe opens and reads $at', (WidgetTester tester) async {
        await openApp(tester, size: device.size, scale: scale);
        final SweepTools tools = SweepTools(tester);

        await tools.tab('Recipes');
        expect(tester.takeException(), isNull, reason: 'the library at $at');

        await tools.reach(find.text('Slow chilli with all the trimmings'));
        expect(tester.takeException(), isNull, reason: 'the recipe at $at');
      });

      testWidgets('the shopping tab opens $at', (WidgetTester tester) async {
        await openApp(tester, size: device.size, scale: scale);
        await SweepTools(tester).tab('Shopping');
        expect(tester.takeException(), isNull, reason: 'shopping at $at');
      });
    }
  }
}
