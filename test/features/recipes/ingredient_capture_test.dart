import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// In-recipe barcode capture (spec §5.5, §10 phase 2).
///
/// The packet is usually in your hand while you write the recipe. Before this,
/// matching it meant leaving for the Foods tab, adding the food there, and
/// coming back to the ingredient — three screens to say "this oil is that
/// bottle".
class _StubSource implements NutritionSource {
  _StubSource(this.answers);

  final Map<String, NutritionMatch> answers;

  @override
  String get displayName => 'Stub';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async => answers[barcode];

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async =>
      const <NutritionMatch>[];
}

Food oliveOil({String id = 'food-oil'}) => aFood(
  'Olive oil',
  id: id,
  brand: 'Filippo Berio',
  barcode: '8002210111110',
  servingOptions: <ServingOption>[
    aServing(
      id: '$id-s1',
      amount: 15,
      unit: Units.millilitre,
      macros: const Macros(kcal: 120, fatG: 14),
    ),
  ],
);

Future<void> openIngredientPicker(
  WidgetTester tester, {
  List<Food> foods = const <Food>[],
  Map<String, NutritionMatch> answers = const <String, NutritionMatch>{},
}) async {
  await pumpHearthApp(
    tester,
    foods: foods,
    nutritionSources: <NutritionSource>[_StubSource(answers)],
  );

  await tester.tap(find.text('New recipe'));
  await pumpFrames(tester);

  // The visible label sits above the field, so the field is found by its hint.
  await tester.enterText(
    find.byWidgetPredicate(
      (Widget w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
    ),
    '2 tbsp olive oil',
  );
  await pumpFrames(tester);

  await tester.tap(find.text('olive oil'));
  await pumpFrames(tester);
}

void main() {
  testWidgets('an ingredient offers scanning instead of a trip to Foods', (
    WidgetTester tester,
  ) async {
    // A library that has foods, none of which is olive oil.
    await openIngredientPicker(
      tester,
      foods: <Food>[aFood('Butter', id: 'food-butter')],
    );

    expect(find.text('Match "olive oil"'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsWidgets);
    // The old copy sent the user away to add the food and come back. The
    // packet is already in their hand.
    expect(find.textContaining('come back and match it'), findsNothing);
    // And the message is about the library, not about the world — results
    // from Open Food Facts and USDA may be listed right underneath it.
    expect(find.textContaining('None of your foods match'), findsOneWidget);
  });

  testWidgets('scanning a food already in the library matches the line', (
    WidgetTester tester,
  ) async {
    await openIngredientPicker(
      tester,
      foods: <Food>[oliveOil()],
      answers: <String, NutritionMatch>{
        '8002210111110': NutritionMatch(
          food: oliveOil(),
          source: FoodSource.manual,
          confidence: 1,
          fromLibrary: true,
        ),
      },
    );

    await tester.tap(find.byIcon(Icons.qr_code_scanner).last);
    await pumpFrames(tester);

    await tester.enterText(find.byType(TextField).last, '8002210111110');
    await tester.tap(find.text('Look it up'));
    await pumpFrames(tester);

    // A food the household already vouched for needs no review — it has an id
    // and the numbers are already theirs.
    expect(find.text('Use it'), findsOneWidget);

    await tester.tap(find.text('Use it'));
    await pumpFrames(tester, frames: 12);

    // Back on the recipe, with the line matched.
    expect(find.text('Match "olive oil"'), findsNothing);
    expect(find.textContaining('Olive oil'), findsWidgets);
  });

  testWidgets('a matched food can be edited in place, not just replaced', (
    WidgetTester tester,
  ) async {
    // Reported bug: reopening the picker on an already-matched ingredient
    // only offered a different food to switch to — no way to fix something
    // wrong with the food already there without abandoning the match.
    await openIngredientPicker(tester, foods: <Food>[oliveOil()]);

    // Select the library food as this line's match.
    await tester.tap(find.textContaining('Olive oil'));
    await pumpFrames(tester);

    // Reopen the picker on the now-matched line.
    await tester.tap(find.text('olive oil'));
    await pumpFrames(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await pumpFrames(tester);

    expect(find.text('Edit food'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Olive oil',
    );
  });

  testWidgets('a food not yet known is checked before it is used', (
    WidgetTester tester,
  ) async {
    await openIngredientPicker(
      tester,
      answers: <String, NutritionMatch>{
        '8002210111110': NutritionMatch(
          food: oliveOil(id: 'off:8002210111110'),
          source: FoodSource.openFoodFacts,
          confidence: 0.9,
        ),
      },
    );

    await tester.tap(find.byIcon(Icons.qr_code_scanner).last);
    await pumpFrames(tester);

    await tester.enterText(find.byType(TextField).last, '8002210111110');
    await tester.tap(find.text('Look it up'));
    await pumpFrames(tester);

    // Still a review before anything is written, even mid-recipe: the
    // shortcut is to the scanner, not past the check (CLAUDE.md rule 4).
    expect(find.text('Check and use'), findsOneWidget);
    expect(find.text('Use it'), findsNothing);
  });
}
