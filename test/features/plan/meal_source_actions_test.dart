import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/theme/hearth_spacing.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_detail_screen.dart';
import 'package:hearth/features/recipes/cook_along_screen.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

const String _entryId = 'meal-oats';
const ValueKey<String> _open = ValueKey<String>('meal-open-$_entryId');
const ValueKey<String> _log = ValueKey<String>('meal-log-$_entryId');
const ValueKey<String> _cook = ValueKey<String>('meal-cook-$_entryId');
const String _frozenName = 'Breakfast as logged';

Food _food() => aFood(
  'Oats from the library',
  id: 'food-oats',
  servingOptions: <ServingOption>[
    aServing(
      id: 'current-serving',
      label: '100 g',
      amount: 100,
      unit: Units.gram,
      macros: const Macros(kcal: 380, proteinG: 13, fiberG: 10),
    ),
  ],
);

Recipe _recipe({
  RecipeKind kind = RecipeKind.cooked,
  bool withDirections = true,
  bool deleted = false,
}) => aRecipe(
  id: 'recipe-oats',
  title: 'Warm breakfast oats',
  servings: 6,
  kind: kind,
  isDeleted: deleted,
  ingredients: <RecipeIngredient>[
    anIngredient('Oats', amount: 600, unit: Units.gram, foodId: 'food-oats'),
  ],
  steps: <RecipeStep>[
    if (withDirections) aStep('Simmer the oats gently until creamy.'),
  ],
);

MealPlanEntry _meal({
  PlanRefType type = PlanRefType.recipe,
  bool logged = false,
  String? servingOptionId,
}) {
  final MealPlanEntry entry = MealPlanEntry(
    id: _entryId,
    dayId: 'day-1',
    slot: MealSlot.breakfast,
    refType: type,
    refId: type == PlanRefType.recipe ? 'recipe-oats' : 'food-oats',
    // This is the person's portion, deliberately far from the cooking yield.
    servings: 0.5,
    servingOptionId: servingOptionId,
  );
  return logged
      ? entry.log(
          liveMacros: const Macros(kcal: 240, proteinG: 12, fiberG: 4),
          coverage: const NutrientCoverage.notRecorded(),
          at: DateTime.utc(2026, 9, 1, 8),
          label: _frozenName,
        )
      : entry;
}

Future<HearthDatabase> _day(
  WidgetTester tester, {
  PlanRefType type = PlanRefType.recipe,
  bool logged = false,
  Recipe? recipe,
  List<Food>? foods,
  String? servingOptionId,
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => pumpHearthApp(
  tester,
  launchTarget: LaunchTarget.today,
  recipes: <Recipe>[recipe ?? _recipe()],
  foods: foods ?? <Food>[_food()],
  entries: <MealPlanEntry>[
    _meal(type: type, logged: logged, servingOptionId: servingOptionId),
  ],
  size: size,
  textScale: textScale,
  brightness: brightness,
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await pumpFrames(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder.hitTestable());
  await pumpFrames(tester, frames: 12);
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await pumpFrames(tester, frames: 12);
}

Future<List<MealPlanEntryRow>> _stored(HearthDatabase db) =>
    db.select(db.mealPlanEntries).get();

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  bool hasFocus() {
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    final Element element = tester.element(target);
    if (focused == element) return true;
    bool found = false;
    (focused as Element).visitAncestorElements((Element ancestor) {
      found = ancestor == element;
      return !found;
    });
    return found;
  }

  for (int i = 0; i < 50 && !hasFocus(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(hasFocus(), isTrue, reason: 'the action must be keyboard reachable');
}

void main() {
  for (final PlanRefType type in PlanRefType.values) {
    for (final bool logged in <bool>[false, true]) {
      testWidgets(
        'opening a ${logged ? 'logged' : 'planned'} ${type.name} preserves '
        'the whole meal record',
        (WidgetTester tester) async {
          final HearthDatabase db = await _day(
            tester,
            type: type,
            logged: logged,
          );
          final List<MealPlanEntryRow> before = await _stored(db);
          final String title = logged
              ? _frozenName
              : type == PlanRefType.recipe
              ? 'Warm breakfast oats'
              : 'Oats from the library';
          await _tap(tester, find.text(title));

          if (type == PlanRefType.recipe) {
            expect(find.byType(RecipeDetailScreen), findsOneWidget);
            expect(find.text('Warm breakfast oats'), findsWidgets);
          } else {
            final FoodDetailScreen detail = tester.widget<FoodDetailScreen>(
              find.byType(FoodDetailScreen),
            );
            expect(detail.foodId, 'food-oats');
            expect(find.text('Oats from the library'), findsWidgets);
            expect(find.byType(TextField), findsNothing);
          }
          expect(await _stored(db), before);
          await _back(tester);
          expect(await _stored(db), before);
          expect(find.text(title), findsOneWidget);
          expect(find.byKey(_log), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Cook opens the full saved yield, independent of my portion', (
    WidgetTester tester,
  ) async {
    final Recipe original = _recipe();
    final HearthDatabase db = await _day(tester, recipe: original);
    final List<MealPlanEntryRow> before = await _stored(db);
    expect(find.text('Full recipe · 6 servings'), findsOneWidget);

    await _tap(tester, find.byKey(_cook));

    final CookAlongScreen cook = tester.widget<CookAlongScreen>(
      find.byType(CookAlongScreen),
    );
    expect(cook.recipe, same(original));
    expect(cook.recipe.servings, 6);
    expect(cook.recipe.allIngredients.single.quantity!.canonicalAmount, 600);
    expect(find.text('Simmer the oats gently until creamy.'), findsWidgets);
    expect(await _stored(db), before);
    await _tap(tester, find.byTooltip('Finish cooking'));
    expect(await _stored(db), before);
    expect(find.byKey(_open), findsOneWidget);
    expect(find.byTooltip('Log Warm breakfast oats'), findsOneWidget);
  });

  testWidgets('restaurant meals have no direct Cook', (
    WidgetTester tester,
  ) async {
    await _day(tester, recipe: _recipe(kind: RecipeKind.eatenOut));
    expect(find.byKey(_cook), findsNothing);
    expect(find.textContaining('Restaurant meal · planned'), findsOneWidget);
    await _tap(tester, find.byKey(_open));
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    await _back(tester);
    expect(find.byKey(_cook), findsNothing);
  });

  testWidgets('food rows have no direct Cook', (WidgetTester tester) async {
    await _day(tester, type: PlanRefType.food);
    expect(find.byKey(_cook), findsNothing);
    expect(find.textContaining('Food · planned'), findsOneWidget);
  });

  testWidgets('logged cooked recipes have no direct Cook', (
    WidgetTester tester,
  ) async {
    await _day(tester, logged: true);
    expect(find.byKey(_cook), findsNothing);
    expect(find.byTooltip('Unlog $_frozenName'), findsOneWidget);
  });

  testWidgets('a recipe without directions explains why Cook cannot start', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await _day(
      tester,
      recipe: _recipe(withDirections: false),
    );
    final List<MealPlanEntryRow> before = await _stored(db);
    await _tap(tester, find.byKey(_cook));
    expect(find.byType(CookAlongScreen), findsNothing);
    expect(find.textContaining('no directions to cook along'), findsOneWidget);
    expect(await _stored(db), before);
  });

  testWidgets('a removed serving still opens the current food by identity', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await _day(
      tester,
      type: PlanRefType.food,
      servingOptionId: 'removed-serving',
    );
    final List<MealPlanEntryRow> before = await _stored(db);
    expect(find.text('Oats from the library'), findsOneWidget);
    expect(find.text('Removed food'), findsNothing);
    expect(find.textContaining('serving no longer available'), findsOneWidget);
    expect(find.text('Nutrition unavailable'), findsOneWidget);
    await _tap(tester, find.byKey(_open));
    final FoodDetailScreen detail = tester.widget<FoodDetailScreen>(
      find.byType(FoodDetailScreen),
    );
    expect(detail.foodId, 'food-oats');
    expect(detail.servingOptionId, 'removed-serving');
    expect(find.text('Oats from the library'), findsWidgets);
    expect(await _stored(db), before);
    await _back(tester);
    expect(await _stored(db), before);
  });

  for (final PlanRefType type in PlanRefType.values) {
    for (final bool deleted in <bool>[false, true]) {
      testWidgets(
        '${deleted ? 'deleted' : 'missing'} ${type.name} explains its absence '
        'and keeps the frozen log',
        (WidgetTester tester) async {
          final HearthDatabase db = await pumpHearthApp(
            tester,
            launchTarget: LaunchTarget.today,
            recipes: <Recipe>[
              if (deleted && type == PlanRefType.recipe) _recipe(deleted: true),
            ],
            foods: <Food>[
              if (deleted && type == PlanRefType.food) _food().withDeleted(),
            ],
            entries: <MealPlanEntry>[_meal(type: type, logged: true)],
          );
          final List<MealPlanEntryRow> before = await _stored(db);
          expect(find.text(_frozenName), findsOneWidget);
          expect(find.byKey(_cook), findsNothing);
          expect(find.textContaining('source no longer'), findsOneWidget);
          await _tap(tester, find.byKey(_open));
          expect(find.textContaining('no longer'), findsWidgets);
          expect(await _stored(db), before);
          await _back(tester);
          expect(await _stored(db), before);
          expect(find.byTooltip('Unlog $_frozenName'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('Open, Log and Cook expose separate named semantic actions', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _day(tester);
    final SemanticsNode open = tester.getSemantics(find.byKey(_open));
    final SemanticsNode log = tester.getSemantics(find.byKey(_log));
    final SemanticsNode cook = tester.getSemantics(find.byKey(_cook));
    expect(open.label, startsWith('Open recipe Warm breakfast oats.'));
    expect(open.hint, 'Shows current library details');
    expect(log.tooltip, 'Log Warm breakfast oats');
    expect(cook.label, 'Cook Warm breakfast oats, full recipe');
    expect(<int>{open.id, log.id, cook.id}, hasLength(3));
    for (final SemanticsNode node in <SemanticsNode>[open, log, cook]) {
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }
    semantics.dispose();
  });

  testWidgets('keyboard opening and cooking stay separate from logging', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await _day(tester);
    final List<MealPlanEntryRow> before = await _stored(db);
    await _tabTo(tester, find.byKey(_open));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester, frames: 12);
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(await _stored(db), before);
    await _back(tester);

    await _tabTo(tester, find.byKey(_cook));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester, frames: 12);
    expect(find.byType(CookAlongScreen), findsOneWidget);
    expect(await _stored(db), before);
    await _tap(tester, find.byTooltip('Finish cooking'));

    await _tabTo(tester, find.byKey(_log));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester, frames: 12);
    expect((await _stored(db)).single.isLogged, isTrue);
    expect(find.byType(RecipeDetailScreen), findsNothing);
    expect(find.byType(CookAlongScreen), findsNothing);
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'meal actions and options fit 320×568 at 3× text in ${brightness.name}',
      (WidgetTester tester) async {
        final HearthDatabase db = await _day(
          tester,
          size: const Size(320, 568),
          textScale: 3,
          brightness: brightness,
        );
        final List<MealPlanEntryRow> before = await _stored(db);
        for (final Key key in <Key>[_open, _log, _cook]) {
          final Finder action = find.byKey(key);
          await _reveal(tester, action);
          final Size size = tester.getSize(action);
          expect(size.width, greaterThanOrEqualTo(HearthTouch.minTarget));
          expect(size.height, greaterThanOrEqualTo(HearthTouch.minTarget));
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await _tap(tester, find.byKey(_open));
        expect(find.byType(RecipeDetailScreen), findsOneWidget);
        await _back(tester);
        await _tap(tester, find.byKey(_cook));
        expect(find.byType(CookAlongScreen), findsOneWidget);
        await _tap(tester, find.byTooltip('Finish cooking'));
        expect(await _stored(db), before);

        await _tap(tester, find.byTooltip('Edit Warm breakfast oats'));
        for (final String label in <String>[
          'Edit portion',
          'Move to another day or meal…',
          'Plan this again…',
          'Remove from this day',
        ]) {
          final Finder action = find.widgetWithText(ListTile, label);
          await _reveal(tester, action);
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        expect(await _stored(db), before);
      },
    );
  }
}
