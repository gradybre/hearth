import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_format.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';
import 'package:hearth/features/recipes/recipe_editor_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import 'restaurant_usual_fixtures.dart';

void main() {
  testWidgets('an added menu item changing its count unit requires Reset', (
    WidgetTester tester,
  ) async {
    Food sauce(Unit unit) => aFood(
      'Sauce',
      id: 'added-sauce',
      brand: 'Corner Kitchen',
      source: FoodSource.restaurant,
      menuOrder: 5,
      servingOptions: <ServingOption>[
        aServing(
          id: 'added-sauce-serving',
          amount: 1,
          unit: unit,
          macros: const Macros(kcal: 50),
        ),
      ],
    );
    final StreamController<List<Food>> updates = StreamController<List<Food>>();
    addTearDown(updates.close);
    final HearthDatabase db = await _openMenu(
      tester,
      foodStream: () async* {
        yield <Food>[...usualMenuFoods(), sauce(Units.packet)];
        yield* updates.stream;
      }(),
    );
    await _tap(tester, find.byKey(const Key('usual-customize-saved-usual')));
    await _tap(tester, find.text('Sauce'));
    updates.add(<Food>[...usualMenuFoods(), sauce(Units.bottle)]);
    await pumpFrames(tester);
    await _reveal(tester, find.byKey(const Key('usual-reset')), scrollBy: -200);
    expect(find.textContaining('Menu portions changed while'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('usual-review-variation')))
          .onPressed,
      isNull,
    );
    expect(await db.select(db.recipes).get(), hasLength(1));
    expect(await db.select(db.mealPlanEntries).get(), isEmpty);
  });

  testWidgets('ambiguous saved ingredient names require explicit review', (
    WidgetTester tester,
  ) async {
    final Recipe original = aRecipe(
      id: 'saved-usual',
      title: 'Our usual dinner',
      kind: RecipeKind.eatenOut,
      ingredients: <RecipeIngredient>[
        anIngredient(
          'Side',
          amount: 1,
          unit: Units.item,
          foodId: 'usual-burger',
        ),
        anIngredient(
          'side',
          amount: 100,
          unit: Units.gram,
          foodId: 'usual-rice',
        ),
      ],
    );
    final HearthDatabase db = await _openMenu(tester, order: original);
    final RecipeRow before = (await db.select(db.recipes).get()).single;
    await _tap(tester, find.byKey(const Key('usual-customize-saved-usual')));
    await _tap(tester, find.byKey(const Key('usual-review-variation')));
    expect(find.text('Review ingredient names'), findsOneWidget);
    expect(find.byType(RecipeEditorScreen), findsNothing);
    await _tap(tester, find.text('View saved details'));
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(
      (await db.select(db.recipes).get()).single.toJson(),
      before.toJson(),
    );
    expect(await db.select(db.mealPlanEntries).get(), isEmpty);
  });

  testWidgets('saved usual exposes Log this, Customize and Details', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      size: const Size(390, 1000),
      foods: usualMenuFoods(),
      recipes: <Recipe>[savedUsual()],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await addRecipeVia(tester, 'Eat out');
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Corner Kitchen'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Log this'), findsOneWidget);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
  });

  for (final int offset in <int>[-2, 2]) {
    testWidgets('Log this reviews the original day and dinner ($offset days)', (
      WidgetTester tester,
    ) async {
      final DateTime date = addDays(DateTime.now(), offset);
      final HearthDatabase db = await _openMenu(tester, mealDate: date);
      final RecipeRow before = (await db.select(db.recipes).get()).single;
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));

      expect(find.text('Our usual dinner'), findsWidgets);
      expect(
        find.text('Dinner · ${weekdayName(date)} ${shortDate(date)}'),
        findsOneWidget,
      );
      expect(find.textContaining('750 kcal'), findsOneWidget);
      expect(
        await db.select(db.mealPlanEntries).get(),
        isEmpty,
        reason: 'Opening the usual must not silently write a meal.',
      );
      final Finder portion = find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.byType(TextField),
      );
      await tester.enterText(portion, '0.5');
      await _tap(tester, find.text(offset > 0 ? 'Add to plan' : 'Log it'));
      final MealPlanEntryRow entry =
          (await db.select(db.mealPlanEntries).get()).single;
      final MealPlanDayRow day =
          (await db.select(db.mealPlanDays).get()).single;
      expect(dayKey(day.day), dayKey(date));
      expect(entry.mealSlot, MealSlot.dinner.name);
      expect(entry.refId, 'saved-usual');
      expect(entry.servings, 0.5);
      expect(entry.isLogged, offset < 0);
      if (offset < 0) {
        final Map<String, Object?> snapshot =
            jsonDecode(entry.macroSnapshot!) as Map<String, Object?>;
        expect(snapshot['kcal'], 375);
      } else {
        expect(entry.macroSnapshot, isNull);
      }
      expect(
        (await db.select(db.recipes).get()).single.toJson(),
        before.toJson(),
      );
    });
  }

  testWidgets(
    'library Log this asks for a day and meal and cancel writes nothing',
    (WidgetTester tester) async {
      final HearthDatabase db = await _openMenu(tester);
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      final DateTime today = dayKey(DateTime.now());
      expect(find.text('Which day and meal?'), findsOneWidget);
      expect(
        find.text(
          '${weekdayName(today)} ${monthName(today)} '
          '${today.day}, ${today.year}',
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('Cancel'));
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);

      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      await _tap(tester, find.byTooltip('Next day'));
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Lunch'));
      await _tap(tester, find.text('Review portion'));
      expect(find.text('Lunch · Tomorrow'), findsOneWidget);
      await _tap(tester, find.text('Add to plan'));
      final MealPlanEntryRow entry =
          (await db.select(db.mealPlanEntries).get()).single;
      final MealPlanDayRow day =
          (await db.select(db.mealPlanDays).get()).single;
      expect(dayKey(day.day), addDays(today, 1));
      expect(entry.mealSlot, MealSlot.lunch.name);
      expect(entry.isLogged, isFalse);
    },
  );

  testWidgets('Details opens the saved recipe without saving or logging', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await _openMenu(tester);
    await _tap(tester, find.byKey(const Key('usual-details-saved-usual')));
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    expect(await db.select(db.recipes).get(), hasLength(1));
  });

  for (final bool deleted in <bool>[true, false]) {
    testWidgets(
      'destination handoff reviews changed menu evidence (deleted: $deleted)',
      (WidgetTester tester) async {
        final StreamController<List<Food>> updates =
            StreamController<List<Food>>();
        addTearDown(updates.close);
        final HearthDatabase db = await _openMenu(
          tester,
          foodStream: () async* {
            yield usualMenuFoods();
            yield* updates.stream;
          }(),
        );
        await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
        expect(find.text('Which day and meal?'), findsOneWidget);
        await _tap(tester, find.byTooltip('Next day'));
        await _tap(tester, find.widgetWithText(ChoiceChip, 'Lunch'));
        updates.add(<Food>[
          for (final Food food in usualMenuFoods())
            if (food.id != 'usual-rice')
              food
            else if (!deleted)
              aFood(
                'Rice',
                id: 'usual-rice',
                brand: 'Corner Kitchen',
                source: FoodSource.restaurant,
                servingOptions: <ServingOption>[
                  aServing(
                    amount: 200,
                    unit: Units.gram,
                    macros: const Macros(
                      kcal: 250,
                      proteinG: 5,
                      carbG: 50,
                      fatG: 3,
                    ),
                  ),
                ],
              ),
        ]);
        await pumpFrames(tester);
        await _tap(tester, find.text('Review portion'));
        expect(
          find.text('Review current order'),
          findsOneWidget,
          reason: 'A new sheet must not treat the chooser’s old evidence as acceptance.',
        );
        if (deleted) {
          expect(
            find.textContaining('Rice: This component is unavailable'),
            findsOneWidget,
          );
          await _tap(tester, find.text('Cancel'));
        } else {
          await _tap(tester, find.text('Continue to review'));
          expect(find.text('Lunch · Tomorrow'), findsOneWidget);
          expect(find.textContaining('694 kcal'), findsOneWidget);
        }
        expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      },
    );
  }

  testWidgets(
    'component-review acceptance cannot authorize a later missing line',
    (WidgetTester tester) async {
      final StreamController<List<Food>> updates =
          StreamController<List<Food>>();
      addTearDown(updates.close);
      final HearthDatabase db = await _openMenu(
        tester,
        mealDate: addDays(DateTime.now(), -2),
        missing: true,
        foodStream: () async* {
          yield usualMenuFoods();
          yield* updates.stream;
        }(),
      );
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      expect(find.text('Review saved components'), findsOneWidget);
      updates.add(<Food>[
        for (final Food food in usualMenuFoods())
          if (food.id != 'usual-rice') food,
      ]);
      await pumpFrames(tester);
      await _tap(tester, find.text('Continue to review'));
      expect(find.text('Review current order'), findsOneWidget);
      expect(
        find.textContaining('Rice: This component is unavailable'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Cancel'));
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    },
  );

  testWidgets(
    'Customize restores whole quantities and Reset restores the base',
    (WidgetTester tester) async {
      final HearthDatabase db = await _openMenu(tester);
      final RecipeRow before = (await db.select(db.recipes).get()).single;
      await _tap(tester, find.byKey(const Key('usual-customize-saved-usual')));
      expect(find.text('Base'), findsOneWidget);
      expect(find.textContaining('Whole recipe · 2 servings'), findsOneWidget);
      await _tap(tester, find.text('Lettuce wrap'));
      await _reveal(tester, find.text('Added'), scrollBy: -200);
      expect(find.text('Energy −180 kcal'), findsOneWidget);
      expect(find.text('Fibre +1 g'), findsOneWidget);
      expect(find.text('Published menu adjustment'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('usual-reset')), scrollBy: -200);
      expect(find.text('No additions'), findsOneWidget);
      expect(find.text('No removals'), findsOneWidget);
      expect(
        (await db.select(db.recipes).get()).single.toJson(),
        before.toJson(),
      );
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    },
  );

  testWidgets('ordinary removals show their signed effect and assumption', (
    WidgetTester tester,
  ) async {
    await _openMenu(tester);
    await _tap(tester, find.byKey(const Key('usual-customize-saved-usual')));
    await _tap(tester, find.byTooltip('Take Lettuce out'));
    await _reveal(tester, find.text('Removed'), scrollBy: -200);
    expect(find.text('Energy −5 kcal'), findsOneWidget);
    expect(find.textContaining('Assumption:'), findsOneWidget);
  });

  testWidgets(
    'unavailable components must be reviewed before a usual is logged',
    (WidgetTester tester) async {
      final HearthDatabase db = await _openMenu(
        tester,
        missing: true,
        mealDate: addDays(DateTime.now(), -2),
      );
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      expect(find.text('Review saved components'), findsOneWidget);
      expect(find.textContaining('House sauce:'), findsOneWidget);
      expect(find.text('Log it'), findsNothing);
      await _tap(tester, find.text('Cancel'));
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    },
  );

  testWidgets(
    'a saved deduction-only usual cannot bypass the negative-meal guard',
    (WidgetTester tester) async {
      final HearthDatabase db = await _openMenu(
        tester,
        order: aRecipe(
          id: 'saved-usual',
          title: 'Invalid usual',
          servings: 1,
          kind: RecipeKind.eatenOut,
          notes: 'Corner Kitchen',
          ingredients: <RecipeIngredient>[
            anIngredient(
              'Rice',
              amount: -100,
              unit: Units.gram,
              foodId: 'usual-rice',
            ),
          ],
        ),
      );
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      expect(find.textContaining('less than nothing'), findsOneWidget);
      expect(find.text('Which day and meal?'), findsNothing);
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    },
  );

  testWidgets('a saved twice-applied modifier cannot bypass fast-path guards', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await _openMenu(
      tester,
      mealDate: addDays(DateTime.now(), -2),
      order: aRecipe(
        id: 'saved-usual',
        title: 'Burger with double wrap adjustment',
        servings: 1,
        kind: RecipeKind.eatenOut,
        notes: 'Corner Kitchen',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'Burger',
            amount: 2,
            unit: Units.item,
            foodId: 'usual-burger',
          ),
          anIngredient(
            'Lettuce wrap',
            amount: 2,
            unit: Units.item,
            foodId: 'usual-wrap',
          ),
        ],
      ),
    );
    await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
    if (find.text('Continue to review').evaluate().isNotEmpty) {
      await _tap(tester, find.text('Continue to review'));
    }
    if (find.text('Log it').evaluate().isNotEmpty) {
      await _tap(tester, find.text('Log it'));
    }
    expect(
      await db.select(db.mealPlanEntries).get(),
      isEmpty,
      reason:
          'A saved usual must preserve the existing apply-once modifier guard.',
    );
    expect(find.textContaining('can be applied only once'), findsOneWidget);
  });

  testWidgets('changing restaurants asks before discarding a variation', (
    WidgetTester tester,
  ) async {
    await _openMenu(tester);
    await _tap(tester, find.byKey(const Key('usual-customize-saved-usual')));
    await _tap(tester, find.text('Lettuce wrap'));
    await tester.tap(find.byTooltip('Back to restaurants'));
    await pumpFrames(tester);
    await tester.tap(find.text('Keep choosing'));
    await pumpFrames(tester);
    expect(
      find.byKey(const Key('usual-customization-receipt')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Back to restaurants'));
    await pumpFrames(tester);
    await tester.tap(find.text('Discard choices'));
    await pumpFrames(tester);
    await tester.tap(find.text('Corner Kitchen'));
    await pumpFrames(tester);
    expect(find.byKey(const Key('usual-customization-receipt')), findsNothing);
    expect(find.byKey(const Key('usual-log-saved-usual')), findsOneWidget);
  });

  testWidgets(
    'a menu deletion during customization requires Reset and review',
    (WidgetTester tester) async {
      final StreamController<List<Food>> updates =
          StreamController<List<Food>>();
      addTearDown(updates.close);
      final HearthDatabase db = await _openMenu(
        tester,
        foodStream: () async* {
          yield usualMenuFoods();
          yield* updates.stream;
        }(),
      );
      await _tap(tester, find.byKey(const Key('usual-customize-saved-usual')));
      await _tap(tester, find.text('Lettuce wrap'));
      final List<Food> changed = usualMenuFoods();
      changed[0] = changed[0].withDeleted();
      updates.add(changed);
      await pumpFrames(tester);
      await _reveal(
        tester,
        find.byKey(const Key('usual-reset')),
        scrollBy: -200,
      );
      expect(
        find.textContaining('Menu portions changed while'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('usual-review-variation')),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, find.byKey(const Key('usual-reset')));
      await _tap(
        tester,
        find.byKey(const Key('usual-review-variation')),
        scrollBy: -200,
      );
      expect(find.text('Review saved components'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet).last,
          matching: find.textContaining('Burger:'),
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('Cancel'));
      expect(await db.select(db.recipes).get(), hasLength(1));
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    },
  );

  testWidgets(
    'deleting a preselected usual while review is open cannot log it',
    (WidgetTester tester) async {
      final StreamController<List<Recipe>> updates =
          StreamController<List<Recipe>>();
      addTearDown(updates.close);
      final HearthDatabase db = await _openMenu(
        tester,
        mealDate: addDays(DateTime.now(), -2),
        recipeStream: () async* {
          yield <Recipe>[savedUsual()];
          yield* updates.stream;
        }(),
      );
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      expect(find.text('Log it'), findsOneWidget);
      updates.add(<Recipe>[]);
      await pumpFrames(tester);
      expect(
        find.textContaining('This recipe is no longer available'),
        findsOneWidget,
      );
      expect(find.text('Log it'), findsNothing);
      await _tap(tester, find.text('Close'));
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    },
  );

  testWidgets(
    'component deletion during fast-path review cannot silently drop it',
    (WidgetTester tester) async {
      final StreamController<List<Food>> updates =
          StreamController<List<Food>>();
      addTearDown(updates.close);
      final HearthDatabase db = await _openMenu(
        tester,
        mealDate: addDays(DateTime.now(), -2),
        foodStream: () async* {
          yield usualMenuFoods();
          yield* updates.stream;
        }(),
      );
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      expect(find.textContaining('750 kcal'), findsOneWidget);
      updates.add(<Food>[
        for (final Food food in usualMenuFoods())
          if (food.id != 'usual-rice') food,
      ]);
      await pumpFrames(tester);
      await _tap(tester, find.text('Log it'));
      expect(
        await db.select(db.mealPlanEntries).get(),
        isEmpty,
        reason: 'A missing component needs explicit review, not a smaller silent total.',
      );
    },
  );

  testWidgets(
    'a newly negative total cannot save from an already-open usual review',
    (WidgetTester tester) async {
      final StreamController<List<Food>> updates =
          StreamController<List<Food>>();
      addTearDown(updates.close);
      final HearthDatabase db = await _openMenu(
        tester,
        mealDate: addDays(DateTime.now(), -2),
        order: aRecipe(
          id: 'saved-usual',
          title: 'Burger with lettuce wrap',
          servings: 1,
          kind: RecipeKind.eatenOut,
          notes: 'Corner Kitchen',
          ingredients: <RecipeIngredient>[
            anIngredient(
              'Burger',
              amount: 1,
              unit: Units.item,
              foodId: 'usual-burger',
            ),
            anIngredient(
              'Lettuce wrap',
              amount: 1,
              unit: Units.item,
              foodId: 'usual-wrap',
            ),
          ],
        ),
        foodStream: () async* {
          yield usualMenuFoods();
          yield* updates.stream;
        }(),
      );
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      expect(find.textContaining('420 kcal'), findsOneWidget);
      final List<Food> changed = usualMenuFoods();
      changed[0] = aFood(
        'Burger',
        id: 'usual-burger',
        brand: 'Corner Kitchen',
        source: FoodSource.restaurant,
        servingOptions: <ServingOption>[
          aServing(
            amount: 1,
            unit: Units.item,
            macros: const Macros(kcal: 100, proteinG: 30, carbG: 50, fatG: 25),
          ),
        ],
      );
      updates.add(changed);
      await pumpFrames(tester);
      await _tap(tester, find.text('Log it'));
      expect(
        await db.select(db.mealPlanEntries).get(),
        isEmpty,
        reason: 'Current facts made this meal negative after its fast-path guard ran.',
      );
    },
  );

  testWidgets(
    'held Log it rechecks a deleted component before the next frame',
    (WidgetTester tester) async {
      final StreamController<List<Food>> updates =
          StreamController<List<Food>>();
      addTearDown(updates.close);
      final HearthDatabase db = await _openMenu(
        tester,
        mealDate: addDays(DateTime.now(), -2),
        foodStream: () async* {
          yield usualMenuFoods();
          yield* updates.stream;
        }(),
      );
      await _tap(tester, find.byKey(const Key('usual-log-saved-usual')));
      final Finder log = find.text('Log it');
      await _reveal(tester, log);
      final TestGesture heldTap = await tester.startGesture(
        tester.getCenter(log),
      );
      updates.add(<Food>[
        for (final Food food in usualMenuFoods())
          if (food.id != 'usual-rice') food,
      ]);
      // Deliver the provider value, without rebuilding the button that took
      // pointer-down. The real pointer-up still reaches its captured callback.
      await tester.idle();
      await heldTap.up();
      await pumpFrames(tester);
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'customization stays reachable at 320pt 3x $brightness with keyboard',
      (WidgetTester tester) async {
        await _openMenu(
          tester,
          size: const Size(320, 568),
          textScale: 3,
          brightness: brightness,
        );
        await _tap(
          tester,
          find.byKey(const Key('usual-customize-saved-usual')),
        );
        await _reveal(tester, find.byKey(const Key('usual-reset')));
        final Finder resetText = find.descendant(
          of: find.byKey(const Key('usual-reset')),
          matching: find.byType(RichText),
        );
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          resetText,
        );
        expect(paragraph.textScaler.scale(16), 48);
        expect(
          tester.getSize(find.byKey(const Key('usual-reset'))).height,
          greaterThanOrEqualTo(48),
        );
        await _reveal(tester, find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Lettuce');
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        tester.view.padding = const FakeViewPadding(top: 24);
        await pumpFrames(tester);
        await _tap(tester, find.text('Lettuce wrap'));
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding();
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        FocusManager.instance.primaryFocus?.unfocus();
        await pumpFrames(tester);
        await _tap(
          tester,
          find.byKey(const Key('usual-reset')),
          scrollBy: -200,
        );
        expect(tester.takeException(), isNull);
        await _tap(
          tester,
          find.byKey(const Key('usual-review-variation')),
          scrollBy: -200,
        );
        expect(find.byType(RecipeEditorScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<HearthDatabase> _openMenu(
  WidgetTester tester, {
  DateTime? mealDate,
  bool missing = false,
  Recipe? order,
  Stream<List<Food>>? foodStream,
  Stream<List<Recipe>>? recipeStream,
  Size size = const Size(390, 1000),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    size: size,
    textScale: textScale,
    brightness: brightness,
    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
    selectedDate: mealDate ?? DateTime(2020, 1, 1),
    foods: usualMenuFoods(),
    foodStream: foodStream,
    recipes: <Recipe>[order ?? savedUsual(missing: missing)],
    recipeStream: recipeStream,
  );
  if (mealDate == null) {
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await _tap(tester, find.text('Add recipe'));
    await _tap(tester, find.text('Eat out'));
  } else {
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester);
    await _tap(tester, find.byTooltip('Add to dinner').first);
    await _tap(
      tester,
      find.text(
        calendarDaysBetween(DateTime.now(), mealDate) > 0
            ? 'Plan a restaurant meal'
            : 'Ate out — build it from a menu',
      ),
    );
  }
  await pumpFrames(tester, frames: 12);
  await _tap(tester, find.text('Corner Kitchen'));
  return db;
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  double scrollBy = 200,
}) async {
  if (target.hitTestable().evaluate().isNotEmpty) return;
  final Finder scrollable = find
      .descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    target,
    scrollBy,
    scrollable: scrollable,
    maxScrolls: 100,
  );
  await pumpFrames(tester);
  expect(target.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _tap(
  WidgetTester tester,
  Finder target, {
  double scrollBy = 200,
}) async {
  await _reveal(tester, target, scrollBy: scrollBy);
  await tester.tap(target);
  await pumpFrames(tester, frames: 16);
  expect(tester.takeException(), isNull);
}
