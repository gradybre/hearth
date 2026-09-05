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
    String? section,
    int? order,
    Macros macros = const Macros(kcal: 180, proteinG: 32),
  }) => aFood(
    name,
    id: 'f-${restaurant.toLowerCase()}-${name.toLowerCase()}',
    brand: restaurant,
    source: FoodSource.restaurant,
    menuGroup: section,
    menuOrder: order,
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

  testWidgets('the menu is laid out the way the restaurant lays it out', (
    WidgetTester tester,
  ) async {
    // A to Z puts the barbacoa between the beans and the cheese, which is
    // nobody's menu. Sections come out in the order the sheet prints them,
    // not alphabetically — Proteins before Salsas, though S precedes P.
    await pumpHearthApp(
      tester,
      foods: <Food>[
        item(
          'Fresh Tomato Salsa',
          restaurant: 'Chipotle',
          section: 'Salsas',
          order: 3,
        ),
        item('Chicken', restaurant: 'Chipotle', section: 'Proteins', order: 2),
        item('Barbacoa', restaurant: 'Chipotle', section: 'Proteins', order: 1),
        item('Black Beans', restaurant: 'Chipotle', section: 'Beans', order: 0),
      ],
    );
    await openBuilder(tester);
    await tester.tap(find.text('Chipotle'));
    await pumpFrames(tester, frames: 12);

    double y(String text) => tester.getTopLeft(find.text(text)).dy;

    expect(find.text('Beans'), findsOneWidget);
    expect(find.text('Proteins'), findsOneWidget);
    expect(find.text('Salsas'), findsOneWidget);

    expect(y('Beans'), lessThan(y('Proteins')));
    expect(y('Proteins'), lessThan(y('Salsas')));
    // And within a section, the sheet's order rather than the alphabet.
    expect(y('Barbacoa'), lessThan(y('Chicken')));
  });

  testWidgets('a menu nobody sectioned still lists, without headings', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      foods: <Food>[
        item('Falafel', restaurant: 'Cava'),
        item('Harissa', restaurant: 'Cava'),
      ],
    );
    await openBuilder(tester);
    await tester.tap(find.text('Cava'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Falafel'), findsOneWidget);
    expect(find.text('Harissa'), findsOneWidget);
  });

  testWidgets('a row shows one portion, and it reads like a portion', (
    WidgetTester tester,
  ) async {
    // Brendan's screenshot: a picked half-scoop read
    // "2.0000000088184904 oz · 4 oz · 65 kcal" — two portions and a float,
    // for one line of one item.
    await pumpHearthApp(
      tester,
      foods: <Food>[
        item(
          'Black Beans',
          restaurant: 'Chipotle',
          macros: const Macros(kcal: 130),
        ),
      ],
    );
    await openBuilder(tester);
    await tester.tap(find.text('Chipotle'));
    await pumpFrames(tester, frames: 12);

    // Unpicked: the serving as the menu states it.
    expect(find.text('4 oz · 130 kcal'), findsOneWidget);

    await tester.tap(find.text('Black Beans'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('One less'));
    await pumpFrames(tester, frames: 12);

    // Picked at a half: what you are having, and what it costs.
    expect(find.text('2 oz · 65 kcal'), findsOneWidget);
  });

  group('taking an ordinary component out (spec §5.2)', () {
    // Not a modifier: the chain publishes lettuce as a positive row you can
    // order. Taking it out is the *pick* being negative, for a burger whose
    // published figure counted the lettuce in.
    List<Food> freddys() => <Food>[
      item(
        'Single Steakburger',
        restaurant: "Freddy's",
        section: 'Steakburgers',
        order: 0,
        amount: 1,
        unit: Units.item,
        macros: const Macros(kcal: 380, proteinG: 24, carbG: 30, fatG: 12),
      ),
      item(
        'Lettuce',
        restaurant: "Freddy's",
        section: 'Toppings',
        order: 1,
        amount: 1,
        unit: Units.ounce,
        macros: const Macros(kcal: 3, carbG: 1),
      ),
    ];

    Future<void> openFreddys(WidgetTester tester) async {
      await openBuilder(tester);
      await tester.tap(find.text("Freddy's"));
      await pumpFrames(tester, frames: 12);
    }

    testWidgets('is offered on every ordinary row, and waits its turn', (
      WidgetTester tester,
    ) async {
      // Greyed with the reason rather than hidden, the way a modifier row is:
      // a control that appears and disappears as you pick is harder to
      // understand than one that says what it is waiting for.
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);

      expect(
        find.byTooltip('Take Lettuce out — pick something first'),
        findsOneWidget,
      );

      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);

      expect(find.byTooltip('Take Lettuce out'), findsOneWidget);
    });

    testWidgets('a taken-out row says so in words, not by colour', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Take Lettuce out'));
      await pumpFrames(tester, frames: 12);

      // The words and a real minus sign, both of which survive a screen
      // reader and a monochrome display (§6.3).
      expect(find.text('Taking it out'), findsOneWidget);
      expect(find.text('−1 oz · −3 kcal'), findsOneWidget);
      expect(find.text('Build (2)'), findsOneWidget);
    });

    testWidgets('and it goes when the last real thing goes', (
      WidgetTester tester,
    ) async {
      // The same rule the modifiers follow, for the same reason: left behind,
      // "no lettuce" is a meal of minus three calories.
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Take Lettuce out'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);

      expect(find.textContaining('Build ('), findsNothing);
      expect(find.text('Taking it out'), findsNothing);
    });

    testWidgets('it builds a recipe with the deduction already matched', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Take Lettuce out'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Build (2)'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('New recipe'), findsOneWidget);
      expect(find.text('tap to match a food'), findsNothing);
      // The line itself carries the sign into the editor.
      expect(find.textContaining('−1 oz Lettuce'), findsWidgets);
      expect(await db.select(db.recipes).get(), isEmpty);
    });

    testWidgets('two slices off a double is a count, taken the other way', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Take Lettuce out'));
      await pumpFrames(tester, frames: 12);

      // The stepper counts what is being taken out, on its magnitude — it does
      // not walk a number down through zero and out the other side.
      expect(find.text('−1×'), findsOneWidget);
      await tester.tap(find.byTooltip('Take out more'));
      await pumpFrames(tester, frames: 12);
      expect(find.text('−1.5×'), findsOneWidget);
    });

    testWidgets('and it is still a deduction once it has been saved', (
      WidgetTester tester,
    ) async {
      // Through the parser, the mapper and SQLite, which is three places a
      // sign can be lost between the menu and the day it is logged to.
      final HearthDatabase db = await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Take Lettuce out'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Build (2)'));
      await pumpFrames(tester, frames: 20);

      await tester.enterText(find.byType(TextField).first, 'Burger, no salad');
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester, frames: 20);

      final List<RecipeIngredientRow> rows = await db
          .select(db.recipeIngredients)
          .get();
      final RecipeIngredientRow lettuce = rows.firstWhere(
        (RecipeIngredientRow row) => row.name == 'Lettuce',
      );
      expect(lettuce.quantityCanonical, lessThan(0));
      expect(lettuce.foodId, isNotNull);
      // And the line the user can still read and edit says it in words.
      expect(lettuce.rawText, startsWith('−'));
    });

    testWidgets('and the refusal says why rather than doing nothing', (
      WidgetTester tester,
    ) async {
      // The button is enabled even when it will refuse, so that the tap does
      // not fall through to the row and *add* the component. What was left
      // was a control that took the tap and did nothing at all with it: no
      // state change, no message, and the reason only in a tooltip that a
      // touch user has to long-press to find. Colour was the whole of it,
      // which rule 6 does not allow.
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);

      await tester.tap(
        find.byTooltip(
          'Take Lettuce out — pick something '
          'first',
        ),
      );
      await pumpFrames(tester, frames: 12);

      expect(
        find.text('Pick something for Lettuce to come out of first.'),
        findsOneWidget,
      );
    });

    testWidgets('a row the sheet gave no portion is not offered at all', (
      WidgetTester tester,
    ) async {
      // With no serving there is no amount for the sign to sit on, so the
      // line came out as a bare "Pickles" — an unquantified ingredient that
      // contributes nothing and raises `noQuantity`. A deduction that
      // silently deducts nothing is worse than one that is never offered.
      await pumpHearthApp(
        tester,
        foods: <Food>[
          ...freddys(),
          aFood(
            'Pickles',
            id: 'f-freddys-pickles',
            brand: "Freddy's",
            source: FoodSource.restaurant,
            menuGroup: 'Toppings',
            menuOrder: 2,
          ),
        ],
      );
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);

      expect(find.byTooltip('Take Lettuce out'), findsOneWidget);
      expect(find.byTooltip('Take Pickles out'), findsNothing);

      // It is still an ordinary row you can say you had.
      await tester.tap(find.text('Pickles'));
      await pumpFrames(tester, frames: 12);
      expect(find.text('Build (2)'), findsOneWidget);
    });

    testWidgets('a meal that comes to less than nothing cannot be built', (
      WidgetTester tester,
    ) async {
      // The guard asked whether *something* positive was picked, not whether
      // the meal came to anything. Three calories of lettuce satisfied it
      // while the burger came out underneath, and the builder assembled a
      // recipe of −377 kcal — which the spec, the calculator and this file
      // all say it will not.
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);

      await tester.tap(find.text('Lettuce'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Take Single Steakburger out'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Build (2)'), findsOneWidget);
      await tester.tap(find.text('Build (2)'));
      await pumpFrames(tester, frames: 20);

      // Still on the menu, and told why rather than left tapping a button
      // that does nothing.
      expect(find.text('New recipe'), findsNothing);
      expect(find.textContaining('less than nothing'), findsOneWidget);
    });

    testWidgets('the stepper at its floor does not unpick the row beneath', (
      WidgetTester tester,
    ) async {
      // A disabled IconButton does not take the tap: it falls through to the
      // row's own InkWell behind it, which toggles the pick. So a second
      // "One less" at half a portion deleted the item from the meal — the
      // same mechanism this screen already fixed for its take-out button,
      // sitting one widget along.
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);

      await tester.tap(find.byTooltip('One less'));
      await pumpFrames(tester, frames: 12);
      expect(find.text('0.5×'), findsOneWidget);

      await tester.tap(find.byTooltip('One less'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('0.5×'), findsOneWidget);
      expect(find.text('Build (1)'), findsOneWidget);
    });

    testWidgets('nor at its ceiling', (WidgetTester tester) async {
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);

      for (int i = 0; i < 6; i++) {
        await tester.tap(find.byTooltip('One more'));
        await pumpFrames(tester, frames: 4);
      }
      expect(find.text('4×'), findsOneWidget);

      await tester.tap(find.byTooltip('One more'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('4×'), findsOneWidget);
      expect(find.text('Build (1)'), findsOneWidget);
    });

    testWidgets('and neither does the one on a row being taken out', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.byTooltip('Take Lettuce out'));
      await pumpFrames(tester, frames: 12);

      await tester.tap(find.byTooltip('Take out less'));
      await pumpFrames(tester, frames: 12);
      expect(find.text('−0.5×'), findsOneWidget);

      await tester.tap(find.byTooltip('Take out less'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('−0.5×'), findsOneWidget);
      expect(find.text('Taking it out'), findsOneWidget);
      expect(find.text('Build (2)'), findsOneWidget);
    });

    testWidgets('a meal of nothing but deductions cannot be built', (
      WidgetTester tester,
    ) async {
      // Whatever the user does, there is no path to a recipe that only takes
      // away — the same guard the modifiers have, sharing the same rule.
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);

      await tester.tap(
        find.byTooltip(
          'Take Lettuce out — pick something '
          'first',
        ),
      );
      await pumpFrames(tester, frames: 12);

      expect(find.textContaining('Build ('), findsNothing);
    });
  });

  group('modifiers (spec §5.2)', () {
    Food wrap() => item(
      'Make it a Lettuce Wrap',
      restaurant: "Freddy's",
      section: 'Modifications',
      order: 2,
      amount: 1,
      unit: Units.item,
      macros: const Macros(
        kcal: -180,
        proteinG: -3,
        carbG: -25,
        fatG: -6,
        fiberG: 1,
      ),
    ).asModifier();

    List<Food> freddys() => <Food>[
      item(
        'Single Steakburger',
        restaurant: "Freddy's",
        section: 'Steakburgers',
        order: 0,
        amount: 1,
        unit: Units.item,
        macros: const Macros(kcal: 380, proteinG: 24, carbG: 30, fatG: 12),
      ),
      wrap(),
    ];

    Future<void> openFreddys(WidgetTester tester) async {
      await openBuilder(tester);
      await tester.tap(find.text("Freddy's"));
      await pumpFrames(tester, frames: 12);
    }

    testWidgets('a deduction reads as one, and not by colour', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);

      // The minus is in the text, so it survives a screen reader and a
      // monochrome display both (§6.3).
      expect(find.textContaining('−180 kcal'), findsOneWidget);
      // And it says why it is waiting rather than silently ignoring a tap.
      expect(find.text('Takes away — pick something first'), findsOneWidget);
    });

    testWidgets('cannot be picked before there is anything to take it from', (
      WidgetTester tester,
    ) async {
      // On its own it is not a meal, it is 180 calories removed from a day
      // that never had them.
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);

      await tester.tap(find.text('Make it a Lettuce Wrap'));
      await pumpFrames(tester, frames: 12);

      // Nothing picked, so nothing to build.
      expect(find.textContaining('Build ('), findsNothing);
    });

    testWidgets('and once something is picked, it comes along', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);

      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Make it a Lettuce Wrap'));
      await pumpFrames(tester, frames: 12);

      expect(find.text('Build (2)'), findsOneWidget);
      await tester.tap(find.text('Build (2)'));
      await pumpFrames(tester, frames: 20);

      // Both lines are in the draft and both are matched — the deduction is
      // an ingredient like any other once it has something to apply to.
      expect(find.text('New recipe'), findsOneWidget);
      expect(find.text('tap to match a food'), findsNothing);
      expect(find.textContaining('Lettuce Wrap'), findsWidgets);
    });

    testWidgets('it goes when the last real thing goes', (
      WidgetTester tester,
    ) async {
      // Otherwise unpicking the burger leaves a meal of minus 180 calories,
      // and the rule that a modifier needs something to apply to would hold
      // only until you changed your mind.
      await pumpHearthApp(tester, foods: freddys());
      await openFreddys(tester);

      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Make it a Lettuce Wrap'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Single Steakburger'));
      await pumpFrames(tester, frames: 12);

      expect(find.textContaining('Build ('), findsNothing);
    });
  });
}
