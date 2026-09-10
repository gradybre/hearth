import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_scope.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// One way in, and whose foods you are looking at (review §6.2.6, §7.5).
///
/// Two defects in one screen. The corner of it carried three or four floating
/// buttons, two of which said what they did only in a tooltip — a hover, on a
/// device with no pointer. And a seeded chain drops hundreds of menu rows into
/// the same list as the twenty foods somebody actually eats, on the screen
/// they open to log from.

Food yogurt() => aFood(
  'Greek yogurt',
  id: 'food-yogurt',
  servingOptions: <ServingOption>[
    aServing(
      id: 's1',
      amount: 170,
      unit: Units.gram,
      macros: const Macros(kcal: 100, proteinG: 17, carbG: 6),
    ),
  ],
);

/// One row off a seeded chain's menu — the thing that crowds out the twenty
/// foods above.
Food harvestBowl() => aFood(
  'Harvest Bowl',
  id: 'food-chopt-harvest',
  brand: 'Chopt',
  source: FoodSource.restaurant,
  menuGroup: 'Warm bowls',
  menuOrder: 1,
  servingOptions: <ServingOption>[
    aServing(
      id: 's-bowl',
      amount: 1,
      unit: Units.item,
      macros: const Macros(kcal: 690, proteinG: 26, carbG: 78, fatG: 30),
    ),
  ],
);

/// A label reader that answers without a backend, so the third way in can be
/// walked end to end.
class _FakeLabelReader implements LabelReader {
  @override
  Future<LabelReading> read(List<AiImage> images) async => const LabelReading(
    name: 'Shredded Sharp Cheddar Cheese',
    brand: 'Kirkland Signature',
    uncertain: <AiUncertainty>[],
    servings: <LabelServing>[
      LabelServing(
        amount: 1,
        unitId: 'oz',
        kcal: 110,
        proteinG: 7,
        carbG: 1,
        fatG: 9,
      ),
    ],
  );
}

class _FakeCamera implements PhotoPicker {
  @override
  bool get canUseCamera => true;

  static final Uint8List _onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async =>
      PickedPhoto(bytes: _onePixelPng, extension: 'png');

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => <PickedPhoto>[
    (await pick(PhotoOrigin.library))!,
  ];
}

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

NutritionMatch aMatch(String name) => NutritionMatch(
  source: FoodSource.usda,
  confidence: 0.95,
  fromLibrary: false,
  food: aFood(
    name,
    id: 'usda:$name',
    source: FoodSource.usda,
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

Future<HearthDatabase> openFoods(
  WidgetTester tester, {
  List<Food> foods = const <Food>[],
  List<NutritionSource> sources = const <NutritionSource>[],
  LabelReader? labelReader,
  PhotoPicker? photoPicker,
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    foods: foods,
    nutritionSources: sources,
    labelReader: labelReader,
    photoPicker: photoPicker,
  );
  await tester.tap(find.text('Foods').last);
  await pumpFrames(tester);
  return db;
}

/// Opens the one way in.
Future<void> openAddFood(WidgetTester tester) async {
  await tester.tap(find.text('Add food'));
  await pumpFrames(tester);
}

Future<void> chooseScope(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await pumpFrames(tester);
  await tester.tap(find.text(label));
  await pumpFrames(tester);
}

Future<void> searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pump(const Duration(milliseconds: 400));
  await pumpFrames(tester);
}

/// Fills the blank editor in and saves, the shortest food there is.
Future<void> saveFoodNamed(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField).first, name);
  await pumpFrames(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await pumpFrames(tester, frames: 20);
}

/// Turns the blank editor's food into a restaurant's, which needs a name for
/// the restaurant as well — one with none refuses to save.
Future<void> makeItARestaurants(WidgetTester tester, String restaurant) async {
  final Finder toggle = find.widgetWithText(
    SwitchListTile,
    'From a restaurant',
  );
  await tester.scrollUntilVisible(
    toggle,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(toggle);
  await pumpFrames(tester);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
  await pumpFrames(tester);
  await tester.enterText(find.byType(TextField).at(1), restaurant);
  await pumpFrames(tester);
}

void main() {
  group('one way in (review §6.2.6)', () {
    testWidgets('the screen carries exactly one floating action', (
      WidgetTester tester,
    ) async {
      // The defect: a bare +, an obscure seasoning icon, and Scan, stacked up
      // the corner — and a fourth when label reading is configured.
      await openFoods(
        tester,
        foods: <Food>[yogurt()],
        labelReader: _FakeLabelReader(),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('and it says what it does in words, not in a tooltip', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);

      // A visible label, matching Recipes' Add recipe. A tooltip is a hover,
      // and a phone has no pointer to hover with (spec §6.3).
      expect(find.text('Add food'), findsOneWidget);
    });

    testWidgets('it opens the three ways a food gets in', (
      WidgetTester tester,
    ) async {
      await openFoods(
        tester,
        foods: <Food>[yogurt()],
        labelReader: _FakeLabelReader(),
      );
      await openAddFood(tester);

      expect(find.text('Scan a barcode'), findsOneWidget);
      expect(find.text('Read a label'), findsOneWidget);
      expect(find.text('Enter it by hand'), findsOneWidget);
    });

    testWidgets('by hand still reaches a blank editor', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);
      await openAddFood(tester);
      await tester.tap(find.text('Enter it by hand'));
      await pumpFrames(tester);

      expect(find.text('New food'), findsOneWidget);
    });

    testWidgets('a barcode still reaches the scanner', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);
      await openAddFood(tester);
      await tester.tap(find.text('Scan a barcode'));
      await pumpFrames(tester);

      expect(find.text('Type the number'), findsOneWidget);
      expect(find.text('Add food'), findsNothing);
    });

    testWidgets('a label photograph still fills the editor in', (
      WidgetTester tester,
    ) async {
      await openFoods(
        tester,
        foods: <Food>[yogurt()],
        labelReader: _FakeLabelReader(),
        photoPicker: _FakeCamera(),
      );
      await openAddFood(tester);
      await tester.tap(find.text('Read a label'));
      await pumpFrames(tester);
      await tester.tap(find.text('Take a photo'));
      await pumpFrames(tester, frames: 10);

      // Straight to the editor, filled in and unsaved (CLAUDE.md rule 4).
      expect(find.text('New food'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Shredded Sharp Cheddar Cheese'),
        findsOneWidget,
      );
    });

    testWidgets('a build with no label reader does not offer that way', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);
      await openAddFood(tester);

      expect(find.text('Read a label'), findsNothing);
      expect(find.text('Scan a barcode'), findsOneWidget);
    });

    testWidgets('seasonings maintenance is behind a labelled menu', (
      WidgetTester tester,
    ) async {
      // §7.5: maintenance moves to a labelled overflow, and stops being an
      // unexplained icon in the corner.
      await openFoods(tester, foods: <Food>[yogurt()]);
      await tester.tap(find.byIcon(Icons.more_vert));
      await pumpFrames(tester);

      await tester.tap(find.text('Seasonings that need no match'));
      await pumpFrames(tester);

      expect(find.text('Known to Hearth'), findsOneWidget);
    });

    testWidgets('and that menu survives a small phone at 3x', (
      WidgetTester tester,
    ) async {
      // A popup menu is neither a sheet nor a dialog, so the surface guard
      // cannot ask for it and the flow sweep cannot list it — its own file
      // no longer opens either, and the sweep's staleness check would fail
      // on the entry. So the case lives here instead of going uncovered.
      await pumpHearthApp(
        tester,
        foods: <Food>[yogurt()],
        size: const Size(320, 568),
        textScale: 3,
      );
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Seasonings that need no match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('whose foods (review §7.5)', () {
    testWidgets('opens on the household\'s own foods', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), harvestBowl()]);

      expect(find.text('Greek yogurt'), findsOneWidget);
      expect(
        find.textContaining('Harvest Bowl'),
        findsNothing,
        reason: 'a seeded chain must not crowd the foods somebody eats',
      );
    });

    testWidgets('and says so, so nothing looks lost', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), harvestBowl()]);

      expect(find.text('Your foods'), findsOneWidget);
      expect(find.text('Restaurant menus'), findsOneWidget);
    });

    testWidgets('the menus are one tap away, not hidden', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), harvestBowl()]);
      await chooseScope(tester, 'Restaurant menus');

      expect(find.textContaining('Harvest Bowl'), findsOneWidget);
      expect(find.text('Greek yogurt'), findsNothing);
    });

    testWidgets('the choice survives leaving the screen and coming back', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), harvestBowl()]);
      await chooseScope(tester, 'Restaurant menus');

      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);

      expect(find.textContaining('Harvest Bowl'), findsOneWidget);
      expect(find.text('Greek yogurt'), findsNothing);
    });

    testWidgets('and is written to this device, not to the household', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openFoods(
        tester,
        foods: <Food>[yogurt(), harvestBowl()],
      );
      await chooseScope(tester, 'Restaurant menus');

      expect(
        await PreferenceStore(db).read(PreferenceStore.foodScope),
        FoodScope.restaurants.stored,
        reason: 'the scope was not remembered on this device',
      );
    });

    test('a stored scope is read back, not just written', () async {
      // The half a widget test cannot see: replacing the read with a bare
      // default leaves every round trip above green, because the notifier
      // keeps its state in memory for the life of the app.
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      await PreferenceStore(db)
          .write(PreferenceStore.foodScope, FoodScope.restaurants.stored);

      final ProviderContainer container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(foodScopeProvider.future),
        FoodScope.restaurants,
      );
    });

    testWidgets('an empty restaurant scope explains itself', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);
      await chooseScope(tester, 'Restaurant menus');

      expect(find.text('No restaurant menus yet'), findsOneWidget);
    });

    testWidgets('search still reaches outward from your own foods', (
      WidgetTester tester,
    ) async {
      final _StubSource source = _StubSource(<NutritionMatch>[
        aMatch('Apple, raw'),
      ]);
      await openFoods(
        tester,
        foods: <Food>[yogurt(), harvestBowl()],
        sources: <NutritionSource>[source],
      );
      await searchFor(tester, 'apple');

      expect(find.text('Elsewhere'), findsOneWidget);
      expect(find.textContaining('Apple, raw'), findsOneWidget);
    });

    testWidgets('and from the restaurant menus too', (
      WidgetTester tester,
    ) async {
      // The scope narrows the household's own list. It has no business
      // switching off Open Food Facts and USDA (spec §5.5).
      final _StubSource source = _StubSource(<NutritionMatch>[
        aMatch('Apple, raw'),
      ]);
      await openFoods(
        tester,
        foods: <Food>[yogurt(), harvestBowl()],
        sources: <NutritionSource>[source],
      );
      await chooseScope(tester, 'Restaurant menus');
      await searchFor(tester, 'apple');

      expect(find.text('Elsewhere'), findsOneWidget);
      expect(find.textContaining('Apple, raw'), findsOneWidget);
    });
  });

  group('a saved food lands where you can see it', () {
    // What is asserted here is the *list moving*, not the new food appearing
    // in it: `pumpHearthApp` feeds the library from a fixed stream override,
    // so nothing saved through the app can ever show up in a widget test.
    // The switch changing scope is the visible half of the same behaviour,
    // and it is the half that answers "where did my food go".

    testWidgets('one entered from the menus scope does not vanish', (
      WidgetTester tester,
    ) async {
      // The screen already knows this failure: `_NoMatches` dropped its "Add
      // it as a new food" button in this scope precisely because the food
      // "would vanish on the spot". The floating button is the same door, and
      // it is the one people use.
      await openFoods(tester, foods: <Food>[yogurt(), harvestBowl()]);
      await chooseScope(tester, 'Restaurant menus');
      expect(find.textContaining('Harvest Bowl'), findsOneWidget);

      await openAddFood(tester);
      await tester.tap(find.text('Enter it by hand'));
      await pumpFrames(tester);
      await saveFoodNamed(tester, 'Deli turkey');

      expect(
        find.text('Greek yogurt'),
        findsOneWidget,
        reason: 'the food was saved into the half of the library not showing',
      );
      expect(find.textContaining('Harvest Bowl'), findsNothing);
    });

    testWidgets('and nor does a restaurant one entered from your own', (
      WidgetTester tester,
    ) async {
      // The mirror, and reachable without touching the scope at all: the
      // editor's own "From a restaurant" switch moves the food across the
      // divide while you are standing on the other side of it.
      await openFoods(tester, foods: <Food>[yogurt(), harvestBowl()]);
      expect(find.text('Greek yogurt'), findsOneWidget);

      await openAddFood(tester);
      await tester.tap(find.text('Enter it by hand'));
      await pumpFrames(tester);
      await tester.enterText(find.byType(TextField).first, 'Burrito bowl');
      await pumpFrames(tester);
      await makeItARestaurants(tester, 'Cava');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester, frames: 20);

      expect(find.textContaining('Harvest Bowl'), findsOneWidget);
      expect(find.text('Greek yogurt'), findsNothing);
    });

    testWidgets('and a food saved into the scope you are in leaves it alone', (
      WidgetTester tester,
    ) async {
      // The common case, and the one a switch that always moved would break.
      await openFoods(tester, foods: <Food>[yogurt(), harvestBowl()]);

      await openAddFood(tester);
      await tester.tap(find.text('Enter it by hand'));
      await pumpFrames(tester);
      await saveFoodNamed(tester, 'Deli turkey');

      expect(find.text('Greek yogurt'), findsOneWidget);
      expect(find.textContaining('Harvest Bowl'), findsNothing);
    });
  });
}
