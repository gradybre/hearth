import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Building a meal from a restaurant's menu (spec §5.2).
void main() {
  Food item(
    String name, {
    required String restaurant,
    num amount = 4,
    Unit? unit,
    Macros macros = const Macros(kcal: 180, proteinG: 32),
  }) => aFood(
    name,
    id: 'f-${restaurant.toLowerCase()}-${name.toLowerCase()}',
    brand: restaurant,
    source: FoodSource.restaurant,
    servingOptions: <ServingOption>[
      aServing(amount: amount, unit: unit ?? Units.ounce, macros: macros),
    ],
  );

  List<Food> twoMenus() => <Food>[
    item('Chicken', restaurant: 'Chipotle'),
    item(
      'Cilantro-Lime White Rice',
      restaurant: 'Chipotle',
      macros: const Macros(kcal: 210, carbG: 40),
    ),
    item('Guacamole', restaurant: 'Chipotle'),
    item('Falafel', restaurant: 'Cava'),
    // The household's own food, which is on nobody's menu.
    aFood('Ground beef'),
  ];

  Future<void> openBuilder(WidgetTester tester) async {
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Build a meal you ate out'));
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('lists the restaurants you have seeded, and only those', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, foods: twoMenus());
    await openBuilder(tester);

    expect(find.text('Cava'), findsOneWidget);
    expect(find.text('Chipotle'), findsOneWidget);
    expect(find.text('Ground beef'), findsNothing);
  });

  testWidgets('with nothing seeded it says how to seed one', (
    WidgetTester tester,
  ) async {
    // A first-run state, not an error — so it names the switch that fixes it.
    await pumpHearthApp(tester);
    await openBuilder(tester);

    expect(find.text('No restaurants yet'), findsOneWidget);
    expect(find.textContaining('From a restaurant'), findsOneWidget);
  });

  testWidgets('one restaurant shows its menu and nobody else\'s', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, foods: twoMenus());
    await openBuilder(tester);

    await tester.tap(find.text('Chipotle'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('Guacamole'), findsOneWidget);
    expect(find.text('Falafel'), findsNothing);
  });

  testWidgets('picking builds an unsaved recipe with everything matched', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester, foods: twoMenus());
    await openBuilder(tester);
    await tester.tap(find.text('Chipotle'));
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.text('Chicken'));
    await tester.tap(find.text('Guacamole'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Build (2)'), findsOneWidget);
    await tester.tap(find.text('Build (2)'));
    await pumpFrames(tester, frames: 20);

    // Straight into the editor, already matched — no line asking for a food.
    expect(find.text('New recipe'), findsOneWidget);
    expect(find.text('tap to match a food'), findsNothing);
    // And nothing written yet (CLAUDE.md rule 4).
    expect(await db.select(db.recipes).get(), isEmpty);
  });

  testWidgets('and saving it lands as an eaten-out recipe', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester, foods: twoMenus());
    await openBuilder(tester);
    await tester.tap(find.text('Chipotle'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Chicken'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Build (1)'));
    await pumpFrames(tester, frames: 20);

    await tester.enterText(find.byType(TextField).first, 'My usual bowl');
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);

    final List<RecipeRow> rows = await db.select(db.recipes).get();
    expect(rows.single.title, 'My usual bowl');
    expect(rows.single.kind, 'eaten_out');
    // Where it came from, which is the only place an eaten-out recipe has to
    // record a venue.
    expect(rows.single.notes, 'Chipotle');
  });

  testWidgets('the stepper is only on what you picked', (
    WidgetTester tester,
  ) async {
    // A stepper on an unpicked row invites setting a number on something you
    // have not said you had.
    await pumpHearthApp(tester, foods: twoMenus());
    await openBuilder(tester);
    await tester.tap(find.text('Chipotle'));
    await pumpFrames(tester, frames: 12);

    expect(find.byTooltip('One more'), findsNothing);

    await tester.tap(find.text('Chicken'));
    await pumpFrames(tester, frames: 12);

    expect(find.byTooltip('One more'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);

    await tester.tap(find.byTooltip('One more'));
    await pumpFrames(tester, frames: 12);
    expect(find.text('1.5×'), findsOneWidget);
  });

  testWidgets('changing restaurant clears the picks', (
    WidgetTester tester,
  ) async {
    // Picking from two menus at once is not a meal, it is a mistake — and a
    // bowl arriving with somebody else's rice in it would be a quiet one.
    await pumpHearthApp(tester, foods: twoMenus());
    await openBuilder(tester);
    await tester.tap(find.text('Chipotle'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Chicken'));
    await pumpFrames(tester, frames: 12);
    expect(find.text('Build (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to restaurants'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Cava'));
    await pumpFrames(tester, frames: 12);

    expect(find.textContaining('Build ('), findsNothing);
  });
}
