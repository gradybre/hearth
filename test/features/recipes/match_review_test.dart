import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The match review screen (spec §5.3's workhorse UI).
///
/// Everything here is a stranger's data until the user says otherwise, so the
/// screen's job is to make each proposal checkable: which food, from where, at
/// what serving, working out to what.
class StubSource implements NutritionSource {
  StubSource(this.byQuery);

  final Map<String, List<NutritionMatch>> byQuery;
  final List<String> queries = <String>[];

  @override
  String get displayName => 'Stub';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async => null;

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    queries.add(query);
    return byQuery[query] ?? const <NutritionMatch>[];
  }
}

NutritionMatch usda(String name, {String? brand, double kcal = 884}) =>
    NutritionMatch(
      source: FoodSource.usda,
      confidence: 0.9,
      food: aFood(
        name,
        id: 'usda:$name:${brand ?? ''}',
        brand: brand,
        source: FoodSource.usda,
        servingOptions: <ServingOption>[
          aServing(
            id: 'usda:$name:${brand ?? ''}:100g',
            amount: 100,
            unit: Units.gram,
            macros: Macros(kcal: kcal, proteinG: 1),
          ),
        ],
      ),
    );

Future<StubSource> openEditorWith(
  WidgetTester tester,
  String ingredients, {
  Map<String, List<NutritionMatch>> answers =
      const <String, List<NutritionMatch>>{},
}) async {
  final StubSource source = StubSource(answers);
  await pumpHearthApp(tester, nutritionSources: <NutritionSource>[source]);

  await tester.tap(find.text('New recipe'));
  await pumpFrames(tester);
  await tester.enterText(
    find.byWidgetPredicate(
      (Widget w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
    ),
    ingredients,
  );
  await pumpFrames(tester);
  return source;
}

void main() {
  testWidgets('the editor offers to look up what it could not match', (
    WidgetTester tester,
  ) async {
    await openEditorWith(tester, '2 tbsp olive oil\n200 g cheddar cheese');

    expect(find.text('Find nutrition for 2 ingredients'), findsOneWidget);
  });

  testWidgets('an optional line is not counted as a gap to fill', (
    WidgetTester tester,
  ) async {
    // Salt to taste is excluded from macros on purpose (§5.2), so there is
    // nothing to go looking for.
    await openEditorWith(tester, '2 tbsp olive oil\nsalt to taste');

    expect(find.text('Find nutrition for 1 ingredient'), findsOneWidget);
  });

  testWidgets('nothing is searched until the user asks', (
    WidgetTester tester,
  ) async {
    final StubSource source = await openEditorWith(tester, '2 tbsp olive oil');

    // A dozen searches fired while someone is still typing is work nobody
    // asked for, against services free to rate-limit us.
    expect(source.queries, isEmpty);
  });

  testWidgets('each row shows the food, its source, and what it works out to', (
    WidgetTester tester,
  ) async {
    await openEditorWith(
      tester,
      '100 g olive oil',
      answers: <String, List<NutritionMatch>>{
        'olive oil': <NutritionMatch>[usda('Olive oil')],
      },
    );

    await tester.tap(find.text('Find nutrition for 1 ingredient'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Matches'), findsOneWidget);
    expect(find.textContaining('Olive oil'), findsWidgets);
    expect(find.textContaining('USDA'), findsOneWidget);
    // The number is the point: a plausible name on the wrong serving is
    // exactly what this screen exists to catch.
    expect(find.textContaining('884 kcal'), findsOneWidget);
  });

  testWidgets('a toss-up is left unticked rather than quietly adopted', (
    WidgetTester tester,
  ) async {
    await openEditorWith(
      tester,
      '200 g cheddar cheese',
      answers: <String, List<NutritionMatch>>{
        // Same name, wildly different energy: a toss-up whose answer
        // actually changes the recipe's numbers.
        'cheddar cheese': <NutritionMatch>[
          usda('CHEDDAR CHEESE', brand: 'Full fat', kcal: 400),
          usda('CHEDDAR CHEESE', brand: 'Reduced fat', kcal: 280),
        ],
      },
    );

    await tester.tap(find.text('Find nutrition for 1 ingredient'));
    await pumpFrames(tester, frames: 20);

    expect(find.textContaining('Several fit equally well'), findsOneWidget);
    // Opt in to a guess the app has already said it is unsure of, rather than
    // having to notice and opt out.
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsNothing);
  });

  testWidgets('an ingredient nothing was found for does not block anything', (
    WidgetTester tester,
  ) async {
    await openEditorWith(tester, '1 pinch of asafoetida');

    await tester.tap(find.text('Find nutrition for 1 ingredient'));
    await pumpFrames(tester, frames: 20);

    // §5.3: missing data never blocks. It is a row that says so, not an error.
    expect(
      find.text('Nothing found. Match it yourself, or leave it.'),
      findsOneWidget,
    );
    expect(find.text('Use these'), findsOneWidget);
  });

  testWidgets('accepted matches come back and attach to the line', (
    WidgetTester tester,
  ) async {
    await openEditorWith(
      tester,
      '100 g olive oil',
      answers: <String, List<NutritionMatch>>{
        'olive oil': <NutritionMatch>[usda('Olive oil')],
      },
    );

    await tester.tap(find.text('Find nutrition for 1 ingredient'));
    await pumpFrames(tester, frames: 20);
    await tester.tap(find.text('Use these'));
    await pumpFrames(tester, frames: 20);

    // Back in the editor, matched — and with nothing left to look up.
    expect(find.text('Matches'), findsNothing);
    expect(find.textContaining('Find nutrition'), findsNothing);
  });
}
