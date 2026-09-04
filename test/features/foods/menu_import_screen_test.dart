import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';

import '../../support/app_harness.dart';

/// Adding a restaurant menu by pasting it (spec §5.2).
///
/// The review is the screen, not a step after it: what was read sits under
/// the box it was read from, so a line Hearth could not understand is visible
/// while the text that caused it is still in front of you.
void main() {
  Future<void> openImporter(WidgetTester tester) async {
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Build a meal you ate out'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Paste a menu'));
    await pumpFrames(tester, frames: 12);
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).at(1), text);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('shows what it read as you paste', (WidgetTester tester) async {
    await pumpHearthApp(tester);
    await openImporter(tester);

    expect(find.text('Nothing pasted yet.'), findsOneWidget);

    await paste(tester, 'Chicken, 4 oz, 180, 32, 0, 7');

    expect(find.text('1 to add'), findsOneWidget);
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.textContaining('180 kcal'), findsOneWidget);
  });

  testWidgets('and names the lines it could not read, without dropping them', (
    WidgetTester tester,
  ) async {
    // A silent skip in a paste of thirty rows is how a menu ends up missing
    // its chicken with nobody any the wiser.
    await pumpHearthApp(tester);
    await openImporter(tester);

    await paste(
      tester,
      'Proteins\n'
      'Chicken, 4 oz, 180, 32, 0, 7\n'
      'Steak, one scoopful, 150',
    );

    // The heading is neither added nor unread — it is the shape of the menu,
    // and it renders as a heading in the review too.
    expect(find.textContaining('1 to add'), findsOneWidget);
    expect(find.textContaining('1 Hearth could not read'), findsOneWidget);
    // `findsWidgets`, not one: the pasted text is still in the box above, so
    // the words appear there too. The counts on the summary line are the
    // precise assertion.
    expect(find.textContaining('one scoopful'), findsWidgets);
  });

  testWidgets('a pasted heading becomes a section, shown as one', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester);
    await openImporter(tester);
    await tester.enterText(find.byType(TextField).first, 'Cava');
    await pumpFrames(tester);
    await paste(
      tester,
      'Proteins\nFalafel, 4 oz, 330, 12, 30, 18\n'
      'Dips\nHarissa, 2 oz, 60, 1, 4, 5',
    );

    expect(find.text('2 to add'), findsOneWidget);

    await tester.tap(find.text('Save 2'));
    await pumpFrames(tester, frames: 20);

    final List<FoodRow> foods = await db.select(db.foods).get();
    expect(
      <String?>{for (final FoodRow f in foods) f.menuGroup},
      <String>{'Proteins', 'Dips'},
    );
    // The order the sheet had them in, which is what lays the menu out.
    expect(
      foods.firstWhere((FoodRow f) => f.name == 'Falafel').menuOrder,
      lessThan(foods.firstWhere((FoodRow f) => f.name == 'Harissa').menuOrder!),
    );
  });

  testWidgets('saving writes them as that restaurant\'s foods', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester);
    await openImporter(tester);

    await tester.enterText(find.byType(TextField).first, 'Cava');
    await pumpFrames(tester);
    await paste(
      tester,
      'Falafel, 4 oz, 330, 12, 30, 18\n'
      'Harissa, 2 oz, 60, 1, 4, 5, 1, 210, 0',
    );

    await tester.tap(find.text('Save 2'));
    await pumpFrames(tester, frames: 20);

    final List<FoodRow> foods = await db.select(db.foods).get();
    expect(foods, hasLength(2));
    expect(foods.map((FoodRow f) => f.brand), everyElement('Cava'));
    expect(foods.map((FoodRow f) => f.source), everyElement('restaurant'));

    // The minor three where the sheet gave them, unknown where it did not —
    // the same distinction everywhere else keeps (spec §5.6).
    final List<FoodServingOptionRow> servings = await db
        .select(db.foodServingOptions)
        .get();
    expect(servings, hasLength(2));
    expect(servings.map((FoodServingOptionRow s) => s.sodiumMg), contains(210));
    expect(
      servings.map((FoodServingOptionRow s) => s.sodiumMg),
      contains(null),
    );
  });

  testWidgets('and will not save without a restaurant to file them under', (
    WidgetTester tester,
  ) async {
    // A restaurant food with no restaurant belongs to no menu, so it would be
    // saved and invisible.
    final HearthDatabase db = await pumpHearthApp(tester);
    await openImporter(tester);
    await paste(tester, 'Falafel, 4 oz, 330, 12, 30, 18');

    await tester.tap(find.text('Save 1'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Which restaurant?'), findsOneWidget);
    expect(await db.select(db.foods).get(), isEmpty);
  });

  testWidgets('and hands you back to the builder when it is done', (
    WidgetTester tester,
  ) async {
    // Deliberately not asserting that Cava then appears in the list. The
    // harness feeds `foodLibraryProvider` a fixed stream, because fake async
    // cannot drive real sqlite — so a food saved mid-test never reaches it,
    // and asserting otherwise would be asserting the harness. The two halves
    // are covered where they are real: the rows written here, and
    // `RestaurantMenu.restaurantsIn` picking up exactly such a food.
    final HearthDatabase db = await pumpHearthApp(tester);
    await openImporter(tester);
    await tester.enterText(find.byType(TextField).first, 'Cava');
    await pumpFrames(tester);
    await paste(tester, 'Falafel, 4 oz, 330, 12, 30, 18');

    await tester.tap(find.text('Save 1'));
    await pumpFrames(tester, frames: 20);

    // Back on the builder — its empty state, because the stubbed library
    // cannot have grown. "Paste a menu" is on that screen too, so the title
    // is what tells the two apart.
    expect(find.text('Ate out'), findsOneWidget);
    expect(find.text('No restaurants yet'), findsOneWidget);
    expect(await db.select(db.foods).get(), hasLength(1));
  });
}
