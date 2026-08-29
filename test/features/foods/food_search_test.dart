import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Searching beyond the household's library (spec §5.5).
///
/// Barcodes only reach what still has a packet. §12 names food-data coverage
/// as the biggest threat to the success bar, and loose produce, the deli
/// counter and anything already unwrapped have no barcode to scan.
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
  double confidence = 0.95,
  FoodSource source = FoodSource.usda,
  bool fromLibrary = false,
}) => NutritionMatch(
  source: source,
  confidence: confidence,
  fromLibrary: fromLibrary,
  food: aFood(
    name,
    id: 'usda:$name',
    source: source,
    servingOptions: <ServingOption>[
      aServing(
        id: 'usda:$name:100g',
        amount: 100,
        unit: Units.gram,
        macros: const Macros(kcal: 52, proteinG: 0.3, carbG: 14),
      ),
    ],
  ),
);

Future<void> openFoods(
  WidgetTester tester, {
  List<Food> foods = const <Food>[],
  List<NutritionSource> sources = const <NutritionSource>[],
}) async {
  await pumpHearthApp(tester, foods: foods, nutritionSources: sources);
  await tester.tap(find.text('Foods').last);
  await pumpFrames(tester);
}

/// Types into the library's search field and waits out the typing pause.
Future<void> searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pump(const Duration(milliseconds: 400));
  await pumpFrames(tester);
}

void main() {
  testWidgets('a food nobody has locally is found further afield', (
    WidgetTester tester,
  ) async {
    await openFoods(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );
    await searchFor(tester, 'apple');

    expect(find.text('Elsewhere'), findsOneWidget);
    expect(find.textContaining('Apple, raw'), findsOneWidget);
    expect(find.text('USDA'), findsOneWidget);
  });

  testWidgets('the local list appears without waiting on the network', (
    WidgetTester tester,
  ) async {
    await openFoods(
      tester,
      foods: <Food>[aFood('Apple sauce', id: 'food-sauce')],
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );

    await tester.enterText(find.byType(TextField).first, 'apple');
    await pumpFrames(tester);

    // Before the typing pause has elapsed the household's own food is already
    // on screen: the daily path never pays for the occasional one.
    expect(find.text('Apple sauce'), findsOneWidget);
    expect(find.text('Elsewhere'), findsNothing);
  });

  testWidgets('typing does not fire a request per keystroke', (
    WidgetTester tester,
  ) async {
    final _StubSource source = _StubSource(<NutritionMatch>[
      aMatch('Apple, raw'),
    ]);
    await openFoods(tester, sources: <NutritionSource>[source]);

    for (final String partial in <String>['app', 'appl', 'apple']) {
      await tester.enterText(find.byType(TextField).first, partial);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await pumpFrames(tester);

    expect(source.searches, 1);
  });

  testWidgets('a query too short to mean anything is not sent', (
    WidgetTester tester,
  ) async {
    final _StubSource source = _StubSource(<NutritionMatch>[
      aMatch('Apple, raw'),
    ]);
    await openFoods(tester, sources: <NutritionSource>[source]);
    await searchFor(tester, 'ap');

    expect(source.searches, 0);
  });

  testWidgets('a food the household already has is not offered again', (
    WidgetTester tester,
  ) async {
    await openFoods(
      tester,
      foods: <Food>[aFood('Apple, raw', id: 'food-apple')],
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw', fromLibrary: true)]),
      ],
    );
    await searchFor(tester, 'apple');

    // It is already listed above under the household's own foods; repeating it
    // as a stranger's suggestion invites saving a second copy.
    expect(find.text('Elsewhere'), findsNothing);
    expect(find.byType(FoodCard), findsOneWidget);
  });

  testWidgets('an incomplete entry is flagged in the list, not just on save', (
    WidgetTester tester,
  ) async {
    await openFoods(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw', confidence: 0.3)]),
      ],
    );
    await searchFor(tester, 'apple');

    expect(find.text('incomplete'), findsOneWidget);
    // Never colour alone (§6.3).
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  testWidgets('an empty local list does not claim there is nothing at all', (
    WidgetTester tester,
  ) async {
    await openFoods(
      tester,
      foods: <Food>[aFood('Butter', id: 'food-butter')],
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );
    await searchFor(tester, 'apple');

    // Saying "nothing matches" above a list of results reads as a broken
    // screen; the message is only ever about the household's own foods.
    expect(find.textContaining('None of your foods match'), findsOneWidget);
    expect(find.text('Elsewhere'), findsOneWidget);
  });

  testWidgets('results are dropped when the search box is cleared', (
    WidgetTester tester,
  ) async {
    await openFoods(
      tester,
      sources: <NutritionSource>[
        _StubSource(<NutritionMatch>[aMatch('Apple, raw')]),
      ],
    );
    await searchFor(tester, 'apple');
    expect(find.text('Elsewhere'), findsOneWidget);

    await searchFor(tester, '');

    // The search state is app-wide, so a stale answer must not outlive the
    // question — otherwise another screen inherits someone else's results.
    expect(find.text('Elsewhere'), findsNothing);
  });
}
