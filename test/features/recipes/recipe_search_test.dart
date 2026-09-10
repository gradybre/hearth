import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/collection_store.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

List<Recipe> library() => <Recipe>[
  aRecipe(
    id: 'ribs',
    title: 'Braised short ribs',
    cuisine: 'French',
    tags: <String>['sunday'],
    cookTime: const Duration(hours: 4),
    sections: <RecipeSection>[aSection(id: 'sec-ribs')],
  ),
  aRecipe(
    id: 'padseeew',
    title: 'Pad see ew',
    cuisine: 'Thai',
    tags: <String>['weeknight'],
    cookTime: const Duration(minutes: 20),
    sections: <RecipeSection>[aSection(id: 'sec-pad')],
  ),
];

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await pumpFrames(tester);
}

/// Taps something in the rail — one of the two toggles, or Filters itself.
Future<void> tapChip(WidgetTester tester, String label) async {
  final Finder chip = find.text(label).last;
  await tester.ensureVisible(chip);
  await pumpFrames(tester);
  await tester.tap(chip);
  await pumpFrames(tester, frames: 12);
}

/// Toggles one filter from behind the Filters button, and closes the sheet.
///
/// Everything but the two rail toggles lives there now: a chip per cuisine,
/// per tag and per cookbook made the rail grow with the library (review P6).
Future<void> pickFilter(WidgetTester tester, String label) async {
  // "Filters" while nothing behind it is on, "Filters (2)" once something is.
  final Finder button = find.textContaining(RegExp(r'^Filters')).last;
  await tester.ensureVisible(button);
  await pumpFrames(tester);
  await tester.tap(button);
  await pumpFrames(tester, frames: 12);

  await tapChip(tester, label);
  await tapChip(tester, 'Done');
}

void main() {
  group('search', () {
    testWidgets('narrows the library as you type', (WidgetTester tester) async {
      await pumpHearthApp(tester, recipes: library());
      await pumpFrames(tester);
      expect(find.byType(RecipeCard), findsNWidgets(2));

      await type(tester, 'pad');

      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Pad see ew'), findsOneWidget);
    });

    testWidgets('says nothing matched instead of looking empty', (
      WidgetTester tester,
    ) async {
      // An empty list with three chips lit is how people conclude their
      // recipes have been deleted.
      await pumpHearthApp(tester, recipes: library());
      await type(tester, 'zzzz');

      expect(find.text('No recipes match'), findsOneWidget);
      expect(find.textContaining('zzzz'), findsWidgets);
      expect(find.text('Clear search and filters'), findsOneWidget);
    });

    testWidgets('clearing brings everything back', (WidgetTester tester) async {
      await pumpHearthApp(tester, recipes: library());
      await type(tester, 'zzzz');
      await tester.tap(find.text('Clear search and filters'));
      await pumpFrames(tester);

      expect(find.byType(RecipeCard), findsNWidgets(2));
    });

    testWidgets('the search bar stays on screen when nothing matches', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: library());
      await type(tester, 'zzzz');

      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'hiding the box would strand the user in their own filter',
      );
    });
  });

  group('filter chips', () {
    testWidgets('a cuisine chip keeps only that cuisine', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: library());
      await pumpFrames(tester);

      await pickFilter(tester, 'Thai');

      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Pad see ew'), findsOneWidget);
    });

    testWidgets('chips from different dimensions narrow together', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: library());
      await pumpFrames(tester);

      await pickFilter(tester, 'Thai');
      await pickFilter(tester, 'Under 30 min');
      expect(find.byType(RecipeCard), findsOneWidget);

      // French and under 30 minutes is nothing in this library.
      await pickFilter(tester, 'Thai');
      await pickFilter(tester, 'French');
      expect(find.text('No recipes match'), findsOneWidget);
    });

    testWidgets('a lit chip can be tapped off again', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: library());
      await pumpFrames(tester);

      await pickFilter(tester, 'Thai');
      expect(find.byType(RecipeCard), findsOneWidget);

      await pickFilter(tester, 'Thai');
      expect(find.byType(RecipeCard), findsNWidgets(2));
    });

    testWidgets('what is applied is named where you can see it', (
      WidgetTester tester,
    ) async {
      // The button this replaced was all-or-nothing and said only how many:
      // undoing one of three meant clearing all three and setting two again.
      await pumpHearthApp(tester, recipes: library());
      await pumpFrames(tester);

      await pickFilter(tester, 'Thai');
      expect(find.text('Cuisine · Thai'), findsOneWidget);

      await pickFilter(tester, 'Under 30 min');
      expect(find.text('Under 30 min'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('a collection chip is offered for each cookbook', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: library(),
        collections: <CollectionSummary>[
          // Deliberately not 'Weeknight': that is also a tag in this
          // library, and a cookbook chip and a tag chip with the same name
          // are indistinguishable by text alone.
          const CollectionSummary(
            id: 'paella',
            name: 'Paella experiments',
            sortOrder: 0,
            recipeIds: <String>{'padseeew'},
          ),
        ],
      );
      await pumpFrames(tester);

      await pickFilter(tester, 'Paella experiments');

      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Pad see ew'), findsOneWidget);
    });
  });

  group('favourites', () {
    testWidgets('favourites sort above the rest', (WidgetTester tester) async {
      await pumpHearthApp(
        tester,
        recipes: library(),
        favorites: <String>{'padseeew'},
      );
      await pumpFrames(tester);

      final List<RecipeCard> cards = tester
          .widgetList<RecipeCard>(find.byType(RecipeCard))
          .toList();
      expect(cards.first.recipe.id, 'padseeew');
    });

    testWidgets('the favourites chip hides everything else', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: library(),
        favorites: <String>{'padseeew'},
      );
      await pumpFrames(tester);

      await tapChip(tester, 'Favourites');

      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Pad see ew'), findsOneWidget);
    });

    testWidgets('a favourite is announced, not just coloured', (
      WidgetTester tester,
    ) async {
      // Colour alone would leave a screen reader with no way to tell the
      // hearted recipe from the rest (spec §6.3).
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpHearthApp(
        tester,
        recipes: library(),
        favorites: <String>{'padseeew'},
      );
      await pumpFrames(tester);

      expect(
        find.bySemanticsLabel(RegExp('Pad see ew.*Favourite')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('macro chips', () {
    testWidgets('explain why unmatched recipes are excluded', (
      WidgetTester tester,
    ) async {
      // Every recipe in this fixture library has unmatched ingredients, so a
      // calorie chip empties the screen. Without a word of explanation that
      // reads as the library having broken.
      await pumpHearthApp(tester, recipes: library());
      await pumpFrames(tester);

      await pickFilter(tester, 'Under 600 kcal');

      expect(find.text('No recipes match'), findsOneWidget);
      expect(find.textContaining('not all matched to foods'), findsOneWidget);
    });

    testWidgets('say nothing about matching when no macro chip is lit', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, recipes: library());
      await type(tester, 'zzzz');

      expect(find.textContaining('not all matched to foods'), findsNothing);
    });
  });
}
