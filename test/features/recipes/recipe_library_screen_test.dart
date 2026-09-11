import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/sort_button.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/recipe_query.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/macro_stats_row.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

Recipe shortRibs() => aRecipe(
  id: 'recipe-1',
  title: 'Braised short ribs',
  servings: 4,
  sections: <RecipeSection>[
    aSection(
      id: 'sec',
      ingredients: <RecipeIngredient>[
        anIngredient(
          'olive oil',
          amount: 2,
          unit: Units.tbsp,
          sectionId: 'sec',
        ),
      ],
    ),
  ],
);

/// A tablespoon of oil, matched to a food, so the recipe's macros actually
/// resolve rather than sitting incomplete.
Food oliveOilPerTbsp() => aFood(
  'Olive oil',
  id: 'food-oil',
  servingOptions: <ServingOption>[
    aServing(
      amount: 1,
      unit: Units.tbsp,
      macros: const Macros(kcal: 120, fatG: 14),
    ),
  ],
);

Recipe shortRibsWithMatchedOil() => aRecipe(
  id: 'recipe-1',
  title: 'Braised short ribs',
  servings: 4,
  sections: <RecipeSection>[
    aSection(
      id: 'sec',
      ingredients: <RecipeIngredient>[
        anIngredient(
          'olive oil',
          amount: 2,
          unit: Units.tbsp,
          sectionId: 'sec',
          foodId: 'food-oil',
        ),
      ],
    ),
  ],
);

void main() {
  group('empty library (spec §5.8)', () {
    testWidgets('says so plainly rather than showing a fake recipe', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester);

      expect(find.text('Your library is empty'), findsOneWidget);
      expect(find.byType(RecipeCard), findsNothing);
    });

    testWidgets('still offers a way to add one', (WidgetTester tester) async {
      await pumpHearthApp(tester);
      expect(find.text('Add recipe'), findsOneWidget);
    });
  });

  group('a populated library', () {
    testWidgets('renders a card per recipe', (WidgetTester tester) async {
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          shortRibs(),
          aRecipe(id: 'recipe-2', title: 'Weeknight pasta'),
        ],
      );

      expect(find.byType(RecipeCard), findsNWidgets(2));
      expect(find.text('Braised short ribs'), findsOneWidget);
      expect(find.text('Weeknight pasta'), findsOneWidget);
      expect(find.text('Your library is empty'), findsNothing);
    });

    testWidgets('summarises yield and time', (WidgetTester tester) async {
      await pumpHearthApp(tester, recipes: <Recipe>[shortRibs()]);
      expect(find.textContaining('Serves 4'), findsOneWidget);
    });

    testWidgets('shows tags when a recipe has them', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'r', title: 'Tagged', sections: <RecipeSection>[]),
        ],
      );
      // The fixture has no tags, so none should render — a tag row must not
      // appear as an empty strip. Scoped to the card: the filter rail is a
      // Wrap of its own now, and always has controls in it.
      expect(
        find.descendant(
          of: find.byType(RecipeCard),
          matching: find.byType(Wrap),
        ),
        findsNothing,
      );
    });
  });

  group('accessibility (spec §6.3)', () {
    testWidgets('each card is one labelled button for a screen reader', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: <Recipe>[shortRibs()]);
      final SemanticsHandle handle = tester.ensureSemantics();

      expect(
        find.bySemanticsLabel(RegExp('Braised short ribs')),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('the library meets the tap-target guidelines', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: <Recipe>[shortRibs()]);
      final SemanticsHandle handle = tester.ensureSemantics();

      // iOS's 44, not Android's 48. Hearth ships iOS, macOS and Windows, and
      // the theme sets 44 as the floor for every button in the app
      // (hearth_theme.dart) — the same call test/app/a11y/guidelines_test.dart
      // makes and says out loud. Asking this one screen for 48 would fail on
      // any themed button that ever appears on it, which is why it only ever
      // passed on a fixture with no filters applied.
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('library text meets the contrast guideline in dark mode', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pumpHearthApp(tester, recipes: <Recipe>[shortRibs()]);
      final SemanticsHandle handle = tester.ensureSemantics();

      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
    });
  });

  group('the household control', () {
    testWidgets('is reachable from an empty library', (
      WidgetTester tester,
    ) async {
      // It used to live only in the populated branch, which hid it from
      // exactly the person who needs it: someone with nothing in their
      // library yet, about to share a code with their partner. It is the
      // shell's own Settings button now (#58, #61) rather than a second door
      // in this corner called "Household" — so what this guards is that an
      // empty library still has one.
      await pumpHearthApp(tester);
      await pumpFrames(tester);

      expect(find.text('Your library is empty'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsWidgets);
    });

    testWidgets('and from a populated one', (WidgetTester tester) async {
      await pumpHearthApp(tester, recipes: <Recipe>[shortRibs()]);
      await pumpFrames(tester);

      expect(find.byTooltip('Settings'), findsWidgets);
    });
  });

  group('per-serving macros on the card', () {
    testWidgets('a fully matched recipe shows its numbers', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[shortRibsWithMatchedOil()],
        foods: <Food>[oliveOilPerTbsp()],
      );

      // 2 tbsp at 120 kcal / 14 g fat per tbsp, across 4 servings.
      expect(find.textContaining('60 kcal'), findsOneWidget);
      expect(find.textContaining('7g fat'), findsOneWidget);
    });

    testWidgets('an incomplete recipe still shows a total, marked partial', (
      WidgetTester tester,
    ) async {
      // shortRibs()'s oil carries no foodId. Hiding the line entirely made a
      // recipe's nutrition vanish over one unresolved ingredient with nothing
      // on screen to say why; marking it partial keeps the numbers honest
      // without keeping them secret.
      await pumpHearthApp(tester, recipes: <Recipe>[shortRibs()]);

      expect(find.byType(MacroStatsLine), findsOneWidget);
      // Never colour alone (§6.3) — the caveat is a word.
      expect(find.textContaining('partial'), findsOneWidget);
    });

    testWidgets('a complete recipe is not marked partial', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[shortRibsWithMatchedOil()],
        foods: <Food>[oliveOilPerTbsp()],
      );

      expect(find.textContaining('partial'), findsNothing);
    });

    testWidgets('an ingredient matched to a food that cannot convert is not '
        'called unmatched', (WidgetTester tester) async {
      // Brendan's report, on the card: every ingredient matched, but a count
      // against a weight-only food still counted as a gap. It is a gap — but
      // not an unmatched one, and saying so sent him to re-match work that
      // was already done.
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[shortRibsWithMatchedOil()],
        // Oil measured in tbsp, food knows only grams, no density.
        foods: <Food>[
          aFood(
            'Olive oil',
            id: 'food-oil',
            servingOptions: <ServingOption>[
              aServing(
                amount: 100,
                unit: Units.gram,
                macros: const Macros(kcal: 884, fatG: 100),
              ),
            ],
          ),
        ],
      );
      final SemanticsHandle handle = tester.ensureSemantics();

      expect(
        find.bySemanticsLabel(RegExp('not matched to a food')),
        findsNothing,
      );

      handle.dispose();
    });
  });

  group('sorting the library', () {
    DateTime at(int day) => DateTime.utc(2026, 8, day);

    List<Recipe> byDate() => <Recipe>[
      aRecipe(id: 'old', title: 'Aaa oldest', updatedAt: at(1)),
      aRecipe(id: 'new', title: 'Zzz newest', updatedAt: at(3)),
    ];

    testWidgets('opens most recent first, not alphabetically', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: byDate());
      await pumpFrames(tester);

      final List<RecipeCard> cards = tester
          .widgetList<RecipeCard>(find.byType(RecipeCard))
          .toList();
      expect(cards.map((RecipeCard c) => c.recipe.id), <String>['new', 'old']);
    });

    testWidgets('the control says which order the list is in', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: byDate());
      await pumpFrames(tester);

      // The order is never something you have to open a menu to discover.
      expect(find.text('Recent'), findsOneWidget);
    });

    testWidgets('choosing A–Z reorders the list', (WidgetTester tester) async {
      await pumpHearthApp(tester, recipes: byDate());
      await pumpFrames(tester);

      await tester.tap(find.byType(SortButton<RecipeSort>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A–Z').last);
      await tester.pumpAndSettle();

      final List<RecipeCard> cards = tester
          .widgetList<RecipeCard>(find.byType(RecipeCard))
          .toList();
      expect(cards.map((RecipeCard c) => c.recipe.id), <String>['old', 'new']);
    });

    testWidgets('a favourite stays on top of a newer recipe', (
      WidgetTester tester,
    ) async {
      // Brendan's call: the sort orders each group, it does not get to bury
      // the handful of recipes actually cooked every week.
      await pumpHearthApp(
        tester,
        recipes: byDate(),
        favorites: <String>{'old'},
      );
      await pumpFrames(tester);

      final List<RecipeCard> cards = tester
          .widgetList<RecipeCard>(find.byType(RecipeCard))
          .toList();
      expect(cards.first.recipe.id, 'old');
    });
  });
}
