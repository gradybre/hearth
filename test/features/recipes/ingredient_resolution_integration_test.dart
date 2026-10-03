import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/auth/local_auth_gateway.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/ingredient_match_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/foods/ingredient_food_capture.dart';
import 'package:hearth/features/foods/label_scan_controller.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../foods/label_scan_test.dart' show FakeCamera, FakeLabelReader;
import 'match_review_test.dart' show usda;

/// These journeys use HearthApp's production router and real repositories.
/// Only outward nutrition/photo/label adapters and library streams are fake.
/// A bespoke capture router would hide a dropped extra or return value here.
class _Source implements NutritionSource {
  _Source({this.answers = const {}});

  Map<String, List<NutritionMatch>> answers;
  final List<String> searches = [];
  final List<String> scans = [];

  @override
  String get displayName => 'Synthetic nutrition';

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    searches.add(query);
    return answers[query] ?? const [];
  }

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async {
    scans.add(barcode);
    return null;
  }
}

final _household = LocalAuthGateway.account.householdId;

Finder _action(int row, String action) => find.byKey(Key('match-$row-$action'));

Finder get _ingredientField => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      (widget.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
);

Finder get _foodName => find.widgetWithText(TextField, 'Greek yogurt');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await pumpFrames(tester, frames: 20);
}

void _expectContext(WidgetTester tester, String authoredLine) {
  expect(find.byType(IngredientFoodBanner), findsOneWidget);
  expect(
    tester
        .widget<IngredientFoodBanner>(find.byType(IngredientFoodBanner))
        .capture
        .authoredLine,
    authoredLine,
  );
  expect(
    find.descendant(
      of: find.byType(IngredientFoodBanner),
      matching: find.text(authoredLine),
    ),
    findsOneWidget,
  );
}

String _textIn(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

Future<HearthDatabase> _openEditor(
  WidgetTester tester, {
  required String lines,
  _Source? source,
  List<Food> foods = const [],
  FakeLabelReader? reader,
}) async {
  final db = await pumpHearthApp(
    tester,
    foods: foods,
    nutritionSources: [source ?? _Source()],
    labelReader: reader,
    photoPicker: FakeCamera(),
  );
  await addRecipeVia(tester, 'Write a recipe');
  await pumpFrames(tester, frames: 20);
  await tester.enterText(
    find.widgetWithText(TextField, 'Braised short ribs'),
    'Ingredient integration supper',
  );
  await tester.enterText(_ingredientField, lines);
  await pumpFrames(tester, frames: 20);
  return db;
}

Future<void> _review(WidgetTester tester) =>
    _tap(tester, find.textContaining('Find nutrition for'));

Future<List<Food>> _foods(HearthDatabase db) =>
    FoodStore(db).all(householdId: _household);

Future<Map<String, String>> _remembered(HearthDatabase db) =>
    IngredientMatchStore(db).allFor(_household);

Future<Recipe> _saveRecipe(WidgetTester tester, HearthDatabase db) async {
  await _tap(tester, find.text('Save'));
  return (await RecipeStore(db).all(householdId: _household)).single;
}

Future<HearthDatabase> _openFlaggedIngredient(
  WidgetTester tester, {
  FakeLabelReader? reader,
}) async {
  final db = await _openEditor(
    tester,
    lines: '2 tbsp white onion, finely chopped',
    foods: [
      aFoodPer100g(
        'White onion',
        id: 'onion',
        kcal: 40,
      ).withHousehold(_household),
    ],
    reader: reader,
  );
  await _tap(tester, find.text('white onion, finely chopped'));
  await _tap(tester, find.text('White onion'));
  await _tap(tester, find.text('white onion, finely chopped'));
  expect(find.text('Add a serving in tbsp'), findsOneWidget);
  return db;
}

void main() {
  testWidgets('review includes the same wording across recipe sections', (
    tester,
  ) async {
    final db = await _openEditor(tester, lines: '100 g olive oil, divided');
    await _tap(tester, find.text('Add a section'));
    await tester.enterText(
      _ingredientField.last,
      '2 tbsp olive oil, for sauce',
    );
    await pumpFrames(tester, frames: 20);
    await _tap(tester, find.textContaining('Find nutrition for').last);
    expect(find.text('Applies to 2 recipe lines'), findsOneWidget);
    expect(find.text('100 g olive oil, divided'), findsOneWidget);
    expect(find.text('2 tbsp olive oil, for sauce'), findsOneWidget);
    await _tap(tester, _action(0, 'manual'));
    final banner = tester.widget<IngredientFoodBanner>(
      find.byType(IngredientFoodBanner),
    );
    expect(banner.capture.recipeLineCount, 2);
    expect(banner.capture.authoredLine, contains('100 g olive oil, divided'));
    expect(
      banner.capture.authoredLine,
      contains('2 tbsp olive oil, for sauce'),
    );
    await _tap(tester, find.text('Save'));
    await _tap(tester, find.byKey(const Key('match-review-apply')));
    final saved = await _saveRecipe(tester, db);
    final food = (await _foods(db)).single;
    expect(saved.sections, hasLength(2));
    expect(saved.allIngredients.map((line) => line.foodId), [food.id, food.id]);
    expect(await _remembered(db), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flagged ingredient repair choices remain reachable at 3x', (
    tester,
  ) async {
    await _openFlaggedIngredient(tester, reader: FakeLabelReader());
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    await pumpFrames(tester, frames: 12);
    expect(tester.takeException(), isNull);
    for (final String choice in <String>[
      'Add a serving in tbsp',
      "Read the packet's label",
      'Match a different food',
      'Scan the packet instead',
      'Unmatch this line',
      "Nothing to match — it's a seasoning",
    ]) {
      await tester.ensureVisible(find.text(choice));
      await pumpFrames(tester, frames: 4);
      expect(find.text(choice).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'applying reviewed matches with unchecked remembering creates no household rules',
    (tester) async {
      final db = await _openEditor(
        tester,
        lines: '100 g olive oil\n200 g cottage cheese',
        source: _Source(
          answers: {
            'olive oil': [usda('Olive oil')],
            'cottage cheese': [usda('Cottage cheese', kcal: 98)],
          },
        ),
      );
      await _review(tester);
      expect(find.text('2 of 2 resolved'), findsOneWidget);
      expect(await _remembered(db), isEmpty);
      await _tap(tester, find.byKey(const Key('match-review-apply')));
      expect(find.text('Matches'), findsNothing);
      final saved = await _saveRecipe(tester, db);
      expect(
        saved.allIngredients.map((line) => line.foodId),
        everyElement(isNotNull),
      );
      expect(await _foods(db), hasLength(2));
      expect(
        await _remembered(db),
        isEmpty,
        reason: 'Using reviewed nutrition for this recipe must not opt the household into remembering.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual capture returns to the same review and only checked wording is remembered',
    (tester) async {
      final db = await _openEditor(
        tester,
        lines: '100 g olive oil\n200 g cottage cheese\n1 pinch asafoetida',
        source: _Source(
          answers: {
            'olive oil': [usda('Olive oil')],
          },
        ),
      );
      await _review(tester);
      await _tap(tester, _action(0, 'remember'));
      await _tap(tester, _action(2, 'skip'));
      await _tap(tester, _action(1, 'manual'));
      // Enter a deliberate correction rather than relying on prefill: this
      // journey isolates return/apply/remember from the route-payload test.
      await tester.enterText(_foodName, 'Cottage cheese from this tub');
      await _tap(tester, find.text('Save'));
      expect(find.text('Matches'), findsOneWidget);
      expect(find.text('Cottage cheese from this tub'), findsOneWidget);
      expect(find.text('2 of 3 resolved'), findsOneWidget);
      expect(find.text('1 skipped for now'), findsOneWidget);
      final captured = (await _foods(db)).single;
      expect(captured.name, 'Cottage cheese from this tub');
      expect(await _remembered(db), isEmpty);
      expect(await RecipeStore(db).all(householdId: _household), isEmpty);
      await _tap(tester, find.byKey(const Key('match-review-apply')));
      final saved = await _saveRecipe(tester, db);
      final byName = {
        for (final line in saved.allIngredients) line.name: line.foodId,
      };
      expect(byName['cottage cheese'], captured.id);
      expect(byName['olive oil'], isNotNull);
      expect(byName['asafoetida'], isNull);
      expect(
        await _remembered(db),
        {'olive oil': byName['olive oil']},
        reason: 'Returning from capture must retain the earlier checked choice without remembering the captured or skipped line.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review manual entry keeps authored amount and seeds the food name',
    (tester) async {
      await _openEditor(tester, lines: '200 g cottage cheese, well drained');
      await _review(tester);
      await _tap(tester, _action(0, 'manual'));
      expect(find.text('New food'), findsOneWidget);
      expect(_textIn(tester, _foodName), 'cottage cheese');
      _expectContext(tester, '200 g cottage cheese, well drained');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review scanner and its barcode-miss manual route keep the same ingredient',
    (tester) async {
      final source = _Source();
      final db = await _openEditor(
        tester,
        lines: '200 g cottage cheese, well drained',
        source: source,
      );
      await _review(tester);
      await _tap(tester, _action(0, 'scan'));
      _expectContext(tester, '200 g cottage cheese, well drained');
      await tester.enterText(find.byType(TextField).last, '8002210111110');
      await _tap(tester, find.text('Look it up'));
      expect(source.scans, ['8002210111110']);
      await _tap(tester, find.text('Add it by hand'));
      _expectContext(tester, '200 g cottage cheese, well drained');
      await tester.enterText(_foodName, 'Cottage cheese from barcode miss');
      await _tap(tester, find.text('Save'));
      expect(find.text('1 of 1 resolved'), findsOneWidget);
      expect((await _foods(db)).single.barcode, '8002210111110');
      expect(await _remembered(db), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review search carries external nutrition into a checkable food before returning',
    (tester) async {
      final source = _Source();
      final db = await _openEditor(
        tester,
        lines: '200 g cottage cheese, well drained',
        source: source,
      );
      await _review(tester);
      source.answers = {
        'cottage cheese': [usda('Cottage cheese', kcal: 98)],
      };
      await _tap(tester, _action(0, 'search'));
      _expectContext(tester, '200 g cottage cheese, well drained');
      await _tap(tester, find.text('Cottage cheese'));
      expect(_textIn(tester, _foodName), 'Cottage cheese');
      _expectContext(tester, '200 g cottage cheese, well drained');
      expect(await _foods(db), isEmpty);
      await _tap(tester, find.text('Save'));
      expect(find.text('1 of 1 resolved'), findsOneWidget);
      final saved = (await _foods(db)).single;
      expect(saved.source, FoodSource.usda);
      expect(saved.defaultServing!.macros.kcal, 98);
      expect(await _remembered(db), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit label capture carries reviewed servings through the production new-food route',
    (tester) async {
      final reader = FakeLabelReader();
      final db = await _openEditor(
        tester,
        lines: '2 tbsp cheddar cheese, shredded',
        reader: reader,
      );
      await _review(tester);
      await _tap(tester, _action(0, 'label'));
      _expectContext(tester, '2 tbsp cheddar cheese, shredded');
      expect(reader.calls, 0);
      await _tap(
        tester,
        find.byKey(ValueKey('${LabelSlot.nutrition}-library')),
      );
      expect(reader.calls, 0);
      await _tap(tester, find.text('Read photos'));
      expect(reader.calls, 1);
      expect(_textIn(tester, _foodName), 'cheddar cheese');
      _expectContext(tester, '2 tbsp cheddar cheese, shredded');
      expect(await _foods(db), isEmpty);
      await _tap(tester, find.text('Save'));
      expect(find.text('1 of 1 resolved'), findsOneWidget);
      final saved = (await _foods(db)).single;
      expect(saved.servingOptions, hasLength(2));
      expect(
        saved.servingOptions.map((serving) => serving.macros.kcal),
        everyElement(110),
      );
      expect(await _remembered(db), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the ordinary ingredient picker retains authored quantity and preparation wording',
    (tester) async {
      await _openEditor(tester, lines: '2 tbsp olive oil, divided');
      await _tap(tester, find.text('olive oil, divided'));
      _expectContext(tester, '2 tbsp olive oil, divided');
      expect(tester.takeException(), isNull);
    },
  );

  for (final choice in [
    'Add a serving in tbsp',
    'Scan the packet instead',
    "Read the packet's label",
  ]) {
    testWidgets('a flagged ingredient keeps authored context through $choice', (
      tester,
    ) async {
      final reader = FakeLabelReader();
      final db = await _openFlaggedIngredient(tester, reader: reader);
      await _tap(tester, find.text(choice));
      _expectContext(tester, '2 tbsp white onion, finely chopped');
      expect(reader.calls, 0);
      if (choice == "Read the packet's label") {
        await _tap(
          tester,
          find.byKey(ValueKey('${LabelSlot.nutrition}-library')),
        );
        await _tap(tester, find.text('Read photos'));
        expect(reader.calls, 1);
        expect(find.text('Edit food'), findsOneWidget);
        _expectContext(tester, '2 tbsp white onion, finely chopped');
        // The existing food's gram serving remains beside the new label's
        // ounce/cup servings; this is an edit, not a detached new food.
        await _tap(tester, find.text('Save'));
        final food = (await _foods(db)).single;
        expect(food.id, 'onion');
        expect(food.servingOptions, hasLength(3));
        expect(
          food.servingOptions.map((serving) => serving.macros.kcal),
          containsAll([40, 110, 110]),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
