import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/swipe_to_delete.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The shopping list on screen (spec §5.7).
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
            amount: 1,
            unit: Units.pound,
            sectionId: 's1',
          ),
          anIngredient('cumin', amount: 2, unit: Units.tsp, sectionId: 's1'),
        ],
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
    await pumpHearthApp(tester, recipes: <Recipe>[chilli()], entries: entries);
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
  }

  Future<void> build(WidgetTester tester) async {
    await tester.tap(find.text('Build from the plan'));
    await pumpFrames(tester, frames: 20);
  }

  testWidgets('an empty list says what it would be built from', (
    WidgetTester tester,
  ) async {
    await openShopping(tester);

    expect(find.text('Nothing on the list yet.'), findsOneWidget);
    expect(find.text('Shopping for'), findsOneWidget);
  });

  testWidgets('building pulls the plan in, without the spices', (
    WidgetTester tester,
  ) async {
    // Seasonings are bought on their own rhythm, so cumin stays off by
    // default even though the recipe calls for it.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    expect(find.text('ground beef'), findsOneWidget);
    expect(find.text('cumin'), findsNothing);
  });

  testWidgets('and the spices come when asked for', (
    WidgetTester tester,
  ) async {
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await tester.tap(find.byType(Switch));
    await pumpFrames(tester);
    await build(tester);

    expect(find.text('cumin'), findsOneWidget);
  });

  testWidgets('tapping a line ticks it off, and says so in words', (
    WidgetTester tester,
  ) async {
    // Never colour alone (§6.3): a done line carries the tick mark itself.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    await tester.tap(find.text('ground beef'));
    await pumpFrames(tester, frames: 20);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('an amount can be changed without touching the recipe', (
    WidgetTester tester,
  ) async {
    // Brendan's case: 1 lb of beef, but he wants 2 because that is how it is
    // sold. The recipe still calls for 1.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    await tester.tap(find.text('1 lb'));
    await pumpFrames(tester, frames: 10);
    await tester.enterText(
      find.widgetWithText(TextField, 'How much to get'),
      '2',
    );
    await tester.tap(find.text('Done'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('2 lb'), findsOneWidget);
    expect(find.textContaining('recipes call for 1 lb'), findsOneWidget);
    // Marked as changed by hand, with an icon rather than colour alone.
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('saying what you already have changes what to buy', (
    WidgetTester tester,
  ) async {
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    await tester.tap(find.text('1 lb'));
    await pumpFrames(tester, frames: 10);
    await tester.enterText(
      find.widgetWithText(TextField, 'How much to get'),
      '2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Leave empty if none'),
      '1',
    );
    await tester.tap(find.text('Done'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('1 lb'), findsOneWidget);
    expect(find.textContaining('have 1 lb'), findsOneWidget);
  });

  testWidgets('an item added by hand survives a rebuild', (
    WidgetTester tester,
  ) async {
    // The plan never put coffee here, so the plan gets no vote on removing it.
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    await tester.tap(find.byTooltip('Add an item by hand'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextField).last, 'Coffee');
    await tester.tap(find.text('Add'));
    await pumpFrames(tester, frames: 20);
    expect(find.text('Coffee'), findsOneWidget);

    await build(tester);
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('a tick survives a rebuild too', (WidgetTester tester) async {
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);
    await tester.tap(find.text('ground beef'));
    await pumpFrames(tester, frames: 20);

    await build(tester);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('the export says what it can do before you press it', (
    WidgetTester tester,
  ) async {
    // A button named after a shop that opens a search page rather than
    // filling a basket should say so before it is pressed. (It says Hearth
    // lacks the product codes — not that Walmart lacks a cart URL, which was
    // wrong: walmart.io/docs/atc/v1/add-to-cart is open to anyone.)
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);

    await tester.tap(find.text('Take it shopping'));
    await pumpFrames(tester, frames: 10);

    expect(find.text('Copy the list'), findsOneWidget);
    expect(find.textContaining('does not know'), findsOneWidget);
    expect(find.textContaining('1 item still to buy'), findsOneWidget);
  });

  testWidgets('and it leaves out what you have already ticked', (
    WidgetTester tester,
  ) async {
    await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
    await build(tester);
    await tester.tap(find.text('ground beef'));
    await pumpFrames(tester, frames: 20);

    await tester.tap(find.text('Take it shopping'));
    await pumpFrames(tester, frames: 10);

    expect(find.text('Everything on the list is ticked off.'), findsOneWidget);
    expect(find.text('Copy the list'), findsNothing);
  });

  group('filling a basket (spec §5.7)', () {
    Food beefAt(String? itemId, {Quantity? pack}) => Food(
      id: 'f-beef',
      householdId: 'household-1',
      name: 'Ground beef',
      source: FoodSource.manual,
      servingOptions: const <ServingOption>[],
      walmartItemId: itemId,
      packSize: pack,
    );

    /// The chilli's beef, matched to a food so the line carries a foodId.
    Recipe chilliWith(String foodId) => aRecipe(
      id: 'r-chilli',
      title: 'Chilli',
      servings: 4,
      sections: <RecipeSection>[
        aSection(
          id: 's1',
          ingredients: <RecipeIngredient>[
            anIngredient(
              'ground beef',
              amount: 1,
              unit: Units.pound,
              sectionId: 's1',
              foodId: foodId,
            ),
          ],
        ),
      ],
    );

    Future<void> openExport(WidgetTester tester, List<Food> foods) async {
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[chilliWith('f-beef')],
        foods: foods,
        entries: <MealPlanEntry>[tonight()],
      );
      await tester.tap(find.text('Shopping').last);
      await pumpFrames(tester);
      await build(tester);
      await tester.tap(find.text('Take it shopping'));
      await pumpFrames(tester, frames: 10);
    }

    testWidgets('the basket is offered once a product is saved', (
      WidgetTester tester,
    ) async {
      await openExport(tester, <Food>[beefAt('10450479')]);

      expect(find.textContaining('Fill a Walmart basket'), findsOneWidget);
      expect(
        find.textContaining('Everything left has a saved product'),
        findsOneWidget,
      );
    });

    testWidgets('and not offered when nothing has one', (
      WidgetTester tester,
    ) async {
      // Most foods will never carry a product code, and a button that can
      // only fail is worse than no button.
      await openExport(tester, <Food>[beefAt(null)]);

      expect(find.textContaining('Fill a Walmart basket'), findsNothing);
      expect(find.text('Copy the list'), findsOneWidget);
    });

    testWidgets('copying stays available either way', (
      WidgetTester tester,
    ) async {
      // Walmart drops you on its homepage if any item will not add, so the
      // copy is what makes a failed basket survivable.
      await openExport(tester, <Food>[beefAt('10450479')]);

      expect(find.text('Copy the list'), findsOneWidget);
    });
  });

  group('taking a line off the list (spec §5.7)', () {
    testWidgets('a swipe uncovers Delete, and the button does the work', (
      WidgetTester tester,
    ) async {
      // Two deliberate actions, which is `SwipeToDelete`'s whole shape and
      // the reason this list uses it rather than a Dismissible of its own:
      // one flick removing a line while you scroll one-handed in a shop is
      // exactly the accident it exists to prevent.
      await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
      await build(tester);
      expect(find.text('ground beef'), findsOneWidget);
      // The button is behind the row all along; what the swipe changes is
      // whether it can be pressed.
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Delete'))
            .onPressed,
        isNull,
      );

      await tester.drag(find.text('ground beef'), const Offset(-200, 0));
      await pumpFrames(tester, frames: 20);

      // The swipe on its own removes nothing.
      expect(find.text('ground beef'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await pumpFrames(tester, frames: 20);
      expect(find.text('ground beef'), findsNothing);
    });

    testWidgets('and Undo puts it back', (WidgetTester tester) async {
      await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
      await build(tester);

      await tester.drag(find.text('ground beef'), const Offset(-200, 0));
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.text('Delete'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Deleted ground beef'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('ground beef'), findsOneWidget);
    });

    testWidgets('a long press no longer deletes — it belongs to the drag', (
      WidgetTester tester,
    ) async {
      // Removal used to hang off `onLongPress`, competing with the reorder
      // drag that `buildDefaultDragHandles` binds to the same gesture on a
      // phone. Dragging the list into shop order is the point of §5.7's
      // ordering, so the gesture went back to it.
      await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
      await build(tester);

      await tester.longPress(find.text('ground beef'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('ground beef'), findsOneWidget);
    });

    testWidgets('and there is a path that needs no gesture at all', (
      WidgetTester tester,
    ) async {
      // A swipe is unreachable by a screen reader and hard for anyone who
      // cannot make a confident horizontal drag (§6.3).
      await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
      await build(tester);

      await tester.tap(find.text('1 lb'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Remove from list'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('ground beef'), findsNothing);
      // Same undo as the swipe, from the same one place.
      expect(find.text('Deleted ground beef'), findsOneWidget);
    });
  });

  group('undoing a deletion and nothing else (spec §5.7)', () {
    /// Adds a manual item, so there is a second line to change.
    Future<void> addByHand(WidgetTester tester, String name) async {
      await tester.tap(find.byTooltip('Add an item by hand'));
      await pumpFrames(tester);
      await tester.enterText(find.byType(TextField).last, name);
      await tester.tap(find.text('Add'));
      await pumpFrames(tester, frames: 20);
    }

    Future<void> swipeAndDelete(WidgetTester tester, String name) async {
      await tester.drag(find.text(name), const Offset(-200, 0));
      await pumpFrames(tester, frames: 20);
      // The Delete button of *that* row: every row has one behind it, and
      // only the swiped-open one can be pressed.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text(name),
            matching: find.byType(SwipeToDelete),
          ),
          matching: find.widgetWithText(TextButton, 'Delete'),
        ),
      );
      await pumpFrames(tester, frames: 20);
    }

    Future<void> undo(WidgetTester tester) async {
      await tester.tap(find.text('Undo'));
      await pumpFrames(tester, frames: 20);
    }

    /// Opens a list of two lines: the plan's beef and a manual coffee.
    Future<void> openTwo(WidgetTester tester) async {
      await openShopping(tester, entries: <MealPlanEntry>[tonight()]);
      await build(tester);
      await addByHand(tester, 'Coffee');
    }

    testWidgets('a tick made after the deletion survives the Undo', (
      WidgetTester tester,
    ) async {
      // The shop is the whole point: beef comes off the list, the next aisle
      // gets ticked, and only then does somebody notice the beef was wanted
      // after all. Undo is that one line coming back — never the list as it
      // stood before, which would quietly un-tick what has been bought since.
      await openTwo(tester);

      await swipeAndDelete(tester, 'ground beef');
      await tester.tap(find.text('Coffee'));
      await pumpFrames(tester, frames: 20);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await undo(tester);

      expect(find.text('ground beef'), findsOneWidget);
      expect(
        find.byIcon(Icons.check_circle),
        findsOneWidget,
        reason: 'the coffee was ticked after the deletion, so Undo leaves it',
      );
    });

    testWidgets('and so does an item added after it', (
      WidgetTester tester,
    ) async {
      await openTwo(tester);

      await swipeAndDelete(tester, 'ground beef');
      await addByHand(tester, 'Paper towels');
      await undo(tester);

      expect(find.text('ground beef'), findsOneWidget);
      expect(find.text('Paper towels'), findsOneWidget);
    });

    testWidgets('the amount sheet’s Remove undoes the same way', (
      WidgetTester tester,
    ) async {
      // The other door onto the same deletion (§6.3's gesture-free path), and
      // it used to hand back its own stale copy of the list.
      await openTwo(tester);

      await tester.tap(find.text('1 lb'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Remove from list'));
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.text('Coffee'));
      await pumpFrames(tester, frames: 20);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await undo(tester);

      expect(find.text('ground beef'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('and the restored line keeps its place in the shop', (
      WidgetTester tester,
    ) async {
      // The order is the route you walk, so a line that comes back at the
      // bottom of the list has not really come back.
      await openTwo(tester);
      final Offset was = tester.getCenter(find.text('ground beef'));

      await swipeAndDelete(tester, 'ground beef');
      await undo(tester);

      expect(tester.getCenter(find.text('ground beef')), was);
    });

    testWidgets('and a line added back by hand is not doubled by the Undo', (
      WidgetTester tester,
    ) async {
      // Same key, back on the list already. The one standing there is the
      // more recent decision, so it stays and Undo has nothing to do.
      await openTwo(tester);
      await swipeAndDelete(tester, 'Coffee');

      await addByHand(tester, 'Coffee');
      await undo(tester);

      expect(find.text('Coffee'), findsOneWidget);
    });
  });
}
