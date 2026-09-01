import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

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

Food chicken() => aFood(
  'Chicken breast',
  id: 'food-chicken',
  servingOptions: <ServingOption>[
    aServing(
      id: 's2',
      amount: 100,
      unit: Units.gram,
      macros: const Macros(kcal: 165, proteinG: 31),
    ),
  ],
);

Future<HearthDatabase> openFoods(
  WidgetTester tester, {
  List<Food> foods = const <Food>[],
}) async {
  final HearthDatabase db = await pumpHearthApp(tester, foods: foods);
  await tester.tap(find.text('Foods').last);
  await tester.pump(const Duration(milliseconds: 50));
  return db;
}

/// Taps a filter chip, scrolling the row to it first.
///
/// The chip row is a horizontal scroll view and is wider than a phone, so a
/// chip further along it is off screen and a plain tap silently misses.
Future<void> tapChip(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await pumpFrames(tester);
  await tester.tap(find.text(label));
  await pumpFrames(tester);
}

void main() {
  _selectingTests();

  group('removing a food from the library', () {
    Future<void> swipe(WidgetTester tester, double dx) async {
      final Offset row = tester.getCenter(find.byType(FoodCard).first);
      await tester.dragFrom(Offset(200, row.dy), Offset(dx, 0));
      await pumpFrames(tester, frames: 12);
    }

    testWidgets('delete is hidden until the card is swiped aside', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);

      final Finder delete = find.widgetWithText(TextButton, 'Delete');
      expect(tester.widget<TextButton>(delete).onPressed, isNull);

      await swipe(tester, -120);
      expect(tester.widget<TextButton>(delete).onPressed, isNotNull);
    });

    testWidgets('deleting offers an undo, because it is only a hide', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);

      await swipe(tester, -120);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Deleted Greek yogurt'), findsOneWidget);
      // Soft-deleted (§4): undo restores the same food, so every meal already
      // logged against it keeps resolving.
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('the row closes itself once the food is gone', (
      WidgetTester tester,
    ) async {
      // Keyed by food id, so a deletion cannot hand its open state to whatever
      // moves up into its place.
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await swipe(tester, -120);
      await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
      await pumpFrames(tester, frames: 12);

      for (final TextButton button in tester.widgetList<TextButton>(
        find.widgetWithText(TextButton, 'Delete'),
      )) {
        expect(button.onPressed, isNull);
      }
    });
  });

  group('empty library', () {
    testWidgets('says so, and points at both ways in', (
      WidgetTester tester,
    ) async {
      await openFoods(tester);
      expect(find.text('No foods yet'), findsOneWidget);
      expect(find.textContaining('Scan a packet'), findsOneWidget);
    });

    testWidgets('offers scanning ahead of typing a food in by hand', (
      WidgetTester tester,
    ) async {
      await openFoods(tester);

      // Scanning is the faster path for anything with a packet, and §5.5 puts
      // manual entry behind it rather than in front.
      expect(find.text('Scan'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('a populated library', () {
    testWidgets('lists foods with their per-serving macros', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      expect(find.byType(FoodCard), findsNWidgets(2));
      expect(find.text('Greek yogurt'), findsOneWidget);
      // Calories lead, the other three follow — calories are the primary
      // focus (spec §5.6).
      expect(find.text('100 kcal'), findsOneWidget);
      expect(find.textContaining('per 170 g'), findsOneWidget);
    });

    testWidgets('search narrows the list as you type', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await tester.enterText(find.byType(TextField).first, 'chick');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(FoodCard), findsOneWidget);
      expect(find.text('Chicken breast'), findsOneWidget);
      expect(find.text('Greek yogurt'), findsNothing);
    });

    testWidgets('a search with no matches offers to add the food', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);

      await tester.enterText(find.byType(TextField).first, 'rutabaga');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('None of your foods match'), findsOneWidget);
      expect(find.text('Add it as a new food'), findsOneWidget);
    });

    testWidgets('an empty search shows everything again', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await tester.enterText(find.byType(TextField).first, 'chick');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(FoodCard), findsNWidgets(2));
    });
  });

  group('accessibility (spec §6.3)', () {
    testWidgets('each food is one labelled button', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);
      final SemanticsHandle handle = tester.ensureSemantics();

      expect(find.bySemanticsLabel(RegExp('Greek yogurt')), findsOneWidget);

      handle.dispose();
    });

    testWidgets('meets the tap-target guidelines', (WidgetTester tester) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);
      final SemanticsHandle handle = tester.ensureSemantics();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      handle.dispose();
    });
  });
}

void _selectingTests() {
  group('selecting multiple foods to delete', () {
    Future<void> select(WidgetTester tester, String name) async {
      await tester.longPress(find.text(name));
      await pumpFrames(tester, frames: 12);
    }

    testWidgets('long-pressing a food starts selecting it', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await select(tester, 'Greek yogurt');

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    });

    testWidgets('a tap on another food while selecting adds it too', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await select(tester, 'Greek yogurt');
      await tester.tap(find.text('Chicken breast'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('tapping a selected food again drops it', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await select(tester, 'Greek yogurt');
      await tester.tap(find.text('Chicken breast'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Chicken breast'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('cancelling clears the selection and returns to browsing', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await select(tester, 'Greek yogurt');
      await tester.tap(find.byIcon(Icons.close));
      await pumpFrames(tester, frames: 12);

      expect(find.text('1 selected'), findsNothing);
      expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
    });

    testWidgets('deleting removes exactly the selected foods and offers undo', (
      WidgetTester tester,
    ) async {
      // The harness feeds the library as a fixed, non-reactive stream (fake
      // async cannot drive real sqlite change notifications), so the list
      // itself never visibly shrinks in this test regardless of whether the
      // delete worked. What can be checked, and what actually matters, is the
      // real row underneath — this reads the database directly rather than
      // trusting a UI that structurally cannot re-render here.
      final HearthDatabase db = await openFoods(
        tester,
        foods: <Food>[yogurt(), chicken()],
      );
      final FoodStore store = FoodStore(db);

      await select(tester, 'Greek yogurt');
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline).last,
      );
      await pumpFrames(tester, frames: 12);

      expect(find.text('Deleted 1 food'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      // Back to ordinary browsing, not still in selection mode.
      expect(find.text('1 selected'), findsNothing);

      // The one selected is actually gone; the one never touched is not.
      expect((await store.byId('food-yogurt'))!.isDeleted, isTrue);
      expect((await store.byId('food-chicken'))!.isDeleted, isFalse);

      await tester.tap(find.text('Undo'));
      await pumpFrames(tester, frames: 12);

      // Soft-deleted (§4): undo is a real restore, not a re-creation.
      expect((await store.byId('food-yogurt'))!.isDeleted, isFalse);
    });

    testWidgets('deleting several at once names the count', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openFoods(
        tester,
        foods: <Food>[yogurt(), chicken()],
      );
      final FoodStore store = FoodStore(db);

      await select(tester, 'Greek yogurt');
      await tester.tap(find.text('Chicken breast'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline).last,
      );
      await pumpFrames(tester, frames: 12);

      expect(find.text('Deleted 2 foods'), findsOneWidget);
      expect((await store.byId('food-yogurt'))!.isDeleted, isTrue);
      expect((await store.byId('food-chicken'))!.isDeleted, isTrue);
    });

    testWidgets('a plain tap still opens the food when nobody is selecting', (
      WidgetTester tester,
    ) async {
      // The regression this whole feature could have introduced: FoodCard now
      // takes an onTap override, and getting the default wrong would break
      // the single most common thing this screen does.
      await openFoods(tester, foods: <Food>[yogurt()]);

      await tester.tap(find.text('Greek yogurt'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Edit food'), findsOneWidget);
    });
  });

  group('filtering and sorting the library', () {
    DateTime at(int day) => DateTime.utc(2026, 8, day);

    List<Food> mixedLibrary() => <Food>[
      aFood(
        'Aaa oldest',
        id: 'old',
        updatedAt: at(1),
        servingOptions: <ServingOption>[
          aServing(
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 5),
          ),
        ],
      ),
      aFood(
        'Zzz newest',
        id: 'new',
        barcode: '5000157024671',
        source: FoodSource.openFoodFacts,
        updatedAt: at(3),
        servingOptions: <ServingOption>[
          aServing(
            amount: 100,
            unit: Units.gram,
            macros: const Macros(kcal: 9),
          ),
        ],
      ),
      // No servings at all, so it cannot be logged as it stands.
      aFood('Broken import', id: 'broken', updatedAt: at(2)),
    ];

    testWidgets('opens most recent first, not alphabetically', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: mixedLibrary());
      await pumpFrames(tester);

      final List<FoodCard> cards = tester
          .widgetList<FoodCard>(find.byType(FoodCard))
          .toList();
      expect(cards.map((FoodCard c) => c.food.id), <String>[
        'new',
        'broken',
        'old',
      ]);
    });

    testWidgets('the control says which order the list is in', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: mixedLibrary());
      await pumpFrames(tester);

      expect(find.text('Recent'), findsOneWidget);
    });

    testWidgets('needs-attention keeps only what cannot be logged', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: mixedLibrary());
      await pumpFrames(tester);

      await tester.tap(find.text('Needs attention'));
      await pumpFrames(tester);

      expect(find.byType(FoodCard), findsOneWidget);
      expect(find.text('Broken import'), findsOneWidget);
    });

    testWidgets('has-barcode keeps only scanned packets', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: mixedLibrary());
      await pumpFrames(tester);

      await tapChip(tester, 'Has barcode');

      expect(find.byType(FoodCard), findsOneWidget);
      expect(find.text('Zzz newest'), findsOneWidget);
    });

    testWidgets('a lit chip offers to clear itself', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: mixedLibrary());
      await pumpFrames(tester);
      await tapChip(tester, 'Has barcode');

      expect(find.text('Clear 1 filter'), findsOneWidget);

      await tester.tap(find.text('Clear 1 filter'));
      await pumpFrames(tester);

      expect(find.byType(FoodCard), findsNWidgets(3));
    });

    testWidgets('an empty library shows no filter chips to fiddle with', (
      WidgetTester tester,
    ) async {
      await openFoods(tester);
      await pumpFrames(tester);

      expect(find.text('Needs attention'), findsNothing);
    });
  });
}
