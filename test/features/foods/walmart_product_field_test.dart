import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';

import '../../support/app_harness.dart';

/// Telling Hearth which product a food is, at the shop (spec §5.7).
void main() {
  Future<void> openNewFood(WidgetTester tester) async {
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Add a food by hand'));
    await pumpFrames(tester);
  }

  /// Found by hint, not by label: the label is a sibling Text above the
  /// field rather than a descendant of it, so widgetWithText cannot see it.
  Future<Finder> field(WidgetTester tester, String hint) async {
    final Finder finder = find.widgetWithText(TextField, hint);
    // The editor is a ListView and this section sits below the fold, so at
    // any text size the field has to be scrolled to before it is built.
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    return finder;
  }

  Future<void> fill(
    WidgetTester tester, {
    required String name,
    String? link,
    String? pack,
  }) async {
    await tester.enterText(find.byType(TextField).first, name);
    if (link != null) {
      await tester.enterText(
        await field(tester, 'walmart.com/ip/…/10450479'),
        link,
      );
      await pumpFrames(tester);
    }
    if (pack != null) {
      await tester.enterText(await field(tester, '1 lb'), pack);
    }
    await pumpFrames(tester);
  }

  testWidgets('a pasted link reaches the row as an item number', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester);
    await openNewFood(tester);

    await fill(
      tester,
      name: 'Ground beef',
      link: 'https://www.walmart.com/ip/Ground-Beef-80-20/10450479',
      pack: '1 lb',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 12);

    final FoodRow row = (await db.select(db.foods).get()).single;
    expect(row.walmartItemId, '10450479');
    expect(row.packUnit, 'lb');
  });

  testWidgets('a link with no number in it says so before you save', (
    WidgetTester tester,
  ) async {
    // The only place this can usefully be said. Stored as nothing, the food
    // would simply be absent from a basket and nobody would know why.
    await pumpHearthApp(tester);
    await openNewFood(tester);

    await fill(tester, name: 'Ground beef', link: 'ground beef');

    expect(find.textContaining('No item number in that'), findsOneWidget);
  });

  testWidgets('and says nothing while the field is empty', (
    WidgetTester tester,
  ) async {
    // Most foods will never have one. An empty optional field is not a fault.
    await pumpHearthApp(tester);
    await openNewFood(tester);

    await fill(tester, name: 'Ground beef');

    expect(find.textContaining('No item number in that'), findsNothing);
  });
}
