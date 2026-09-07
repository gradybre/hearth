import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../foods/label_scan_test.dart' show FakeCamera, FakeLabelReader;

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
  String ingredientLine = '2 tbsp olive oil',
  String ingredientName = 'olive oil',
  LabelReader? labelReader,
}) async {
  await pumpHearthApp(
    tester,
    foods: foods,
    nutritionSources: <NutritionSource>[_StubSource(answers)],
    labelReader: labelReader,
    photoPicker: FakeCamera(),
  );

  await addRecipeVia(tester, 'Write a recipe');
  await pumpFrames(tester);

  // The visible label sits above the field, so the field is found by its hint.
  await tester.enterText(
    find.byWidgetPredicate(
      (Widget w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
    ),
    ingredientLine,
  );
  await pumpFrames(tester);

  await tester.tap(find.text(ingredientName));
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

  testWidgets(
    'a food sharing every word, not a shared phrase, still shows up and ranks first',
    (WidgetTester tester) async {
      // Reported bug: "Maverick Ranch 96/4 Ground Beef" was already saved,
      // but matching a differently-worded ingredient for it didn't show it at
      // all — a plain substring check misses a match when neither string
      // contains the other, even though every meaningful word is shared.
      final Food groundBeef = aFood(
        '96/4 Ground Beef',
        id: 'food-beef',
        brand: 'Maverick Ranch',
      );
      final Food unrelated = aFood('Butter', id: 'food-butter');

      await openIngredientPicker(
        tester,
        foods: <Food>[unrelated, groundBeef],
        ingredientLine: '1 lb lean ground beef',
        ingredientName: 'lean ground beef',
      );

      expect(find.textContaining('96/4 Ground Beef'), findsOneWidget);
      // Genuinely unrelated — no shared words at all — so it drops out
      // rather than cluttering the list with noise.
      expect(find.textContaining('Butter'), findsNothing);
    },
  );

  group('which ingredient needs attention', () {
    // Brendan's report: the summary counted four problem ingredients and
    // nothing in the list said which four — a row that was linked and broken
    // looked exactly like one that was linked and fine.
    Future<void> openEditorWith(
      WidgetTester tester, {
      required String line,
      required List<Food> foods,
      LabelReader? labelReader,
    }) async {
      await openIngredientPicker(
        tester,
        foods: foods,
        ingredientLine: line,
        ingredientName: line.split(' ').skip(2).join(' '),
        labelReader: labelReader,
      );
      // Match the line to the only food on offer, then close the sheet.
      await tester.tap(find.textContaining(foods.first.name).last);
      await pumpFrames(tester, frames: 12);
    }

    testWidgets('a food that cannot convert is flagged, not called unmatched', (
      WidgetTester tester,
    ) async {
      // Half an onion against a food that only knows grams: matched, and
      // still uncountable. The fix is a serving in that unit, not a match.
      await openEditorWith(
        tester,
        line: '1 tbsp white onion',
        foods: <Food>[
          aFood(
            'White onion',
            id: 'food-onion',
            servingOptions: <ServingOption>[
              aServing(
                amount: 100,
                unit: Units.gram,
                macros: const Macros(kcal: 40),
              ),
            ],
          ),
        ],
      );

      // Twice over, and deliberately: the row names the offending
      // ingredient, and the nutrition summary counts it. The whole point is
      // that the two now agree about which lines did not count.
      expect(
        find.textContaining('White onion — no serving in tbsp'),
        findsOneWidget,
      );
      expect(find.textContaining('no serving in'), findsNWidgets(2));
      // Icon and words together, never colour alone (§6.3).
      expect(find.byIcon(Icons.error_outline), findsWidgets);
      expect(find.text('tap to match a food'), findsNothing);
    });

    Future<void> openFixSheet(
      WidgetTester tester, {
      LabelReader? labelReader,
    }) async {
      await openEditorWith(
        tester,
        labelReader: labelReader,
        line: '1 tbsp white onion',
        foods: <Food>[
          aFood(
            'White onion',
            id: 'food-onion',
            servingOptions: <ServingOption>[
              aServing(
                amount: 100,
                unit: Units.gram,
                macros: const Macros(kcal: 40),
              ),
            ],
          ),
        ],
      );
      // The row, not the summary sentence underneath — both mention it.
      await tester.tap(find.textContaining('White onion — no serving in'));
      await tester.pumpAndSettle();
    }

    testWidgets('a flagged row offers every way out, not just one', (
      WidgetTester tester,
    ) async {
      // Going straight to the food editor assumed the food was right and only
      // wanted the unit. It might be the wrong food, or the packet might be
      // in your hand, or the line might not want matching at all.
      await openFixSheet(tester);

      expect(find.textContaining('no serving in tbsp'), findsWidgets);
      expect(find.text('Add a serving in tbsp'), findsOneWidget);
      expect(find.text('Match a different food'), findsOneWidget);
      expect(find.text('Scan the packet instead'), findsOneWidget);
      expect(find.text('Unmatch this line'), findsOneWidget);
    });

    testWidgets('reading the packet is offered above picking another food', (
      WidgetTester tester,
    ) async {
      // The usual reason a line is flagged is not that the match is wrong —
      // it is that the food only knows one unit, and the packet's own panel
      // is the thing that states both.
      await openFixSheet(tester, labelReader: FakeLabelReader());

      expect(find.text("Read the packet's label"), findsOneWidget);
    });

    testWidgets('a build with no backend does not offer to read a label', (
      WidgetTester tester,
    ) async {
      await openFixSheet(tester);
      expect(find.text("Read the packet's label"), findsNothing);
    });

    testWidgets('reading a packet fills that food, keeping what it had', (
      WidgetTester tester,
    ) async {
      await openFixSheet(tester, labelReader: FakeLabelReader());

      await tester.tap(find.text("Read the packet's label"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await pumpFrames(tester, frames: 12);

      // That food's own editor, with the grams it had and the units the label
      // states — and nothing saved until it is (CLAUDE.md rule 4).
      expect(find.text('Edit food'), findsOneWidget);
      // Scrolled to rather than assumed on screen: these are two serving rows
      // in a lazy ListView, so whether both are built at once depends on how
      // tall the form above them happens to be, not on the servings.
      for (final String unit in <String>['g', 'cup']) {
        await tester.scrollUntilVisible(
          find.text(unit),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(unit), findsOneWidget);
      }
    });

    testWidgets('adding a serving goes to that food, not the picker', (
      WidgetTester tester,
    ) async {
      await openFixSheet(tester);

      await tester.tap(find.text('Add a serving in tbsp'));
      await tester.pumpAndSettle();

      expect(find.text('Edit food'), findsOneWidget);
    });

    testWidgets('matching a different food opens the picker', (
      WidgetTester tester,
    ) async {
      await openFixSheet(tester);

      await tester.tap(find.text('Match a different food'));
      await tester.pumpAndSettle();

      expect(find.text('Match "white onion"'), findsOneWidget);
    });

    testWidgets('unmatching detaches the food and says so', (
      WidgetTester tester,
    ) async {
      await openFixSheet(tester);

      await tester.tap(find.text('Unmatch this line'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('tap to match a food'), findsWidgets);
      expect(find.textContaining('no serving in'), findsNothing);
    });

    testWidgets('a healthy match shows the food, with no warning', (
      WidgetTester tester,
    ) async {
      await openEditorWith(
        tester,
        line: '2 tbsp olive oil',
        foods: <Food>[oliveOil()],
      );

      expect(find.textContaining('no serving in'), findsNothing);
      expect(find.byIcon(Icons.link), findsWidgets);
    });

    testWidgets('an unmatched line still says so plainly', (
      WidgetTester tester,
    ) async {
      await openIngredientPicker(
        tester,
        foods: <Food>[aFood('Butter', id: 'food-butter')],
      );
      // Leave it unmatched: close the sheet without choosing anything.
      await tester.tap(find.text('Match "olive oil"'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('tap to match a food'), findsWidgets);
      expect(find.textContaining('no serving in'), findsNothing);
    });
  });
}
