import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Merging the copies that are already there (review N05).
///
/// `Use existing` (#69) stops a second copy being made. This is for the ones
/// that got made — and unlike that one it writes, so every figure is counted
/// and shown before the button (CLAUDE.md rule 4).
void main() {
  Food yogurt({
    required String id,
    String name = 'Greek yogurt',
    String? brand,
    double amount = 170,
    Unit unit = Units.gram,
  }) => aFood(
    name,
    id: id,
    brand: brand,
    servingOptions: <ServingOption>[
      aServing(
        id: '$id-s',
        amount: amount,
        unit: unit,
        macros: const Macros(kcal: 100, proteinG: 17, carbG: 6),
      ),
    ],
  );

  Future<HearthDatabase> openMerge(
    WidgetTester tester, {
    List<Food> foods = const <Food>[],
    List<Recipe> recipes = const <Recipe>[],
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      size: size,
      textScale: scale,
      foods: foods,
      recipes: recipes,
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Duplicate foods'));
    await pumpFrames(tester, frames: 12);
    return db;
  }

  group('finding them', () {
    testWidgets('two foods with one name are a group', (
      WidgetTester tester,
    ) async {
      await openMerge(
        tester,
        foods: <Food>[
          yogurt(id: 'f-1', brand: 'Fage'),
          yogurt(id: 'f-2', brand: 'Chobani'),
        ],
      );

      expect(find.text('Review a merge'), findsOneWidget);
      expect(find.textContaining('Fage'), findsOneWidget);
      expect(find.textContaining('Chobani'), findsOneWidget);
    });

    testWidgets('and a library with no pairs says so', (
      WidgetTester tester,
    ) async {
      await openMerge(
        tester,
        foods: <Food>[
          yogurt(id: 'f-1'),
          yogurt(id: 'f-2', name: 'Oats'),
        ],
      );

      expect(find.text('No duplicates'), findsOneWidget);
    });
  });

  group('the review before the merge', () {
    testWidgets('says what moves and what does not', (
      WidgetTester tester,
    ) async {
      await openMerge(
        tester,
        foods: <Food>[
          yogurt(id: 'f-1', brand: 'Fage'),
          yogurt(id: 'f-2', brand: 'Chobani'),
        ],
        recipes: <Recipe>[
          aRecipe(
            id: 'r1',
            title: 'Chilli',
            // The household the app's own repositories use. `aRecipe`
            // defaults to `household-1` and recipes are scoped strictly, so a
            // fixture left at the default is invisible to the merge walk.
            householdId: 'local-household',
            sections: <RecipeSection>[
              aSection(
                id: 's1',
                ingredients: <RecipeIngredient>[
                  anIngredient(
                    'yogurt',
                    amount: 200,
                    unit: Units.gram,
                    foodId: 'f-2',
                    sectionId: 's1',
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.tap(find.text('Review a merge'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Merge two foods'), findsOneWidget);
      expect(find.textContaining('1 recipe line'), findsOneWidget);
      expect(find.textContaining('No meal has been logged'), findsOneWidget);
    });

    testWidgets('and the button counts before it commits', (
      WidgetTester tester,
    ) async {
      await openMerge(
        tester,
        foods: <Food>[
          yogurt(id: 'f-1', brand: 'Fage'),
          yogurt(id: 'f-2', brand: 'Chobani'),
        ],
      );
      await tester.tap(find.text('Review a merge'));
      await pumpFrames(tester, frames: 20);

      // Nothing references either, so there is nothing to move — and the
      // button says that rather than a number.
      expect(find.text('Merge'), findsOneWidget);
      expect(
        find.textContaining('nothing — no recipe or plan'),
        findsOneWidget,
      );
    });

    testWidgets('the other food can be the one kept instead', (
      WidgetTester tester,
    ) async {
      await openMerge(
        tester,
        foods: <Food>[
          yogurt(id: 'f-1', brand: 'Fage'),
          yogurt(id: 'f-2', brand: 'Chobani'),
        ],
      );
      await tester.tap(find.text('Review a merge'));
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.text('Keep the other one instead'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Merge two foods'), findsOneWidget);
    });
  });

  testWidgets('merging retires one and keeps the other', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await openMerge(
      tester,
      foods: <Food>[
        yogurt(id: 'f-1', brand: 'Fage'),
        yogurt(id: 'f-2', brand: 'Chobani', amount: 100),
      ],
    );
    await tester.tap(find.text('Review a merge'));
    await pumpFrames(tester, frames: 20);

    await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
    await pumpFrames(tester, frames: 30);

    final List<FoodRow> rows = await db.select(db.foods).get();
    expect(rows, hasLength(2), reason: 'soft-deleted, never removed');
    expect(rows.firstWhere((FoodRow r) => r.id == 'f-2').isDeleted, isTrue);
    expect(rows.firstWhere((FoodRow r) => r.id == 'f-1').isDeleted, isFalse);
  });

  testWidgets('the review survives a small phone at three times the text', (
    WidgetTester tester,
  ) async {
    // A sheet of counted lines is exactly the shape that breaks at large
    // text, and the surface guard is per file — so this walks it here.
    await openMerge(
      tester,
      foods: <Food>[
        yogurt(id: 'f-1', brand: 'Fage'),
        yogurt(id: 'f-2', brand: 'Chobani'),
      ],
      size: const Size(320, 568),
      scale: 3,
    );
    // The list scrolls, and at three times the text the card's own lines put
    // the button below the fold — which is what dynamic type costs and is not
    // itself the fault. What matters is that the sheet it opens holds.
    await tester.ensureVisible(find.text('Review a merge'));
    await pumpFrames(tester);
    await tester.tap(find.text('Review a merge'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Merge two foods'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
