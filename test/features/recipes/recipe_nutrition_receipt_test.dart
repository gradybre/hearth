import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';
import 'package:hearth/features/recipes/recipe_editor_screen.dart';
import 'package:hearth/features/recipes/recipe_nutrition_receipt.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

const Key _openKey = ValueKey<String>('recipe-nutrition-receipt');
const Key _coverageKey = ValueKey<String>('recipe-nutrition-coverage');
const Key _listKey = ValueKey<String>('recipe-nutrition-receipt-list');
const Key _backKey = ValueKey<String>('receipt-back');

Food beansFood() => aFood(
  'Cannellini beans',
  id: 'beans',
  servingOptions: <ServingOption>[
    aServing(
      id: 'can',
      amount: 1,
      unit: Units.can,
      macros: const Macros(
        kcal: 400,
        proteinG: 24,
        carbG: 60,
        fatG: 4,
        fiberG: 0,
      ),
    ),
  ],
);

Recipe beansRecipe({bool partial = false}) => aRecipe(
  id: 'receipt-recipe',
  title: 'Beans for supper',
  servings: 4,
  ingredients: <RecipeIngredient>[
    RecipeIngredient(
      id: 'beans-line',
      sectionId: 'section-main',
      name: 'white beans',
      quantity: Quantity.of(2, Units.can),
      rawText: '2 cans white beans',
      foodId: 'beans',
      sortOrder: 0,
    ),
    if (partial) ...<RecipeIngredient>[
      RecipeIngredient(
        id: 'sauce-line',
        sectionId: 'section-main',
        name: 'mystery sauce',
        quantity: Quantity.of(1, Units.tbsp),
        rawText: '1 tbsp mystery sauce',
        sortOrder: 1,
      ),
      RecipeIngredient(
        id: 'parsley-line',
        sectionId: 'section-main',
        name: 'parsley',
        quantity: Quantity.of(1, Units.tbsp),
        rawText: '1 tbsp parsley (optional)',
        isOptional: true,
        sortOrder: 2,
      ),
    ],
  ],
  steps: <RecipeStep>[aStep('Warm the beans.')],
);

Future<HearthDatabase> openReceiptRecipe(
  WidgetTester tester, {
  Recipe? recipe,
  List<Food>? foods,
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final Recipe chosen = recipe ?? beansRecipe();
  final HearthDatabase db = await pumpHearthApp(
    tester,
    recipes: <Recipe>[chosen],
    foods: foods ?? <Food>[beansFood()],
    size: size,
    textScale: scale,
    brightness: brightness,
    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
  );
  await pumpFrames(tester);
  await pressReceiptTarget(tester, find.text(chosen.title));
  return db;
}

Finder _verticalScroll() {
  final Finder vertical = find.byWidgetPredicate(
    (Widget widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
  final Finder lists = find.byType(ListView);
  return lists.evaluate().isEmpty
      ? vertical.first
      : find.descendant(of: lists.first, matching: vertical).first;
}

Future<void> reachReceiptTarget(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final ScrollableState state = tester.state<ScrollableState>(
      _verticalScroll(),
    );
    state.position.jumpTo(0);
    await pumpFrames(tester);
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: _verticalScroll(),
      maxScrolls: 100,
    );
  }
  await tester.ensureVisible(finder);
  await pumpFrames(tester);
}

Future<void> pressReceiptTarget(WidgetTester tester, Finder finder) async {
  await reachReceiptTarget(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await pumpFrames(tester, frames: 12);
}

Finder ingredient(int index) =>
    find.byKey(ValueKey<String>('receipt-ingredient-$index'));
Finder inIngredient(int index, String text) =>
    find.descendant(of: ingredient(index), matching: find.text(text));

void main() {
  testWidgets('receipt preserves AI estimate provenance beside its figures', (
    WidgetTester tester,
  ) async {
    await openReceiptRecipe(
      tester,
      foods: <Food>[
        aFood(
          'Cannellini beans',
          id: 'beans',
          source: FoodSource.aiEstimate,
          servingOptions: beansFood().servingOptions,
        ),
      ],
    );
    await pressReceiptTarget(tester, find.byKey(_openKey));
    await reachReceiptTarget(tester, ingredient(0));
    expect(inIngredient(0, 'Source: AI estimate'), findsOneWidget);
    expect(inIngredient(0, '200 kcal'), findsOneWidget);
  });

  testWidgets('receipt multiplier does not snap 0.11 to one eighth', (
    WidgetTester tester,
  ) async {
    await openReceiptRecipe(
      tester,
      foods: <Food>[
        aFood(
          'Spice blend',
          id: 'spice',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              label: '100 g',
              macros: const Macros(kcal: 200),
            ),
          ],
        ),
      ],
      recipe: aRecipe(
        title: 'Seasoned soup',
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient('spices', amount: 11, unit: Units.gram, foodId: 'spice'),
        ],
      ),
    );
    await pressReceiptTarget(tester, find.byKey(_openKey));
    await reachReceiptTarget(tester, ingredient(0));
    expect(inIngredient(0, 'Calculation amount: 0.11 × 100 g'), findsOneWidget);
    expect(inIngredient(0, '22 kcal'), findsOneWidget);
  });

  testWidgets(
    'custom serving label also explains the measured nutrition basis',
    (WidgetTester tester) async {
      await openReceiptRecipe(
        tester,
        foods: <Food>[
          aFood(
            'Spice blend',
            id: 'spice',
            servingOptions: <ServingOption>[
              aServing(
                amount: 100,
                unit: Units.gram,
                label: 'one portion',
                macros: const Macros(kcal: 200),
              ),
            ],
          ),
        ],
        recipe: aRecipe(
          title: 'Seasoned soup',
          servings: 1,
          ingredients: <RecipeIngredient>[
            anIngredient(
              'spices',
              amount: 100,
              unit: Units.gram,
              foodId: 'spice',
            ),
          ],
        ),
      );
      await pressReceiptTarget(tester, find.byKey(_openKey));
      await reachReceiptTarget(tester, ingredient(0));
      expect(
        inIngredient(0, 'Serving basis: one portion (100 g) · 200 kcal'),
        findsOneWidget,
      );
    },
  );

  testWidgets('small nonzero serving multiplier keeps the measured basis', (
    WidgetTester tester,
  ) async {
    await openReceiptRecipe(
      tester,
      foods: <Food>[
        aFood(
          'Spice blend',
          id: 'spice',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              label: 'one portion',
              macros: const Macros(kcal: 200),
            ),
          ],
        ),
      ],
      recipe: aRecipe(
        title: 'Seasoned soup',
        servings: 1,
        ingredients: <RecipeIngredient>[
          anIngredient('spices', amount: 1, unit: Units.gram, foodId: 'spice'),
        ],
      ),
    );
    await pressReceiptTarget(tester, find.byKey(_openKey));
    await reachReceiptTarget(tester, ingredient(0));
    expect(
      inIngredient(0, 'Calculation amount: 0.01 × one portion'),
      findsOneWidget,
    );
    expect(
      inIngredient(0, 'Serving basis: one portion (100 g) · 200 kcal'),
      findsOneWidget,
    );
    expect(inIngredient(0, '2 kcal'), findsOneWidget);
  });

  testWidgets('recipe nutrition opens its read-only calculation receipt', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await openReceiptRecipe(tester);
    final List<RecipeRow> recipesBefore = await db.select(db.recipes).get();
    final List<RecipeIngredientRow> ingredientsBefore = await db
        .select(db.recipeIngredients)
        .get();
    final Finder receipt = find.byKey(_openKey);
    expect(receipt, findsOneWidget);
    await pressReceiptTarget(tester, receipt);
    expect(find.text('Nutrition details'), findsOneWidget);
    await reachReceiptTarget(
      tester,
      inIngredient(0, 'Matched food: Cannellini beans'),
    );
    expect(inIngredient(0, 'As written: 2 cans'), findsOneWidget);
    expect(inIngredient(0, 'Serving basis: 1 can · 400 kcal'), findsOneWidget);
    expect(inIngredient(0, 'Calculation amount: 2 × 1 can'), findsOneWidget);
    expect(inIngredient(0, 'Included · Per serving'), findsOneWidget);
    expect(inIngredient(0, '200 kcal'), findsOneWidget);
    expect(inIngredient(0, 'Fibre: 0 g'), findsOneWidget);
    expect(inIngredient(0, 'Sodium: not stated'), findsOneWidget);
    await pressReceiptTarget(tester, find.byKey(_backKey));
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Per serving'))
          .selected,
      isTrue,
    );
    expect(
      (await db.select(db.recipes).get()).map((RecipeRow row) => row.toJson()),
      recipesBefore.map((RecipeRow row) => row.toJson()),
    );
    expect(
      (await db.select(db.recipeIngredients).get()).map(
        (RecipeIngredientRow row) => row.toJson(),
      ),
      ingredientsBefore.map((RecipeIngredientRow row) => row.toJson()),
    );
  });

  testWidgets(
    'scaled Whole dish receipt keeps the authored amount and Per serving unchanged',
    (WidgetTester tester) async {
      await openReceiptRecipe(tester);
      await pressReceiptTarget(tester, find.text('2×'));
      await pressReceiptTarget(tester, find.text('Whole dish'));
      await pressReceiptTarget(tester, find.byKey(_openKey));
      expect(find.text('Displayed yield: 8 servings.'), findsOneWidget);
      expect(
        find.textContaining(
          'Whole dish is scaled to 8 servings; Per serving is unchanged.',
        ),
        findsOneWidget,
      );
      await reachReceiptTarget(
        tester,
        inIngredient(0, 'Included · Whole dish'),
      );
      expect(inIngredient(0, 'As written: 2 cans'), findsOneWidget);
      expect(inIngredient(0, 'Displayed amount: 4 cans'), findsOneWidget);
      expect(inIngredient(0, 'Calculation amount: 4 × 1 can'), findsOneWidget);
      expect(inIngredient(0, '1600 kcal'), findsOneWidget);
      await pressReceiptTarget(tester, find.byKey(_backKey));
      await pressReceiptTarget(tester, find.text('Per serving'));
      await pressReceiptTarget(tester, find.byKey(_openKey));
      await reachReceiptTarget(tester, inIngredient(0, '200 kcal'));
      expect(inIngredient(0, 'Included · Per serving'), findsOneWidget);
      await reachReceiptTarget(
        tester,
        find.text('Displayed yield: 8 servings.'),
      );
      expect(find.text('Displayed yield: 8 servings.'), findsOneWidget);
    },
  );

  testWidgets(
    'coverage opens the same receipt and separates missing from optional',
    (WidgetTester tester) async {
      await openReceiptRecipe(tester, recipe: beansRecipe(partial: true));
      await pressReceiptTarget(tester, find.byKey(_coverageKey));
      expect(find.byType(RecipeNutritionReceiptScreen), findsOneWidget);
      expect(
        find.text('Known contributions · 1 of 2 ingredients counted'),
        findsOneWidget,
      );
      await reachReceiptTarget(tester, ingredient(1));
      expect(
        inIngredient(1, 'No food match — contribution is unknown, not zero.'),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ingredient(1), matching: find.text('0 kcal')),
        findsNothing,
      );
      await reachReceiptTarget(tester, ingredient(2));
      expect(
        inIngredient(2, 'Optional ingredient — excluded from nutrition.'),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ingredient(2), matching: find.text('0 kcal')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'unavailable, empty-serving, unquantified and incompatible matches explain their own gap',
    (WidgetTester tester) async {
      final Recipe recipe = aRecipe(
        title: 'Unfinished recipe',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'removed food',
            amount: 1,
            unit: Units.can,
            foodId: 'removed',
          ),
          anIngredient(
            'empty food',
            amount: 1,
            unit: Units.can,
            foodId: 'empty',
          ),
          anIngredient('unquantified beans', foodId: 'beans'),
          anIngredient(
            'weighed beans',
            amount: 100,
            unit: Units.gram,
            foodId: 'beans',
          ),
          anIngredient('seasoning', needsNoMatch: true),
        ],
      );
      await openReceiptRecipe(
        tester,
        recipe: recipe,
        foods: <Food>[
          beansFood(),
          aFood('Empty food', id: 'empty'),
        ],
      );
      await pressReceiptTarget(tester, find.byKey(_openKey));
      expect(
        find.textContaining(
          'Missing ingredients are not zero-calorie ingredients.',
        ),
        findsOneWidget,
      );
      final List<String> reasons = <String>[
        'The matched food is unavailable — contribution is unknown, not zero.',
        'This food has no nutrition serving — contribution is unknown, not zero.',
        'Amount not specified — contribution is unknown, not zero.',
        'No compatible serving for this amount and unit — contribution is unknown, not zero.',
        'Excluded — marked as needing no nutrition match.',
      ];
      for (int i = 0; i < reasons.length; i++) {
        await reachReceiptTarget(tester, ingredient(i));
        expect(inIngredient(i, reasons[i]), findsOneWidget);
        expect(
          find.descendant(of: ingredient(i), matching: find.text('0 kcal')),
          findsNothing,
        );
      }
    },
  );

  testWidgets(
    'approximate package evidence qualifies the serving multiplier and contribution',
    (WidgetTester tester) async {
      final ServingOption serving = aServing(
        id: 'cup',
        amount: 1,
        unit: Units.cup,
        macros: const Macros(kcal: 100),
      );
      final Food food = aFood(
        'Packaged stew',
        id: 'stew',
        packSize: Quantity.of(200, Units.gram),
        servingOptions: <ServingOption>[serving],
        packageNutrition: PackageNutrition.manual(
          servingOptionId: serving.id,
          servingAmount: serving.amount,
          packageAmount: Quantity.of(200, Units.gram),
          servingsPerPackage: 4,
          isApproximate: true,
        ),
      );
      await openReceiptRecipe(
        tester,
        recipe: aRecipe(
          title: 'Stew',
          servings: 2,
          ingredients: <RecipeIngredient>[
            anIngredient('stew', amount: 100, unit: Units.gram, foodId: 'stew'),
          ],
        ),
        foods: <Food>[food],
      );
      await pressReceiptTarget(tester, find.byKey(_openKey));
      await reachReceiptTarget(tester, ingredient(0));
      expect(
        inIngredient(0, 'Calculation amount: about 2 × 1 cup'),
        findsOneWidget,
      );
      expect(
        inIngredient(0, 'Uses approximate package servings'),
        findsOneWidget,
      );
      expect(inIngredient(0, '100 kcal'), findsOneWidget);
    },
  );

  testWidgets('restaurant deductions stay signed without changing the total', (
    WidgetTester tester,
  ) async {
    await openReceiptRecipe(
      tester,
      recipe: aRecipe(
        title: 'Usual order',
        servings: 1,
        kind: RecipeKind.eatenOut,
        ingredients: <RecipeIngredient>[
          anIngredient('beans', amount: 2, unit: Units.can, foodId: 'beans'),
          anIngredient(
            'less beans',
            amount: -0.5,
            unit: Units.can,
            foodId: 'beans',
          ),
        ],
      ),
    );
    await pressReceiptTarget(tester, find.byKey(_openKey));
    expect(find.text('600 kcal'), findsOneWidget);
    await reachReceiptTarget(tester, ingredient(1));
    expect(
      inIngredient(1, 'Included adjustment · Per serving'),
      findsOneWidget,
    );
    expect(inIngredient(1, '−200 kcal'), findsOneWidget);
    expect(inIngredient(1, 'Calculation amount: −0.5 × 1 can'), findsOneWidget);
  });

  testWidgets(
    'editor uses both bases and receipt sees the live unsaved yield',
    (WidgetTester tester) async {
      final HearthDatabase db = await openReceiptRecipe(tester);
      await pressReceiptTarget(tester, find.text('Edit'));
      final Finder serves = find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField &&
            widget.keyboardType ==
                const TextInputType.numberWithOptions(decimal: true),
      );
      await reachReceiptTarget(tester, serves);
      await tester.enterText(serves, '8');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFrames(tester);
      await pressReceiptTarget(tester, find.text('Whole dish'));
      await pressReceiptTarget(tester, find.byKey(_openKey));
      expect(find.text('Current editor preview'), findsOneWidget);
      expect(find.text('Displayed yield: 8 servings.'), findsOneWidget);
      await reachReceiptTarget(tester, ingredient(0));
      expect(inIngredient(0, '800 kcal'), findsOneWidget);
      await pressReceiptTarget(tester, find.byKey(_backKey));
      expect(find.byType(RecipeEditorScreen), findsOneWidget);
      await pressReceiptTarget(tester, find.text('Per serving'));
      await pressReceiptTarget(tester, find.byKey(_openKey));
      await reachReceiptTarget(tester, ingredient(0));
      expect(inIngredient(0, '100 kcal'), findsOneWidget);
      expect((await db.select(db.recipes).getSingle()).servings, 4);
      await pressReceiptTarget(tester, find.byKey(_backKey));
      await reachReceiptTarget(tester, serves);
      expect(tester.widget<TextField>(serves).controller!.text, '8');
    },
  );

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      '3x receipt opens with readable title and recipe identity in ${brightness.name}',
      (WidgetTester tester) async {
        await openReceiptRecipe(
          tester,
          size: const Size(320, 568),
          scale: 3,
          brightness: brightness,
        );
        await pressReceiptTarget(tester, find.byKey(_openKey));
        final RenderParagraph heading = _paragraph(tester, 'Nutrition details');
        for (final TextSelection word in <TextSelection>[
          const TextSelection(baseOffset: 0, extentOffset: 9),
          const TextSelection(baseOffset: 10, extentOffset: 17),
        ]) {
          expect(
            heading
                .getBoxesForSelection(word)
                .map((TextBox box) => box.top)
                .toSet(),
            hasLength(1),
            reason: 'The receipt title must wrap between its words, not inside them.',
          );
        }
        final Rect viewport = tester.getRect(find.byKey(_listKey));
        _within(tester.getRect(find.text('Nutrition details')), viewport);
        _within(tester.getRect(find.text('Beans for supper')), viewport);
      },
    );
    for (final bool editor in <bool>[false, true]) {
      testWidgets(
        '3x entry word stays intact in ${brightness.name} ${editor ? 'editor' : 'detail'}',
        (WidgetTester tester) async {
          await openReceiptRecipe(
            tester,
            size: const Size(320, 568),
            scale: 3,
            brightness: brightness,
          );
          if (editor) await pressReceiptTarget(tester, find.text('Edit'));
          await reachReceiptTarget(tester, find.byKey(_openKey));
          final RenderParagraph paragraph = _paragraph(tester, 'Nutrition');
          _expectTextPainted(paragraph, 'Nutrition');
          expect(
            paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 9),
                )
                .map((TextBox box) => box.top)
                .toSet(),
            hasLength(1),
            reason: 'The information icon must not split the heading inside its only word.',
          );
        },
      );
      testWidgets(
        '3x selected basis labels stay complete in ${brightness.name} ${editor ? 'editor' : 'detail'}',
        (WidgetTester tester) async {
          await openReceiptRecipe(
            tester,
            size: const Size(320, 568),
            scale: 3,
            brightness: brightness,
          );
          if (editor) await pressReceiptTarget(tester, find.text('Edit'));
          for (final String label in <String>['Per serving', 'Whole dish']) {
            await pressReceiptTarget(tester, find.text(label));
            final Finder choice = find.widgetWithText(ChoiceChip, label);
            expect(tester.widget<ChoiceChip>(choice).selected, isTrue);
            final RenderParagraph paragraph = _paragraph(tester, label);
            _expectTextPainted(paragraph, label);
            final Rect buttonBounds = tester.getRect(choice);
            for (final TextBox box in paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            )) {
              _within(
                box.toRect().shift(paragraph.localToGlobal(Offset.zero)),
                buttonBounds,
              );
            }
            expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
          }
        },
      );
      testWidgets(
        '320x568 3x ${brightness.name} ${editor ? 'editor' : 'detail'} receipt stays scrollable and Back reachable',
        (WidgetTester tester) async {
          await openReceiptRecipe(
            tester,
            recipe: beansRecipe(partial: true),
            size: const Size(320, 568),
            scale: 3,
            brightness: brightness,
          );
          if (editor) await pressReceiptTarget(tester, find.text('Edit'));
          final Finder button = find.byKey(_openKey);
          await reachReceiptTarget(tester, button);
          final Rect buttonBounds = tester.getRect(button);
          expect(buttonBounds.width, greaterThanOrEqualTo(48));
          expect(buttonBounds.height, greaterThanOrEqualTo(48));
          await pressReceiptTarget(tester, button);
          expect(
            MediaQuery.textScalerOf(
              tester.element(find.byType(RecipeNutritionReceiptScreen)),
            ).scale(16),
            48,
          );
          final Rect viewport = tester.getRect(find.byKey(_listKey));
          expect(viewport.height, greaterThan(0));
          await reachReceiptTarget(tester, inIngredient(0, '200 kcal'));
          _within(tester.getRect(inIngredient(0, '200 kcal')), viewport);
          await reachReceiptTarget(
            tester,
            inIngredient(2, 'Optional ingredient — excluded from nutrition.'),
          );
          expect(
            inIngredient(2, 'Optional ingredient — excluded from nutrition.'),
            findsOneWidget,
          );
          final Finder back = find.byKey(_backKey);
          expect(back.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(back).size.shortestSide,
            greaterThanOrEqualTo(48),
          );
          await pressReceiptTarget(tester, back);
          expect(
            find.byType(editor ? RecipeEditorScreen : RecipeDetailScreen),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('receipt entry and Back can be activated by keyboard', (
    WidgetTester tester,
  ) async {
    await openReceiptRecipe(tester);
    final Finder button = find.byKey(_openKey);
    await reachReceiptTarget(tester, button);
    // Move focus through actual controls instead of invoking a callback.
    for (int i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (Focus.of(
        tester.element(
          find.descendant(of: button, matching: find.text('Nutrition')),
        ),
      ).hasFocus) {
        break;
      }
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester, frames: 12);
    expect(find.byType(RecipeNutritionReceiptScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester, frames: 12);
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
  });
}

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );

void _expectTextPainted(RenderParagraph paragraph, String text) {
  final List<TextBox> boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty);
  for (final TextBox box in boxes) {
    expect(box.left, greaterThanOrEqualTo(-1));
    expect(
      box.right,
      lessThanOrEqualTo(paragraph.size.width + 1),
      reason: '$text must not fade or clip at the end.',
    );
  }
}

void _within(Rect child, Rect parent) {
  expect(child.left, greaterThanOrEqualTo(parent.left - 1));
  expect(child.right, lessThanOrEqualTo(parent.right + 1));
  expect(child.top, greaterThanOrEqualTo(parent.top - 1));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 1));
}
