import 'dart:ui' show CheckedState, SemanticsFlags, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Every node that announces itself as a control must also be operable.
///
/// The trap this guards is `Semantics(button: true, excludeSemantics: true)`
/// wrapped around an `InkWell`: excluding descendants drops the InkWell's tap
/// action, so the node tells a screen-reader user "button" and then does
/// nothing when they activate it. Announcing a control you cannot press is
/// worse than not announcing it — the user has no way to know the difference
/// between a broken control and their own mistake (spec §6.3).
List<String> unactivatable(SemanticsNode root) {
  final List<String> offenders = <String>[];

  void visit(SemanticsNode node) {
    final SemanticsData data = node.getSemanticsData();
    final SemanticsFlags flags = data.flagsCollection;
    final bool claimsControl =
        flags.isButton ||
        flags.isChecked != CheckedState.none ||
        flags.isSelected != Tristate.none;
    final bool operable =
        data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.increase) ||
        data.hasAction(SemanticsAction.decrease);

    if (claimsControl && !operable) {
      offenders.add('"${data.label}"');
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return offenders;
}

void main() {
  testWidgets('every announced control on the home screen can be activated', (
    WidgetTester tester,
  ) async {
    // Its section cards use exactly the pattern above — a Semantics button
    // wrapped around an InkWell with descendants excluded — and a home screen
    // whose cards announce themselves and then do nothing would be the first
    // thing a screen-reader user met (spec §6.3).
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(tester, launchTarget: LaunchTarget.home);
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });

  testWidgets('and so can the way back out of a section', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(tester);
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });

  testWidgets(
    'every announced control on the recipe library can be activated',
    (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(
            id: 'ribs',
            title: 'Braised short ribs',
            cuisine: 'French',
            tags: <String>['sunday'],
            sections: <RecipeSection>[aSection(id: 'sec-ribs')],
          ),
        ],
      );
      await pumpFrames(tester);

      expect(
        unactivatable(tester.getSemantics(find.byType(MaterialApp))),
        isEmpty,
      );
      handle.dispose();
    },
  );

  testWidgets('every announced control on the planner can be activated', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(tester);
    await tester.tap(find.text('Plan'));
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });

  testWidgets('every announced control on the week summary can be activated', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(tester);
    await tester.tap(find.text('Plan'));
    await pumpFrames(tester);
    await tester.tap(find.text('Week'));
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });

  testWidgets('every announced control on the settings screen can be '
      'activated', (WidgetTester tester) async {
    // The densest use of the pattern in the app: every settings row and every
    // theme option announces itself as a button — and the theme options as a
    // selected one — with their descendants excluded. Six wrappers, none of
    // them guarded until now.
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(tester, size: const Size(500, 2400));
    await tester.tap(find.byTooltip('Settings').last);
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });

  testWidgets(
    'every announced control in the eat-out builder can be activated',
    (WidgetTester tester) async {
      // The trap above is exactly what this screen walked into: a
      // `Semantics(selected:, excludeSemantics: true)` wrapped around the row's
      // `InkWell`, announcing every menu row as a selectable thing and then
      // dropping the tap that selects it. It was found by reading rather than
      // by this file, which is the gap — a screen this guard does not visit is
      // a screen the regression can come back to unnoticed.
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpHearthApp(
        tester,
        foods: <Food>[
          aFood(
            'Single Steakburger',
            brand: "Freddy's",
            source: FoodSource.restaurant,
            menuGroup: 'Steakburgers',
            menuOrder: 0,
            servingOptions: <ServingOption>[
              aServing(
                amount: 1,
                unit: Units.item,
                macros: const Macros(kcal: 380, proteinG: 24),
              ),
            ],
          ),
          aFood(
            'Lettuce',
            brand: "Freddy's",
            source: FoodSource.restaurant,
            menuGroup: 'Toppings',
            menuOrder: 1,
            servingOptions: <ServingOption>[
              aServing(
                amount: 1,
                unit: Units.ounce,
                macros: const Macros(kcal: 3, carbG: 1),
              ),
            ],
          ),
          aFood(
            'Make it a Lettuce Wrap',
            brand: "Freddy's",
            source: FoodSource.restaurant,
            menuGroup: 'Modifications',
            menuOrder: 2,
            isModifier: true,
            servingOptions: <ServingOption>[
              aServing(
                amount: 1,
                unit: Units.item,
                macros: const Macros(kcal: -180, carbG: -25, fiberG: 1),
              ),
            ],
          ),
        ],
      );
      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await addRecipeVia(tester, 'Eat out');
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text("Freddy's"));
      await pumpFrames(tester, frames: 12);

      // Both states of a row, because "selected" is announced in both and the
      // stepper and the take-out button only exist in one of them.
      expect(
        unactivatable(tester.getSemantics(find.byType(MaterialApp))),
        isEmpty,
      );

      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Take Lettuce out'));
      await pumpFrames(tester, frames: 12);

      expect(
        unactivatable(tester.getSemantics(find.byType(MaterialApp))),
        isEmpty,
      );
      handle.dispose();
    },
  );

  testWidgets('every announced control in the log sheet can be activated', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    await pumpHearthApp(
      tester,
      recipes: <Recipe>[
        aRecipe(
          id: 'ribs',
          title: 'Braised short ribs',
          sections: <RecipeSection>[aSection(id: 'sec-ribs')],
        ),
      ],
    );
    await tester.tap(find.text('Plan'));
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.add).first);
    await pumpFrames(tester);

    expect(
      unactivatable(tester.getSemantics(find.byType(MaterialApp))),
      isEmpty,
    );
    handle.dispose();
  });
}
