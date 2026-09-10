import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';

import '../../support/app_harness.dart';

/// Adding a restaurant's food from inside the app (spec §5.2).
///
/// Until this existed, `FoodSource.restaurant` could only be written by a
/// migration — so seeding a second restaurant meant asking for SQL. Anything
/// added by hand came out `manual` and would have been auto-matched into
/// recipes the household cooks, which is the one thing that source exists to
/// prevent.
void main() {
  Future<void> openNewFood(WidgetTester tester) async {
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    // One labelled way in now (review §6.2.6), so entering a food by hand is
    // a row in its sheet rather than a bare + in the corner.
    await tester.tap(find.text('Add food'));
    await pumpFrames(tester);
    await tester.tap(find.text('Enter it by hand'));
    await pumpFrames(tester);
  }

  Future<void> flipRestaurant(WidgetTester tester) async {
    final Finder toggle = find.widgetWithText(
      SwitchListTile,
      'From a restaurant',
    );
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(toggle);
    await pumpFrames(tester);
  }

  /// Scrolls back up to the top of the form.
  ///
  /// Flipping the switch means scrolling down to it, which takes the Brand
  /// field out of a lazy ListView's built range — so an assertion about that
  /// field has to go and fetch it again.
  Future<void> scrollToTop(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await pumpFrames(tester);
  }

  testWidgets('the switch renames Brand and drops the shop tag', (
    WidgetTester tester,
  ) async {
    // A restaurant *is* the brand — one string is what groups a menu — and
    // you do not buy a burrito bowl's chicken at Costco.
    await pumpHearthApp(tester);
    await openNewFood(tester);

    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('Store'), findsOneWidget);

    await flipRestaurant(tester);
    await scrollToTop(tester);

    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.text('Brand'), findsNothing);
    expect(find.text('Store'), findsNothing);
  });

  testWidgets('a restaurant food saves as one', (WidgetTester tester) async {
    final HearthDatabase db = await pumpHearthApp(tester);
    await openNewFood(tester);

    await tester.enterText(find.byType(TextField).first, 'Chicken');
    await pumpFrames(tester);
    await flipRestaurant(tester);
    await scrollToTop(tester);
    await tester.enterText(find.byType(TextField).at(1), 'Cava');
    await pumpFrames(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);

    final List<FoodRow> rows = await db.select(db.foods).get();
    expect(rows.single.name, 'Chicken');
    expect(rows.single.brand, 'Cava');
    expect(rows.single.source, 'restaurant');
  });

  testWidgets('and one with no restaurant named will not save', (
    WidgetTester tester,
  ) async {
    // A restaurant food with no restaurant on it cannot be grouped into a
    // menu, so it would never appear in the builder — saved and invisible is
    // the worst of both.
    final HearthDatabase db = await pumpHearthApp(tester);
    await openNewFood(tester);

    await tester.enterText(find.byType(TextField).first, 'Chicken');
    await pumpFrames(tester);
    await flipRestaurant(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Which restaurant?'), findsOneWidget);
    expect(await db.select(db.foods).get(), isEmpty);
  });

  testWidgets('turning it back off restores the real provenance', (
    WidgetTester tester,
  ) async {
    // Not "manual": a food saved from Open Food Facts stays Open Food Facts
    // however much of it is edited, and the switch must not launder that.
    final HearthDatabase db = await pumpHearthApp(tester);
    await openNewFood(tester);

    await tester.enterText(find.byType(TextField).first, 'Chicken');
    await pumpFrames(tester);
    await flipRestaurant(tester);
    await flipRestaurant(tester);
    await scrollToTop(tester);
    await tester.enterText(find.byType(TextField).at(1), 'Tesco');
    await pumpFrames(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);

    expect((await db.select(db.foods).get()).single.source, 'manual');
  });
}
