import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The food editor's "Package & nutrition" section (spec R4, R9-R10).
///
/// The field's move out of the Walmart-specific area, the weight display
/// control, the live preview, and -- the part that matters most -- that a
/// package relationship is only ever used once somebody has confirmed it.
void main() {
  Future<void> reveal(WidgetTester tester, Finder target) async {
    final list = find.byType(Scrollable).first;
    if (target.evaluate().isEmpty) {
      await tester.drag(list, const Offset(0, 3000));
      await pumpFrames(tester);
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: list,
        maxScrolls: 25,
      );
    }
    await tester.ensureVisible(target);
    await pumpFrames(tester);
  }

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await reveal(tester, target);
    await tester.tap(target);
    await pumpFrames(tester);
  }

  Future<HearthDatabase> openNewFoodEditor(WidgetTester tester) async {
    final db = await pumpHearthApp(tester);
    await tapVisible(tester, find.text('Foods').last);
    await pumpFrames(tester);
    await tapVisible(tester, find.text('Add food'));
    await pumpFrames(tester);
    await tapVisible(tester, find.text('Enter it by hand'));
    await pumpFrames(tester);
    await reveal(tester, find.text('Package & nutrition'));
    return db;
  }

  Future<void> openFoodFromLibrary(WidgetTester tester, Food food) async {
    await pumpHearthApp(tester, foods: <Food>[food]);
    await tapVisible(tester, find.text('Foods').last);
    await pumpFrames(tester);
    await tapVisible(tester, find.text(food.name));
    await pumpFrames(tester);
    await reveal(tester, find.text('Package & nutrition'));
  }

  Future<void> enterLabeled(
    WidgetTester tester,
    String label,
    String text,
  ) async {
    await reveal(tester, find.text(label));
    final Finder column = find
        .ancestor(of: find.text(label), matching: find.byType(Column))
        .first;
    await tester.enterText(
      find.descendant(of: column, matching: find.byType(TextField)),
      text,
    );
    await pumpFrames(tester, frames: 2);
  }

  /// Fills in a cup serving and a complete package entry, which is the
  /// state every confirm test starts from.
  Future<void> fillCupPackage(WidgetTester tester) async {
    await enterLabeled(tester, 'Name', 'Shredded cheddar');
    await enterLabeled(tester, 'Amount', '1');
    // The starter row opens in grams; a package relationship needs a volume
    // serving to anchor to.
    await tapVisible(tester, find.text('g').first);
    await pumpFrames(tester, frames: 4);
    await tapVisible(tester, find.text('cup').last);
    await pumpFrames(tester, frames: 4);

    await enterLabeled(tester, 'Package amount', '10 oz');
    await enterLabeled(tester, 'Servings per package', '2');

    await tapVisible(tester, find.text('Choose a serving'));
    await pumpFrames(tester, frames: 4);
    await tapVisible(tester, find.text('1 cup').last);
    await pumpFrames(tester, frames: 4);
  }

  Food cheddarWithRelation() {
    final PackageNutrition relation = PackageNutrition.manual(
      servingsPerPackage: 2,
      servingOptionId: 'serving-cup',
      servingAmount: Quantity.of(1, Units.cup),
      packageAmount: Quantity.of(10, Units.ounce),
    );
    return aFood(
      'Shredded cheddar',
      packSize: Quantity.of(10, Units.ounce),
      servingOptions: <ServingOption>[
        aServing(
          id: 'serving-cup',
          amount: 1,
          unit: Units.cup,
          macros: const Macros(kcal: 100),
        ),
      ],
      packageNutrition: relation,
    );
  }

  testWidgets(
    'the package amount field lives in its own section, not under Walmart',
    (WidgetTester tester) async {
      await openNewFoodEditor(tester);

      expect(find.text('Package & nutrition'), findsOneWidget);
      expect(find.text('Package amount'), findsOneWidget);
      await reveal(tester, find.text('Buying it at Walmart'));
      expect(find.text('Buying it at Walmart'), findsOneWidget);
      // One field, not two independently editable copies (spec R10).
      expect(find.text('Sold in'), findsNothing);
    },
  );

  testWidgets('the weight display control defaults to Automatic', (
    WidgetTester tester,
  ) async {
    await openNewFoodEditor(tester);

    expect(find.text('Weight display'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
  });

  testWidgets("choosing Weight updates the control's own display", (
    WidgetTester tester,
  ) async {
    await openNewFoodEditor(tester);

    await tapVisible(tester, find.text('Automatic'));
    await pumpFrames(tester, frames: 4);
    await tapVisible(tester, find.text('Weight (oz/lb)').last);
    await pumpFrames(tester, frames: 4);

    expect(find.text('Weight (oz/lb)'), findsOneWidget);
  });

  testWidgets('a complete entry previews, and waits to be confirmed', (
    WidgetTester tester,
  ) async {
    await openNewFoodEditor(tester);
    await fillCupPackage(tester);

    expect(
      find.textContaining('1 package (10 oz) = 2 servings'),
      findsOneWidget,
    );
    // Nothing is in effect yet, and the screen says so.
    expect(find.textContaining('Not used yet'), findsOneWidget);
    expect(find.text('Use package servings'), findsOneWidget);
    expect(find.text('Package servings in use.'), findsNothing);
  });

  testWidgets('confirming it inline is what puts it in use', (
    WidgetTester tester,
  ) async {
    await openNewFoodEditor(tester);
    await fillCupPackage(tester);

    await tapVisible(tester, find.text('Use package servings'));
    await pumpFrames(tester, frames: 4);

    expect(
      find.text('Package servings confirmed. Save to apply.'),
      findsOneWidget,
    );
    expect(find.textContaining('Not used yet'), findsNothing);
  });

  testWidgets('changing the count after confirming asks again', (
    WidgetTester tester,
  ) async {
    await openFoodFromLibrary(tester, cheddarWithRelation());

    expect(find.text('Package servings in use.'), findsOneWidget);

    await enterLabeled(tester, 'Servings per package', '4');

    expect(find.text('Confirm package servings'), findsOneWidget);
    expect(find.textContaining('Not used yet'), findsOneWidget);
  });

  testWidgets('a food whose package no longer matches its relationship asks to '
      'check it', (WidgetTester tester) async {
    await openFoodFromLibrary(tester, cheddarWithRelation());
    expect(find.textContaining('Check package servings'), findsNothing);

    await enterLabeled(tester, 'Package amount', '12 oz');

    expect(find.textContaining('Check package servings'), findsOneWidget);
    // Stale, not pending: it never stands in the way of saving.
    expect(find.text('Confirm package servings'), findsOneWidget);
  });

  testWidgets('an unrelated edit saves a stale relationship untouched', (
    WidgetTester tester,
  ) async {
    await openFoodFromLibrary(tester, cheddarWithRelation());

    await enterLabeled(tester, 'Package amount', '12 oz');
    await enterLabeled(tester, 'Name', 'Sharp cheddar');

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 12);

    // Back out of the editor rather than stuck in it.
    expect(find.text('Edit food'), findsNothing);
  });

  testWidgets('manual package saves and reopens with six servings in 30 oz', (
    tester,
  ) async {
    final db = await openNewFoodEditor(tester);
    await fillCupPackage(tester);
    await tapVisible(tester, find.text('Use package servings'));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 16);
    final rows = await tester.runAsync(() => db.select(db.foods).get());
    expect(rows, hasLength(1));
    final food = await tester.runAsync(
      () => FoodStore(db).byId(rows!.single.id),
    );
    expect(food!.activePackageServing, isNotNull);
    expect(food.packageNutrition!.servingsPerPackage, 2);
    final reopened = FoodDraft.fromFood(food);
    expect(reopened.hasStalePackageNutrition, isFalse);
    expect(reopened.packageNutritionNeedsConfirmation, isFalse);
    expect(
      reopened.toFood().packageGramsPerMillilitre,
      food.packageGramsPerMillilitre,
    );
  });

  testWidgets('the link can be removed outright', (WidgetTester tester) async {
    await openFoodFromLibrary(tester, cheddarWithRelation());

    await tester.scrollUntilVisible(
      find.text('Remove package/nutrition link'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapVisible(tester, find.text('Remove package/nutrition link'));
    await pumpFrames(tester, frames: 4);

    expect(find.text('Package servings in use.'), findsNothing);
    expect(find.text('Remove package/nutrition link'), findsNothing);
  });
}
