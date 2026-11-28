import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';
import 'package:hearth/features/recipes/recipe_photo.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Two recipes, newest first, so "the first one" is a fixed thing.
List<Recipe> twoRecipes() => <Recipe>[
  aRecipe(
    id: 'first',
    title: 'Chicken pot pie stew',
    servings: 12,
    updatedAt: DateTime.utc(2026, 8, 3),
  ),
  aRecipe(
    id: 'second',
    title: 'Weeknight chilli',
    servings: 4,
    updatedAt: DateTime.utc(2026, 8, 1),
  ),
];

void main() {
  group('the first recipe, drawn large (templates, §6.1)', () {
    testWidgets('leads with its photograph when it has one', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: twoRecipes(),
        photos: const <String, String>{'first': 'first.jpg'},
      );
      await pumpFrames(tester);

      final RecipeCard first = tester
          .widgetList<RecipeCard>(find.byType(RecipeCard))
          .first;
      expect(first.recipe.id, 'first');
      expect(first.hero, isTrue);
      expect(
        find.descendant(
          of: find.byType(RecipeCard).first,
          matching: find.byType(RecipePhoto),
        ),
        findsOneWidget,
      );
    });

    testWidgets('and stays an ordinary row when it has none', (
      WidgetTester tester,
    ) async {
      // A hero is a photograph. Without one it would be a grey rectangle
      // the height of a hand, above a title that fits on one line — worse
      // than the row it replaced, and nothing on screen to say why.
      await pumpHearthApp(tester, recipes: twoRecipes());
      await pumpFrames(tester);

      for (final RecipeCard card in tester.widgetList<RecipeCard>(
        find.byType(RecipeCard),
      )) {
        expect(card.hero, isFalse);
      }
    });

    testWidgets('a photograph on the second recipe does not promote it', (
      WidgetTester tester,
    ) async {
      // The hero is the top of the list, not a prize for having a picture:
      // promoting the second recipe would reorder the library behind the
      // sort the person chose.
      await pumpHearthApp(
        tester,
        recipes: twoRecipes(),
        photos: const <String, String>{'second': 'second.jpg'},
      );
      await pumpFrames(tester);

      for (final RecipeCard card in tester.widgetList<RecipeCard>(
        find.byType(RecipeCard),
      )) {
        expect(card.hero, isFalse);
      }
    });

    testWidgets('the hero is still one labelled button for a screen reader', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: twoRecipes(),
        photos: const <String, String>{'first': 'first.jpg'},
      );
      await pumpFrames(tester);
      final SemanticsHandle handle = tester.ensureSemantics();

      expect(
        find.bySemanticsLabel(RegExp('Chicken pot pie stew. Serves 12')),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}
