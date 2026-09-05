import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/quantity.dart';
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
  String? label,
  bool isReference = false,
}) => NutritionMatch(
  source: FoodSource.usda,
  confidence: 0.95,
  food: aFood(
    name,
    id: 'usda:$name',
    source: FoodSource.usda,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'usda:$name:serving',
        label: label ?? '$amount ${unit.label}',
        amount: Quantity.of(amount, unit),
        macros: const Macros(kcal: 52, proteinG: 0.3, carbG: 14),
        isReference: isReference,
      ),
    ],
  ),
);

Future<HearthDatabase> openMealPicker(
  WidgetTester tester, {
  List<Food> foods = const <Food>[],
  List<Recipe> recipes = const <Recipe>[],
  List<NutritionSource> sources = const <NutritionSource>[],
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    foods: foods,
    recipes: recipes,
    nutritionSources: sources,
  );
  await tester.tap(find.text('Plan').last);
  await pumpFrames(tester);
  await tester.tap(find.byTooltip('Add to breakfast'));
  await pumpFrames(tester);
  return db;
}

/// Types into the picker's search field and waits out the typing pause.
Future<void> searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).last, query);
  await tester.pump(const Duration(milliseconds: 400));
  await pumpFrames(tester);
}

void main() {
  portionTests();

  testWidgets('a modifier is not something the meal picker offers', (
    WidgetTester tester,
  ) async {
    // Freddy's lettuce wrap is −180 kcal. Logged on its own it would make a
    // day read 180 calories lighter than the day that happened, and once
    // that is frozen into a snapshot nothing corrects it (rule 3). It is
    // chosen in the eat-out builder, against something real, or nowhere.
    await openMealPicker(
      tester,
      foods: <Food>[
        aFood('Single Steakburger', id: 'food-burger'),
        aFood(
          'Make any Sandwich a Lettuce Wrap',
          id: 'food-wrap',
          source: FoodSource.restaurant,
        ).asModifier(),
      ],
    );

    await searchFor(tester, 'a');

    expect(find.textContaining('Single Steakburger'), findsOneWidget);
    expect(find.textContaining('Lettuce Wrap'), findsNothing);
  });
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
        _StubSource(<NutritionMatch>[aMatch('Apple, raw', amount: 150)]),
      ],
    );
    await searchFor(tester, 'apple');

    expect(find.textContaining('5.3 oz'), findsOneWidget);
  });

  testWidgets('a per-100 g reference is not dressed up as a serving', (
    WidgetTester tester,
  ) async {
    // Brendan's report: every Oikos yogurt in the list claimed "3.5 oz".
    // None of them said so — that is 100 g in ounces, the figure nutrition is
    // quoted against rather than a pot anybody eats.
    await openMealPicker(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[
          aMatch('Apple, raw', amount: 100, label: '100 g', isReference: true),
        ]),
      ],
    );
    await searchFor(tester, 'apple');

    expect(find.textContaining('100 g'), findsOneWidget);
    expect(find.textContaining('3.5 oz'), findsNothing);
  });

  testWidgets("a serving reads in the packet's own words", (
    WidgetTester tester,
  ) async {
    await openMealPicker(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[
          aMatch('Oikos Strawberry', amount: 150, label: '1 con (150 g)'),
        ]),
      ],
    );
    await searchFor(tester, 'oikos');

    expect(find.textContaining('1 container'), findsOneWidget);
  });
}

/// Typing a portion instead of tapping to it (spec §5.6).
void portionTests() {
  Food yogurt() => aFood(
    'Greek yogurt',
    id: 'food-yogurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'serving-1',
        label: '170 g',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 100, proteinG: 17, carbG: 6),
      ),
    ],
  );

  /// Opens the sheet with the yogurt picked, so the portion row is on screen.
  Future<HearthDatabase> pickYogurt(WidgetTester tester) async {
    final HearthDatabase db = await openMealPicker(
      tester,
      foods: <Food>[yogurt()],
    );
    await tester.tap(find.text('Greek yogurt'));
    await pumpFrames(tester);
    return db;
  }

  Finder portionField() => find.widgetWithText(TextField, '1');

  Future<void> typePortion(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).last, text);
    await pumpFrames(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
  }

  group('the portion', () {
    testWidgets('is a field, not just a number between two buttons', (
      WidgetTester tester,
    ) async {
      await pickYogurt(tester);
      expect(portionField(), findsOneWidget);
    });

    testWidgets('takes a typed number, and the macros follow', (
      WidgetTester tester,
    ) async {
      await pickYogurt(tester);
      await typePortion(tester, '3');

      // 100 kcal a serving, three servings.
      expect(find.textContaining('300 kcal'), findsOneWidget);
    });

    testWidgets('takes a fraction, because a portion is written that way', (
      WidgetTester tester,
    ) async {
      // No numeric pad on iOS carries both "." and "/", which is why the
      // field takes the full keyboard and filters it.
      await pickYogurt(tester);
      await typePortion(tester, '1/2');

      expect(find.textContaining('50 kcal'), findsOneWidget);
    });

    testWidgets('and a decimal', (WidgetTester tester) async {
      await pickYogurt(tester);
      await typePortion(tester, '1.5');

      expect(find.textContaining('150 kcal'), findsOneWidget);
    });

    testWidgets('reads a fraction back the way it would be typed', (
      WidgetTester tester,
    ) async {
      await pickYogurt(tester);
      await typePortion(tester, '1/3');

      // Not 0.3333333333333333, which is neither what was typed nor anything
      // anybody would type over.
      expect(find.widgetWithText(TextField, '1/3'), findsOneWidget);
    });

    testWidgets('reverts rather than logging a number nobody chose', (
      WidgetTester tester,
    ) async {
      await pickYogurt(tester);
      await typePortion(tester, '0');

      expect(portionField(), findsOneWidget);
      expect(find.textContaining('100 kcal'), findsOneWidget);
    });

    testWidgets('an empty field reverts too', (WidgetTester tester) async {
      await pickYogurt(tester);
      await typePortion(tester, '');

      expect(portionField(), findsOneWidget);
    });

    testWidgets('the buttons still work, and the field shows what they did', (
      WidgetTester tester,
    ) async {
      await pickYogurt(tester);
      await tester.tap(find.byTooltip('Larger portion'));
      await pumpFrames(tester);

      expect(find.widgetWithText(TextField, '1 1/4'), findsOneWidget);
      expect(find.textContaining('125 kcal'), findsOneWidget);
    });

    testWidgets('a typed portion is what gets logged', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pickYogurt(tester);
      await typePortion(tester, '2');
      await tester.tap(find.text('Log it'));
      await pumpFrames(tester, frames: 12);

      // Read from the row rather than the day view: the harness feeds the
      // day a fixed list, so a freshly written entry never reaches it.
      final List<MealPlanEntryRow> rows = await db
          .select(db.mealPlanEntries)
          .get();
      expect(rows.single.servings, 2);
      expect(rows.single.isLogged, isTrue);
      // The snapshot is frozen at log time (spec §4), so the doubled portion
      // is in it rather than being recomputed later.
      expect(rows.single.macroSnapshot, contains('200'));
    });
  });
}
