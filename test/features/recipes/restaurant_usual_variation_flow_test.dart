import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/recipe_icon.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_format.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/log_sheet.dart';
import 'package:hearth/features/recipes/recipe_editor_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';
import 'restaurant_usual_fixtures.dart';

class _NoDrawing implements RecipeIconSource {
  final List<String> titles = <String>[];

  @override
  Future<String?> draw({required String title}) async {
    titles.add(title);
    return null;
  }
}

void main() {
  testWidgets(
    'preselected variation review refuses a repeated published modifier',
    (WidgetTester tester) async {
      final Recipe variation = aRecipe(
        id: 'new-variation',
        title: 'Double burger variation',
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
      );
      final HearthDatabase db = await pumpHearthApp(
        tester,
        size: const Size(390, 1000),
        foods: usualMenuFoods(),
        recipes: <Recipe>[variation],
      );
      await pumpFrames(tester);
      unawaited(
        showLogSheet(
          tester.element(find.byType(Scaffold).first),
          date: addDays(DateTime.now(), -2),
          slot: MealSlot.dinner,
          initialRecipeId: variation.id,
        ),
      );
      await pumpFrames(tester, frames: 12);
      await SweepTools(tester).reach(find.text('Log it'));
      expect(
        await db.select(db.mealPlanEntries).get(),
        isEmpty,
        reason:
            'Saving a variation does not make a twice-applied modifier valid.',
      );
      expect(find.textContaining('can be applied only once'), findsOneWidget);
    },
  );

  for (final ({int days, bool commit}) scenario in <({int days, bool commit})>[
    (days: -2, commit: true),
    (days: 2, commit: true),
    (days: -2, commit: false),
  ]) {
    testWidgets(
      'variation saves separately before portion review (${scenario.days}, commit ${scenario.commit})',
      (WidgetTester tester) async {
        final DateTime date = addDays(DateTime.now(), scenario.days);
        final Recipe original = savedUsual();
        final StreamController<List<Recipe>> updates =
            StreamController<List<Recipe>>();
        addTearDown(updates.close);
        final _NoDrawing icons = _NoDrawing();
        final HearthDatabase db = await _openVariation(
          tester,
          date: date,
          icons: icons,
          recipeStream: () async* {
            yield <Recipe>[original];
            yield* updates.stream;
          }(),
        );
        final RecipeRow before = (await db.select(db.recipes).get()).single;
        expect(await db.select(db.mealPlanEntries).get(), isEmpty);
        final SweepTools tools = SweepTools(tester);
        await tools.reach(find.text('Save new variation and review portion'));

        final List<RecipeRow> rows = await db.select(db.recipes).get();
        expect(rows, hasLength(2));
        expect(
          rows.singleWhere((RecipeRow row) => row.id == original.id).toJson(),
          before.toJson(),
        );
        final RecipeRow added = rows.singleWhere(
          (RecipeRow row) => row.id != original.id,
        );
        final Recipe variation = (await RecipeStore(db).byId(added.id))!;
        expect(variation.servings, 2);
        expect(variation.title, 'Our usual dinner (variation)');
        expect(
          variation.allIngredients.map((RecipeIngredient line) => line.foodId),
          <String>['usual-burger', 'usual-rice', 'usual-wrap'],
        );
        expect(
          variation.sections.single.id,
          isNot(original.sections.single.id),
        );
        expect(
          await db.select(db.mealPlanEntries).get(),
          isEmpty,
          reason: 'Saving the reusable variation is not approval of a personal portion.',
        );
        expect(
          icons.titles,
          isEmpty,
          reason: 'An explicit variation does not request new AI artwork.',
        );

        // The harness library is a controlled stream. Publish the real saved
        // recipe as the production repository watcher would after its save.
        updates.add(<Recipe>[original, variation]);
        await pumpFrames(tester, frames: 16);
        expect(
          find.text('Dinner · ${weekdayName(date)} ${shortDate(date)}'),
          findsOneWidget,
        );
        expect(find.textContaining('660 kcal'), findsOneWidget);
        if (!scenario.commit) {
          await tester.tapAt(const Offset(12, 120));
          await pumpFrames(tester, frames: 12);
          expect(find.byType(BottomSheet), findsNothing);
          expect(await db.select(db.mealPlanEntries).get(), isEmpty);
          expect(await db.select(db.recipes).get(), hasLength(2));
          return;
        }

        final Finder portion = find.descendant(
          of: find.byType(BottomSheet).last,
          matching: find.byType(TextField),
        );
        await tester.enterText(portion, '0.5');
        await tools.reach(
          find.text(scenario.days > 0 ? 'Add to plan' : 'Log it'),
        );
        final MealPlanEntryRow entry =
            (await db.select(db.mealPlanEntries).get()).single;
        final MealPlanDayRow day =
            (await db.select(db.mealPlanDays).get()).single;
        expect(entry.refId, variation.id);
        expect(entry.servings, 0.5);
        expect(entry.mealSlot, MealSlot.dinner.name);
        expect(dayKey(day.day), dayKey(date));
        expect(entry.isLogged, scenario.days < 0);
        if (scenario.days < 0) {
          final Map<String, Object?> snapshot =
              jsonDecode(entry.macroSnapshot!) as Map<String, Object?>;
          expect(snapshot['kcal'], 330);
        } else {
          expect(entry.macroSnapshot, isNull);
        }
        expect(icons.titles, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'library variation explicitly saves a new recipe without a diary entry',
    (WidgetTester tester) async {
      final _NoDrawing icons = _NoDrawing();
      final HearthDatabase db = await _openVariation(tester, icons: icons);
      final RecipeRow before = (await db.select(db.recipes).get()).single;
      await SweepTools(tester).reach(find.text('Save new variation'));
      final List<RecipeRow> rows = await db.select(db.recipes).get();
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((RecipeRow row) => row.id == before.id).toJson(),
        before.toJson(),
      );
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      expect(find.byType(BottomSheet), findsNothing);
      expect(icons.titles, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling variation review preserves only the original usual', (
    WidgetTester tester,
  ) async {
    final _NoDrawing icons = _NoDrawing();
    final HearthDatabase db = await _openVariation(tester, icons: icons);
    final RecipeRow before = (await db.select(db.recipes).get()).single;
    final SweepTools tools = SweepTools(tester);
    await tools.reach(find.text('Cancel'));
    await tools.reach(find.text('Discard'));
    expect(
      (await db.select(db.recipes).get()).single.toJson(),
      before.toJson(),
    );
    expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    expect(icons.titles, isEmpty);
  });
}

Future<HearthDatabase> _openVariation(
  WidgetTester tester, {
  DateTime? date,
  required _NoDrawing icons,
  Stream<List<Recipe>>? recipeStream,
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    size: const Size(390, 1000),
    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
    recipes: <Recipe>[savedUsual()],
    recipeStream: recipeStream,
    foods: usualMenuFoods(),
    recipeIcon: icons,
    selectedDate: date,
  );
  final SweepTools tools = SweepTools(tester);
  if (date == null) {
    await tools.tab('Recipes');
    await tools.reach(find.text('Add recipe'));
    await tools.reach(find.text('Eat out'));
  } else {
    await tools.tab('Plan');
    await tools.reach(find.byTooltip('Add to dinner').first);
    await tools.reach(
      find.text(
        calendarDaysBetween(DateTime.now(), date) > 0
            ? 'Plan a restaurant meal'
            : 'Ate out — build it from a menu',
      ),
    );
  }
  await tools.reach(find.text('Corner Kitchen'));
  await tools.reach(find.byKey(const Key('usual-customize-saved-usual')));
  await tools.reach(find.text('Lettuce wrap'));
  await tools.reach(find.byKey(const Key('usual-review-variation')));
  expect(find.byType(RecipeEditorScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
  return db;
}
