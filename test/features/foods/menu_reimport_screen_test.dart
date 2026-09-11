import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/foods/menu_reimport.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Importing a menu that has moved on (review N08).
///
/// The ids already made a second import update rather than duplicate. What
/// they could not do was notice what the second import leaves *behind*: a
/// dish whose portion changed saves as a second food and the old one stays on
/// the menu for ever, which is how a restaurant comes to have two of
/// everything.
void main() {
  /// A menu food saved the way the importer saves one — with the id derived
  /// from what identifies the row, which is what makes a second import
  /// update it rather than add a second copy.
  Food onTheMenu({
    String name = 'Harvest Bowl',
    // A pasted line with no heading above it has no section, and the
    // importer formats "1 item" as "1" — both are part of the id, so a
    // fixture that guesses either is a different food.
    String? section,
    String portion = '1',
    double amount = 1,
  }) {
    final String id = menuFoodId(
      restaurant: 'Chopt',
      name: name,
      portion: portion,
      section: section,
    );
    return aFood(
      name,
      id: id,
      brand: 'Chopt',
      source: FoodSource.restaurant,
      menuGroup: section,
      servingOptions: <ServingOption>[
        aServing(
          id: '$id-s',
          amount: amount,
          unit: Units.item,
          macros: const Macros(kcal: 690, proteinG: 26, carbG: 78, fatG: 30),
        ),
      ],
    );
  }

  Future<HearthDatabase> openImporter(
    WidgetTester tester, {
    List<Food> foods = const <Food>[],
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      size: size,
      textScale: scale,
      foods: foods,
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Add recipe'));
    await pumpFrames(tester, frames: 12);
    // At three times the text the sheet's rows run past the fold, and a lazy
    // list has not built the last of them at all.
    if (find.text('Eat out').evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text('Eat out'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await pumpFrames(tester);
    }
    await tester.ensureVisible(find.text('Eat out'));
    await pumpFrames(tester);
    await tester.tap(find.text('Eat out'));
    await pumpFrames(tester, frames: 12);
    // "Paste a menu" is the empty state's wording; once a restaurant is
    // saved the same door is called "Add restaurant" (review §7.6).
    final Finder door = find.text(
      foods.isEmpty ? 'Paste a menu' : 'Add restaurant',
    );
    if (door.evaluate().isEmpty) {
      // A lazy list has not built it yet, which is what three times the text
      // on a 320-point phone does to a screen with a restaurant on it.
      await tester.scrollUntilVisible(
        door,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await pumpFrames(tester);
    }
    await tester.ensureVisible(door);
    await pumpFrames(tester);
    await tester.tap(door);
    await pumpFrames(tester, frames: 12);
    return db;
  }

  /// Names the restaurant and pastes a menu.
  Future<void> pasteFor(
    WidgetTester tester,
    String restaurant,
    String menu,
  ) async {
    await tester.enterText(find.byType(TextField).first, restaurant);
    await pumpFrames(tester);
    if (find.byType(TextField).evaluate().length < 2) {
      // The paste box sits below the restaurant field, and at large text a
      // lazy list has not built it yet.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
      await pumpFrames(tester, frames: 12);
    }
    await tester.enterText(find.byType(TextField).at(1), menu);
    await pumpFrames(tester, frames: 12);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.textContaining('Save '));
    await pumpFrames(tester);
    await tester.tap(find.textContaining('Save '));
    await pumpFrames(tester, frames: 20);
  }

  testWidgets('a first import asks nothing', (WidgetTester tester) async {
    await openImporter(tester);
    await pasteFor(tester, 'Chopt', 'Harvest Bowl, 1 item, 690, 26, 78, 30');

    await save(tester);

    expect(find.text('This menu has moved on'), findsNothing);
  });

  testWidgets('and so does one that says exactly the same thing', (
    WidgetTester tester,
  ) async {
    // The ids already made this update in place. Nothing is left behind, so
    // there is nothing to ask about.
    await openImporter(tester, foods: <Food>[onTheMenu()]);
    await pasteFor(tester, 'Chopt', 'Harvest Bowl, 1 item, 690, 26, 78, 30');

    await save(tester);

    expect(find.text('This menu has moved on'), findsNothing);
  });

  group('when the menu has moved on', () {
    testWidgets('a dropped dish is named before anything is written', (
      WidgetTester tester,
    ) async {
      await openImporter(
        tester,
        foods: <Food>[
          onTheMenu(),
          onTheMenu(name: 'Winter Bowl'),
        ],
      );
      await pasteFor(tester, 'Chopt', 'Harvest Bowl, 1 item, 690, 26, 78, 30');

      await save(tester);

      expect(find.text('This menu has moved on'), findsOneWidget);
      expect(find.textContaining('Winter Bowl'), findsOneWidget);
      expect(find.textContaining('not in this document'), findsOneWidget);
    });

    testWidgets('going back writes nothing at all', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openImporter(
        tester,
        foods: <Food>[onTheMenu(name: 'Winter Bowl')],
      );
      await pasteFor(tester, 'Chopt', 'Harvest Bowl, 1 item, 690, 26, 78, 30');
      await save(tester);

      await tester.tap(find.text('Go back'));
      await pumpFrames(tester, frames: 20);

      expect(await db.select(db.foods).get(), hasLength(1));
    });

    testWidgets('keeping them saves the new rows and retires nothing', (
      WidgetTester tester,
    ) async {
      // A restaurant that genuinely still serves the small fries is not a
      // restaurant whose menu was read wrong.
      final HearthDatabase db = await openImporter(
        tester,
        foods: <Food>[onTheMenu(name: 'Winter Bowl')],
      );
      await pasteFor(tester, 'Chopt', 'Harvest Bowl, 1 item, 690, 26, 78, 30');
      await save(tester);

      await tester.tap(find.text('Keep them'));
      await pumpFrames(tester, frames: 30);

      final List<FoodRow> rows = await db.select(db.foods).get();
      expect(rows, hasLength(2));
      expect(rows.every((FoodRow r) => !r.isDeleted), isTrue);
    });

    testWidgets('retiring them soft-deletes, never removes', (
      WidgetTester tester,
    ) async {
      // A menu food can be on a past log, and an absence cannot travel to the
      // other phone (rule 3).
      final HearthDatabase db = await openImporter(
        tester,
        foods: <Food>[onTheMenu(name: 'Winter Bowl')],
      );
      await pasteFor(tester, 'Chopt', 'Harvest Bowl, 1 item, 690, 26, 78, 30');
      await save(tester);

      await tester.tap(find.textContaining('Retire '));
      await pumpFrames(tester, frames: 30);

      final List<FoodRow> rows = await db.select(db.foods).get();
      expect(rows, hasLength(2));
      expect(
        rows.firstWhere((FoodRow r) => r.name == 'Winter Bowl').isDeleted,
        isTrue,
      );
    });
  });
}
