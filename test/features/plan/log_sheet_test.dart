import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Logging something the household has never saved (spec §5.5, §5.6).
///
/// The meal picker used to reach only the library, so anything not already in
/// it meant leaving the meal, adding the food from the Foods tab, coming back
/// and picking the day up again. §12 names food-data coverage as the biggest
/// threat to the success bar, and a dead end at the moment of logging is
/// exactly how that threat lands.
class _StubSource implements NutritionSource {
  _StubSource(this.results);

  final List<NutritionMatch> results;
  int searches = 0;

  @override
  String get displayName => 'Stub';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async => null;

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    searches++;
    return results;
  }
}

NutritionMatch aMatch(
  String name, {
  double amount = 100,
  Unit unit = Units.gram,
}) => NutritionMatch(
  source: FoodSource.usda,
  confidence: 0.95,
  food: aFood(
    name,
    id: 'usda:$name',
    source: FoodSource.usda,
    servingOptions: <ServingOption>[
      aServing(
        id: 'usda:$name:serving',
        amount: amount,
        unit: unit,
        macros: const Macros(kcal: 52, proteinG: 0.3, carbG: 14),
      ),
    ],
  ),
);

Future<void> openMealPicker(
  WidgetTester tester, {
  List<Food> foods = const <Food>[],
  List<Recipe> recipes = const <Recipe>[],
  List<NutritionSource> sources = const <NutritionSource>[],
}) async {
  await pumpHearthApp(
    tester,
    foods: foods,
    recipes: recipes,
    nutritionSources: sources,
  );
  await tester.tap(find.text('Plan').last);
  await pumpFrames(tester);
  await tester.tap(find.byTooltip('Add to breakfast'));
  await pumpFrames(tester);
}

/// Types into the picker's search field and waits out the typing pause.
Future<void> searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).last, query);
  await tester.pump(const Duration(milliseconds: 400));
  await pumpFrames(tester);
}

void main() {
  testWidgets('the meal picker reaches beyond the library', (
    WidgetTester tester,
  ) async {
    await openMealPicker(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );
    await searchFor(tester, 'apple');

    expect(find.text('Elsewhere'), findsOneWidget);
    expect(find.textContaining('Apple, raw'), findsOneWidget);
  });

  testWidgets('an empty library is no longer a dead end', (
    WidgetTester tester,
  ) async {
    await openMealPicker(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );

    // Before anything is typed the sheet says where a food can come from,
    // rather than sending the user off to another tab.
    expect(find.textContaining('added straight from here'), findsOneWidget);
  });

  testWidgets("saying nothing matches is only ever about the household's own", (
    WidgetTester tester,
  ) async {
    await openMealPicker(
      tester,
      foods: <Food>[aFood('Butter', id: 'food-butter')],
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );
    await searchFor(tester, 'apple');

    expect(
      find.textContaining('None of your recipes or foods match'),
      findsOneWidget,
    );
    expect(find.text('Elsewhere'), findsOneWidget);
  });

  testWidgets('the local list appears without waiting on the network', (
    WidgetTester tester,
  ) async {
    await openMealPicker(
      tester,
      foods: <Food>[aFood('Apple sauce', id: 'food-sauce')],
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );

    await tester.enterText(find.byType(TextField).last, 'apple');
    await pumpFrames(tester);

    expect(find.text('Apple sauce'), findsOneWidget);
    expect(find.text('Elsewhere'), findsNothing);
  });

  testWidgets('a query too short to mean anything is not sent', (
    WidgetTester tester,
  ) async {
    final _StubSource source = _StubSource(<NutritionMatch>[
      aMatch('Apple, raw'),
    ]);
    await openMealPicker(tester, sources: <NutritionSource>[source]);
    await searchFor(tester, 'ap');

    expect(source.searches, 0);
  });

  testWidgets('a found food is reviewed and saved before it reaches the day', (
    WidgetTester tester,
  ) async {
    await openMealPicker(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );
    await searchFor(tester, 'apple');
    await tester.tap(find.textContaining('Apple, raw'));
    await pumpFrames(tester);

    // CLAUDE.md rule 4: nothing automated writes to the library unseen.
    expect(find.text('New food'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 10);

    // Back in the sheet, with the food picked and the day one tap away.
    expect(find.text('Apple, raw'), findsOneWidget);
    expect(find.text('Log it'), findsOneWidget);
  });

  testWidgets('a serving is shown in the measure the box states', (
    WidgetTester tester,
  ) async {
    await openMealPicker(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[
          aMatch('Cheddar', amount: 0.25, unit: Units.cup),
        ]),
      ],
    );
    await searchFor(tester, 'cheddar');

    expect(find.textContaining('¼ cup'), findsOneWidget);
  });

  testWidgets('a serving with only a metric weight is shown in imperial', (
    WidgetTester tester,
  ) async {
    // Every source reports metrically whatever the packet says, so the list
    // used to read as an unbroken column of grams.
    await openMealPicker(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );
    await searchFor(tester, 'apple');

    expect(find.textContaining('3.5 oz'), findsOneWidget);
    expect(find.textContaining('100 g'), findsNothing);
  });
}
