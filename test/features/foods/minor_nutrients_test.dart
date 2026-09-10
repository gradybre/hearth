import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Fibre, sodium and cholesterol on a food, and on a day (spec §5.6).
///
/// Lifted from §12's deferred list deliberately; the spec was amended in the
/// same change. The whole feature rests on one distinction — **blank means
/// unknown, a typed 0 means none** — so that is what most of this asserts.
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

  /// The field under a label.
  ///
  /// `_TextField` renders its label as a sibling `Text` above the input
  /// rather than as an `InputDecoration.labelText`, so the field cannot be
  /// found by its own words — it is found through the Column that holds both.
  /// Taps a control after making sure it is actually on screen.
  ///
  /// The editor is a long ListView, so anything below the fold has to be
  /// scrolled to first — a bare `tap` lands on whatever happens to be at
  /// those coordinates instead, which fails as a silent no-op.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    // Settle first: text entered a moment ago has not rebuilt the tree yet,
    // and scrolling to a stale element lands the tap on nothing.
    await pumpFrames(tester);
    await tester.ensureVisible(finder);
    await pumpFrames(tester);
    await tester.tap(finder);
    await pumpFrames(tester);
  }

  Future<Finder> field(WidgetTester tester, String label) async {
    final Finder text = find.text(label);
    await tester.scrollUntilVisible(
      text,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    return find
        .descendant(
          of: find.ancestor(of: text, matching: find.byType(Column)).first,
          matching: find.byType(TextField),
        )
        .first;
  }

  testWidgets('are behind a disclosure, and it costs no height closed', (
    WidgetTester tester,
  ) async {
    // Closed is the default because these are minor and the four above are
    // the daily driver. The toggle sits in a row that already existed, so a
    // food with four servings does not grow four rows of chrome.
    await pumpHearthApp(tester);
    await openNewFood(tester);

    expect(find.text('Fibre (g)'), findsNothing);
    expect(find.byTooltip('Add fibre, sodium and cholesterol'), findsOneWidget);

    // By icon rather than by tooltip: `find.byTooltip` can resolve to the
    // tooltip's own overlay entry once the list has been scrolled, and a tap
    // on that hit-tests through to nothing.
    await tapVisible(tester, find.byIcon(Icons.expand_more));

    expect(find.text('Fibre (g)'), findsOneWidget);
    expect(find.text('Sodium (mg)'), findsOneWidget);
    expect(find.text('Cholesterol (mg)'), findsOneWidget);
  });

  testWidgets('a typed value is saved, and a blank one stays unknown', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester);
    await openNewFood(tester);

    await tester.enterText(find.byType(TextField).first, 'Oats');
    await pumpFrames(tester);
    // Real calories too, or the editor rightly asks whether a food with no
    // macros at all was meant.
    await tester.enterText(await field(tester, 'kcal'), '380');
    // By icon rather than by tooltip: `find.byTooltip` can resolve to the
    // tooltip's own overlay entry once the list has been scrolled, and a tap
    // on that hit-tests through to nothing.
    await tapVisible(tester, find.byIcon(Icons.expand_more));

    await tester.enterText(await field(tester, 'Fibre (g)'), '10');
    // Cholesterol left blank on purpose: nobody has said, and Hearth must not
    // decide that means none.
    await tester.enterText(await field(tester, 'Sodium (mg)'), '0');
    await pumpFrames(tester);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);

    final List<FoodServingOptionRow> servings = await db
        .select(db.foodServingOptions)
        .get();
    expect(servings.single.fiberG, 10);
    // A stated zero is a fact — this food really has no sodium.
    expect(servings.single.sodiumMg, 0);
    expect(servings.single.cholesterolMg, isNull);
  });

  testWidgets('the disclosure opens itself when there is something to show', (
    WidgetTester tester,
  ) async {
    // Never hiding real data behind a tap is the other half of the rule. A
    // food that already knows its fibre shows it the moment it is opened, so
    // the closed default can never bury a number somebody entered.
    await pumpHearthApp(
      tester,
      foods: <Food>[
        aFood(
          'Oats',
          servingOptions: <ServingOption>[
            aServing(
              amount: 100,
              unit: Units.gram,
              macros: const Macros(kcal: 380, fiberG: 10),
            ),
          ],
        ),
      ],
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Oats').first);
    await pumpFrames(tester, frames: 12);

    expect(find.text('Fibre (g)'), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
  });
}
