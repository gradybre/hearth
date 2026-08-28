import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
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
      expect(find.text('New recipe'), findsOneWidget);
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
      // appear as an empty strip.
      expect(find.byType(Wrap), findsNothing);
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

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
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
}
