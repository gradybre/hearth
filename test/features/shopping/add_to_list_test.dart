import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Filling the list by adding to it (spec §5.7, as amended).
///
/// The flow the shopping tab is built around now: open it, say what you are
/// going to cook, and Hearth works out what to buy. Building from a stretch
/// of the plan is still there and still tested — it is behind `Manage list`,
/// because it is one way to fill a list rather than what a list is.
void main() {
  Recipe chilli() => aRecipe(
    id: 'r-chilli',
    title: 'Chilli',
    servings: 4,
    sections: <RecipeSection>[
      aSection(
        id: 's1',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'ground beef',
            amount: 2,
            unit: Units.pound,
            sectionId: 's1',
          ),
          anIngredient(
            'kidney beans',
            amount: 1,
            unit: Units.can,
            sectionId: 's1',
          ),
        ],
      ),
    ],
  );

  Food yoghurt() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'o1',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 160, proteinG: 15, carbG: 8, fatG: 8),
      ),
    ],
  );

  MealPlanEntry tonight() => const MealPlanEntry(
    id: 'e1',
    dayId: 'day-1',
    slot: MealSlot.dinner,
    refType: PlanRefType.recipe,
    refId: 'r-chilli',
    servings: 4,
  );

  Future<void> openShopping(
    WidgetTester tester, {
    List<MealPlanEntry> entries = const <MealPlanEntry>[],
  }) async {
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[chilli()],
      foods: <Food>[yoghurt()],
      entries: entries,
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester, frames: 12);
  }

  /// Opens the add sheet, from whichever shape the screen is in — the empty
  /// card and the action bar over a list both carry it.
  Future<void> openAdd(WidgetTester tester) async {
    await tester.tap(find.text('Add to list').last);
    await pumpFrames(tester, frames: 16);
  }

  /// Types into the sheet's search field.
  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).last, text);
    await pumpFrames(tester, frames: 8);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('Add to the list'));
    await pumpFrames(tester, frames: 20);
  }

  Future<void> manage(WidgetTester tester) async {
    await tester.tap(find.text('Manage list'));
    await pumpFrames(tester, frames: 16);
  }

  testWidgets('an empty list leads with adding, not with a date range', (
    WidgetTester tester,
  ) async {
    // The screen used to open on a date picker set in a title face. The dates
    // belong to the build from the plan, which is one of the two ways in.
    await openShopping(tester);

    expect(find.text('Add to list'), findsOneWidget);
    expect(find.text('Build from the plan'), findsOneWidget);
    expect(
      find.text('Nothing on the list yet.'),
      findsOneWidget,
      reason: 'the empty state still says what the screen is for',
    );
  });

  testWidgets('a recipe goes on as its ingredients', (
    WidgetTester tester,
  ) async {
    await openShopping(tester);
    await openAdd(tester);

    // Offered before anything is typed: the thing you are shopping for is
    // usually the thing you were just looking at.
    await tester.tap(find.text('Chilli'));
    await pumpFrames(tester, frames: 12);

    // At the yield it was written for, until somebody says otherwise.
    expect(find.text('4 servings'), findsOneWidget);
    await confirm(tester);

    expect(find.text('ground beef'), findsOneWidget);
    expect(find.text('2 lb'), findsOneWidget);
    expect(find.text('kidney beans'), findsOneWidget);
  });

  testWidgets('and the stepper scales what goes on', (
    WidgetTester tester,
  ) async {
    await openShopping(tester);
    await openAdd(tester);
    await tester.tap(find.text('Chilli'));
    await pumpFrames(tester, frames: 12);

    // Down to two servings: half a four-serving chilli is half the beef.
    await tester.tap(find.byTooltip('Fewer'));
    await pumpFrames(tester, frames: 4);
    await tester.tap(find.byTooltip('Fewer'));
    await pumpFrames(tester, frames: 4);
    await tester.tap(find.byTooltip('Fewer'));
    await pumpFrames(tester, frames: 4);
    await tester.tap(find.byTooltip('Fewer'));
    await pumpFrames(tester, frames: 4);
    expect(find.text('2 servings'), findsOneWidget);

    await confirm(tester);
    expect(find.text('1 lb'), findsOneWidget);
  });

  testWidgets('a food goes on as itself, in its own serving', (
    WidgetTester tester,
  ) async {
    // Not through a recipe: "I need yoghurt" is a whole errand on its own.
    await openShopping(tester);
    await openAdd(tester);
    await search(tester, 'yogh');

    await tester.tap(find.text('Greek yoghurt'));
    await pumpFrames(tester, frames: 12);
    expect(find.text('1 × 170 g pot'), findsOneWidget);

    await confirm(tester);
    expect(find.text('Greek yoghurt'), findsOneWidget);
    // 170 g, said the way the list says every weight (spec §5.2's display
    // rules, not this sheet's): the stepper counts pots, the line counts what
    // you are carrying home.
    expect(find.text('6 oz'), findsOneWidget);
  });

  testWidgets('and something the library has never heard of goes on too', (
    WidgetTester tester,
  ) async {
    // Most of a shopping list is this. The old name-only dialog was a
    // separate door for it; one sheet is one act.
    await openShopping(tester);
    await openAdd(tester);
    await search(tester, 'Paper towels');

    await tester.tap(find.text('Add "Paper towels" as an item'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Paper towels'), findsOneWidget);
    expect(find.textContaining('added by hand'), findsOneWidget);
  });

  testWidgets('adding the same item twice says so rather than doing nothing', (
    WidgetTester tester,
  ) async {
    // The list simply would not change, which looks exactly like a button
    // that did not work.
    await openShopping(tester);
    await openAdd(tester);
    await search(tester, 'Coffee');
    await tester.tap(find.text('Add "Coffee" as an item'));
    await pumpFrames(tester, frames: 20);

    await openAdd(tester);
    await search(tester, 'Coffee');
    await tester.tap(find.text('Add "Coffee" as an item'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Coffee is already on the list.'), findsOneWidget);
  });

  testWidgets('a recipe added twice is two dinners, not a correction', (
    WidgetTester tester,
  ) async {
    // Two occasions is two lots of ingredients (spec §5.7, as amended). The
    // second ask sums rather than replacing, and rather than listing the
    // recipe twice.
    await openShopping(tester);
    await openAdd(tester);
    await tester.tap(find.text('Chilli'));
    await pumpFrames(tester, frames: 12);
    await confirm(tester);

    await openAdd(tester);
    await tester.tap(find.text('Chilli'));
    await pumpFrames(tester, frames: 12);
    await confirm(tester);

    expect(find.text('ground beef'), findsOneWidget);
    expect(find.text('4 lb'), findsOneWidget);
  });

  testWidgets('and a recipe in the plan does not absorb one added by hand', (
    WidgetTester tester,
  ) async {
    // The same chilli, twice over: once because it is planned for tonight and
    // once because somebody is cooking it again at the weekend. A list that
    // reported 2 lb would send them home short.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await openAdd(tester);
    await tester.tap(find.text('Chilli'));
    await pumpFrames(tester, frames: 12);
    await confirm(tester);

    await manage(tester);
    await tester.tap(find.text('Build from the plan'));
    await pumpFrames(tester, frames: 24);

    expect(find.text('4 lb'), findsOneWidget);
  });

  group('taking a source back off (spec §5.7)', () {
    testWidgets('the manage sheet says what put the list there', (
      WidgetTester tester,
    ) async {
      await openShopping(tester);
      await openAdd(tester);
      await tester.tap(find.text('Chilli'));
      await pumpFrames(tester, frames: 12);
      await confirm(tester);

      await manage(tester);

      expect(find.text('What is on it'), findsOneWidget);
      expect(find.text('Chilli'), findsOneWidget);
      expect(find.text('4 servings · 2 lines'), findsOneWidget);
    });

    testWidgets('and taking a recipe off takes its ingredients with it', (
      WidgetTester tester,
    ) async {
      await openShopping(tester);
      await openAdd(tester);
      await tester.tap(find.text('Chilli'));
      await pumpFrames(tester, frames: 12);
      await confirm(tester);

      await manage(tester);
      await tester.tap(find.text('Take off'));
      await pumpFrames(tester, frames: 24);

      // The sheet stays open and updates: taking two recipes off in a row is
      // one visit to it.
      expect(find.text('What is on it'), findsNothing);
      await tester.tapAt(const Offset(200, 40));
      await pumpFrames(tester, frames: 20);
      expect(find.text('ground beef'), findsNothing);
      expect(find.text('Nothing on the list yet.'), findsOneWidget);
    });

    testWidgets('but a line you ticked off survives it', (
      WidgetTester tester,
    ) async {
      // A tick is a decision about the shop, not about the recipe that
      // prompted it — the same rule a rebuild follows.
      await openShopping(tester);
      await openAdd(tester);
      await tester.tap(find.text('Chilli'));
      await pumpFrames(tester, frames: 12);
      await confirm(tester);

      await tester.tap(find.text('ground beef'));
      await pumpFrames(tester, frames: 20);

      await manage(tester);
      await tester.tap(find.text('Take off'));
      await pumpFrames(tester, frames: 24);
      await tester.tapAt(const Offset(200, 40));
      await pumpFrames(tester, frames: 20);

      expect(find.text('ground beef'), findsOneWidget);
      expect(find.text('kidney beans'), findsNothing);
    });
  });

  group('clearing the list (spec §5.7)', () {
    Future<void> fill(WidgetTester tester) async {
      await openShopping(tester);
      await openAdd(tester);
      await tester.tap(find.text('Chilli'));
      await pumpFrames(tester, frames: 12);
      await confirm(tester);
    }

    testWidgets('it asks before it happens', (WidgetTester tester) async {
      await fill(tester);
      await manage(tester);
      await tester.tap(find.text('Clear the list'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Clear the list?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('ground beef'), findsOneWidget);
    });

    testWidgets('and clears it when told to', (WidgetTester tester) async {
      await fill(tester);
      await manage(tester);
      await tester.tap(find.text('Clear the list'));
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.text('Clear it'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('ground beef'), findsNothing);
      expect(find.text('Nothing on the list yet.'), findsOneWidget);
    });

    testWidgets('and Undo puts the whole list back', (
      WidgetTester tester,
    ) async {
      await fill(tester);
      await manage(tester);
      await tester.tap(find.text('Clear the list'));
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.text('Clear it'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Cleared 2 items'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await pumpFrames(tester, frames: 24);

      expect(find.text('ground beef'), findsOneWidget);
      expect(find.text('kidney beans'), findsOneWidget);
    });

    testWidgets('and what was added since the clear stays', (
      WidgetTester tester,
    ) async {
      // The rule a single-line undo already follows: anything standing on the
      // list when Undo is tapped is somebody's newer decision, and a restore
      // of the snapshot would quietly delete it.
      await fill(tester);
      await manage(tester);
      await tester.tap(find.text('Clear the list'));
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.text('Clear it'));
      await pumpFrames(tester, frames: 20);

      await openAdd(tester);
      await search(tester, 'Paper towels');
      await tester.tap(find.text('Add "Paper towels" as an item'));
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.text('Undo'));
      await pumpFrames(tester, frames: 24);

      expect(find.text('Paper towels'), findsOneWidget);
      expect(find.text('ground beef'), findsOneWidget);
    });
  });
}
