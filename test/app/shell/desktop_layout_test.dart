import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_spacing.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// What a wide window does with the space (review §6.2.7).
///
/// "Desktop is underused: the recipe list stretches a short title and a few
/// numbers across roughly a thousand pixels; the sidebar floats around the
/// vertical center."
void main() {
  const Size desktop = Size(1280, 900);

  /// A library with something in it, because both faults are about how
  /// *content* is laid out and an empty screen lays out nothing. The recipe
  /// search bar in particular is hidden until the library has a recipe.
  Future<void> openWide(WidgetTester tester, String tab) async {
    await pumpHearthApp(
      tester,
      size: desktop,
      recipes: <Recipe>[aRecipe(id: 'r-1', title: 'Weeknight chilli')],
      foods: <Food>[
        aFood(
          'Rolled oats',
          id: 'f-oats',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 380, proteinG: 13),
            ),
          ],
        ),
      ],
    );
    await tester.tap(find.text(tab).last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('the navigation is anchored at the top, not floating', (
    WidgetTester tester,
  ) async {
    // The shell lays the sidebar beside the content in a Row, and a Row
    // centres its children on the cross axis unless told otherwise — so a
    // sidebar shorter than the window sat in a band down the middle with
    // empty paper above and below it.
    await openWide(tester, 'Recipes');

    final double home = tester.getTopLeft(find.text('Home')).dy;

    expect(
      home,
      lessThan(200),
      reason: 'the way out of the section starts $home points down',
    );
  });

  testWidgets('and the sidebar fills the height it is given', (
    WidgetTester tester,
  ) async {
    await openWide(tester, 'Recipes');

    final double rail = tester
        .getSize(
          find.ancestor(
            of: find.text('Nutrition'),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .height;

    expect(rail, greaterThan(desktop.height * 0.8));
  });

  /// The width of something that spans the content column.
  ///
  /// A search field or the shopping header fills its column by construction,
  /// so its width *is* the column's. Measured rather than hunted for through
  /// ancestors: reaching for a `Scrollable` or a `ConstrainedBox` above a bit
  /// of text found the sidebar's own rail — 192 points — and passed two of
  /// these three without measuring anything on the page.
  double columnWidth(WidgetTester tester, Finder spanning) =>
      tester.getSize(spanning).width;

  testWidgets('Recipes stops widening before the window does', (
    WidgetTester tester,
  ) async {
    await openWide(tester, 'Recipes');

    expect(
      columnWidth(tester, find.byType(TextField).first),
      lessThanOrEqualTo(HearthLayout.readingWidth),
    );
  });

  testWidgets('and so does Foods', (WidgetTester tester) async {
    await openWide(tester, 'Foods');

    expect(
      columnWidth(tester, find.byType(TextField).first),
      lessThanOrEqualTo(HearthLayout.readingWidth),
    );
  });

  testWidgets('and so does Shopping', (WidgetTester tester) async {
    await openWide(tester, 'Shopping');

    expect(
      columnWidth(
        tester,
        find
            .ancestor(
              of: find.text('Shopping for'),
              matching: find.byType(Card).evaluate().isEmpty
                  ? find.byType(Padding)
                  : find.byType(Card),
            )
            .first,
      ),
      lessThanOrEqualTo(HearthLayout.readingWidth),
    );
  });
}
