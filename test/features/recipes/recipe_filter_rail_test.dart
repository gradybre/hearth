import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/widgets/sort_button.dart';
import 'package:hearth/data/local/collection_store.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/recipe_query.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_filter_bar.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The rail used to hold one chip per collection, per cuisine and per tag, in
/// a horizontal scroll view — so it grew with the library and was longest for
/// the person with the most to sift through (review P6).
///
/// These are the tests that pinned that. They are written against what is on
/// screen *and* against `recipeFilterProvider`, because a rail that looks
/// right while filtering nothing is the failure mode a pixel test cannot see.

/// A library with enough of every dimension that a chip-per-value rail runs
/// off the side of a desktop window: five cuisines, six tags, three
/// cookbooks.
List<Recipe> library() => <Recipe>[
  aRecipe(
    id: 'ribs',
    title: 'Braised short ribs',
    cuisine: 'French',
    tags: <String>['sunday', 'braise'],
    cookTime: const Duration(hours: 4),
    sections: <RecipeSection>[aSection(id: 'sec-ribs')],
  ),
  aRecipe(
    id: 'padseeew',
    title: 'Pad see ew',
    servings: 1,
    cuisine: 'Thai',
    tags: <String>['weeknight'],
    cookTime: const Duration(minutes: 20),
    sections: <RecipeSection>[
      aSection(
        id: 'sec-pad',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'chicken thigh',
            amount: 100,
            unit: Units.gram,
            sectionId: 'sec-pad',
            foodId: 'food-chicken',
          ),
        ],
      ),
    ],
  ),
  aRecipe(
    id: 'tacos',
    title: 'Tuesday tacos',
    cuisine: 'Mexican',
    tags: <String>['quick'],
    cookTime: const Duration(minutes: 25),
    sections: <RecipeSection>[aSection(id: 'sec-tacos')],
  ),
  aRecipe(
    id: 'sushi',
    title: 'Hand rolls',
    cuisine: 'Japanese',
    tags: <String>['fish'],
    sections: <RecipeSection>[aSection(id: 'sec-sushi')],
  ),
  aRecipe(
    id: 'pasta',
    title: 'Cacio e pepe',
    cuisine: 'Italian',
    tags: <String>['pasta'],
    sections: <RecipeSection>[aSection(id: 'sec-pasta')],
  ),
];

/// Matched so Pad see ew — and only Pad see ew — has macros to filter on.
Food chicken() => aFood(
  'Chicken thigh',
  id: 'food-chicken',
  servingOptions: <ServingOption>[
    aServing(
      amount: 100,
      unit: Units.gram,
      macros: const Macros(kcal: 165, proteinG: 31),
    ),
  ],
);

List<CollectionSummary> cookbooks() => <CollectionSummary>[
  // None of these share a name with a tag or a cuisine: a cookbook chip and
  // a tag chip wearing the same word are indistinguishable by text alone.
  const CollectionSummary(
    id: 'paella',
    name: 'Paella experiments',
    sortOrder: 0,
    recipeIds: <String>{'tacos'},
  ),
  const CollectionSummary(
    id: 'batch',
    name: 'Batch cooking',
    sortOrder: 1,
    recipeIds: <String>{'ribs'},
  ),
  const CollectionSummary(
    id: 'sunday-project',
    name: 'Sunday project',
    sortOrder: 2,
    recipeIds: <String>{'ribs'},
  ),
];

Future<void> openLibrary(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  await pumpHearthApp(
    tester,
    size: size,
    textScale: textScale,
    recipes: library(),
    foods: <Food>[chicken()],
    collections: cookbooks(),
  );
  await pumpFrames(tester, frames: 12);
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first));

RecipeFilter filterOf(WidgetTester tester) =>
    containerOf(tester).read(recipeFilterProvider);

/// What the library is showing, read from the provider rather than counted on
/// screen: the list is lazy, so the fifth card of five is never built at
/// 390x844 and counting cards would call a full library a filtered one.
List<String> shownIds(WidgetTester tester) => <String>[
  for (final Recipe recipe
      in containerOf(tester).read(filteredRecipesProvider).value ??
          const <Recipe>[])
    recipe.id,
];

/// Brings [finder] on screen and taps it.
Future<void> reach(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.last);
  await pumpFrames(tester, frames: 4);
  await tester.tap(finder.last);
  await pumpFrames(tester, frames: 12);
}

Future<void> openFilters(WidgetTester tester) async {
  await reach(tester, find.textContaining(RegExp(r'^Filters')));
}

Future<void> closeFilters(WidgetTester tester) async {
  await reach(tester, find.text('Done'));
}

/// Opens the sheet, taps one thing in it, and closes it again.
Future<void> pickInSheet(WidgetTester tester, String label) async {
  await openFilters(tester);
  await reach(tester, find.text(label));
  await closeFilters(tester);
}

void main() {
  group('the visible row (review P6)', () {
    testWidgets('is four controls however much is in the library', (
      WidgetTester tester,
    ) async {
      // The defect: one chip per collection, per cuisine and per tag, all in
      // the rail. Fourteen controls in this library, and more with every
      // recipe added.
      await openLibrary(tester);

      final Finder bar = find.byType(RecipeFilterBar);
      for (final String buried in <String>[
        'Thai',
        'French',
        'Weeknight',
        'Sunday',
        'Paella experiments',
        'Batch cooking',
        'Under 30 min',
        'Protein 30 g+',
        'Under 600 kcal',
      ]) {
        expect(
          find.descendant(of: bar, matching: find.text(buried)),
          findsNothing,
          reason: '"$buried" belongs behind Filters, not in the rail',
        );
      }

      // And what is left is exactly the four: sort, two toggles, Filters.
      final Finder row = find.byKey(const ValueKey('recipe-filter-controls'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byType(SortButton<RecipeSort>)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byType(Text)),
        findsNWidgets(4),
        reason: 'sort, Favourites, Eaten out, Filters — and nothing else',
      );
      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('Eaten out'), findsOneWidget);
    });

    testWidgets('does not scroll sideways inside the list that scrolls down', (
      WidgetTester tester,
    ) async {
      await openLibrary(tester);

      // Not "no horizontal Scrollable": the search field contains one of its
      // own for its editable, and always will. The rail's was a
      // SingleChildScrollView, and the rail wraps now instead.
      expect(
        find.descendant(
          of: find.byType(RecipeFilterBar),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
        reason: 'a sideways scroll inside a list that scrolls down',
      );
    });
  });

  group('everything still filters (spec §5.2)', () {
    testWidgets('a cuisine, from behind Filters', (WidgetTester tester) async {
      await openLibrary(tester);
      expect(shownIds(tester), hasLength(5));

      await pickInSheet(tester, 'Thai');

      expect(filterOf(tester).cuisines, <String>{'thai'});
      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Pad see ew'), findsOneWidget);
    });

    testWidgets('a tag', (WidgetTester tester) async {
      await openLibrary(tester);

      await pickInSheet(tester, 'Quick');

      expect(filterOf(tester).tags, <String>{'quick'});
      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Tuesday tacos'), findsOneWidget);
    });

    testWidgets('a cookbook', (WidgetTester tester) async {
      await openLibrary(tester);

      await pickInSheet(tester, 'Paella experiments');

      expect(filterOf(tester).collectionIds, <String>{'paella'});
      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Tuesday tacos'), findsOneWidget);
    });

    testWidgets('a time', (WidgetTester tester) async {
      await openLibrary(tester);

      await pickInSheet(tester, 'Under 30 min');

      expect(filterOf(tester).maxTotalTime, const Duration(minutes: 30));
      expect(find.byType(RecipeCard), findsNWidgets(2));
    });

    testWidgets('protein', (WidgetTester tester) async {
      await openLibrary(tester);

      await pickInSheet(tester, 'Protein 30 g+');

      expect(filterOf(tester).minProteinPerServing, 30);
      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Pad see ew'), findsOneWidget);
    });

    testWidgets('calories', (WidgetTester tester) async {
      await openLibrary(tester);

      await pickInSheet(tester, 'Under 600 kcal');

      expect(filterOf(tester).maxKcalPerServing, 600);
      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Pad see ew'), findsOneWidget);
    });

    testWidgets('and a lit one turns off again', (WidgetTester tester) async {
      await openLibrary(tester);

      await openFilters(tester);
      await reach(tester, find.text('Thai'));
      expect(filterOf(tester).cuisines, <String>{'thai'});
      await reach(tester, find.text('Thai'));
      await closeFilters(tester);

      expect(filterOf(tester).cuisines, isEmpty);
      expect(shownIds(tester), hasLength(5));
    });

    testWidgets('the two toggles stay in the rail', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: library(),
        foods: <Food>[chicken()],
        collections: cookbooks(),
        favorites: <String>{'sushi'},
      );
      await pumpFrames(tester, frames: 12);

      await reach(tester, find.text('Favourites'));

      expect(filterOf(tester).favoritesOnly, isTrue);
      expect(find.byType(RecipeCard), findsOneWidget);
      expect(find.text('Hand rolls'), findsOneWidget);
    });
  });

  group('the count on Filters', () {
    testWidgets('counts only what is behind it', (WidgetTester tester) async {
      await openLibrary(tester);
      expect(find.text('Filters'), findsOneWidget);

      // Favourites and Eaten out are in the rail, visibly lit. Counting them
      // behind a button that does not hold them would double-count them.
      await reach(tester, find.text('Favourites'));
      await reach(tester, find.text('Eaten out'));
      expect(
        find.text('Filters'),
        findsOneWidget,
        reason: 'neither toggle lives behind Filters',
      );

      await pickInSheet(tester, 'Thai');
      expect(find.text('Filters (1)'), findsOneWidget);

      await pickInSheet(tester, 'Under 30 min');
      expect(find.text('Filters (2)'), findsOneWidget);
    });

    testWidgets('and says the number rather than only lighting up', (
      WidgetTester tester,
    ) async {
      // Never colour alone (spec §6.3).
      await openLibrary(tester);
      await pickInSheet(tester, 'Thai');

      expect(find.text('Filters (1)'), findsOneWidget);
    });
  });

  group('what is applied is on screen', () {
    testWidgets('each applied filter is named below the rail', (
      WidgetTester tester,
    ) async {
      // The old rail showed this only by scrolling it to find the lit chips.
      await openLibrary(tester);

      await openFilters(tester);
      await reach(tester, find.text('Thai'));
      await reach(tester, find.text('Weeknight'));
      await closeFilters(tester);

      expect(find.text('Cuisine · Thai'), findsOneWidget);
      expect(find.text('Tag · Weeknight'), findsOneWidget);
    });

    testWidgets('its × removes just that one', (WidgetTester tester) async {
      await openLibrary(tester);

      await openFilters(tester);
      await reach(tester, find.text('Thai'));
      await reach(tester, find.text('Weeknight'));
      await closeFilters(tester);

      await reach(tester, find.text('Cuisine · Thai'));

      final RecipeFilter after = filterOf(tester);
      expect(after.cuisines, isEmpty);
      expect(after.tags, <String>{'weeknight'}, reason: 'the other one stays');
      expect(find.text('Cuisine · Thai'), findsNothing);
      expect(find.text('Tag · Weeknight'), findsOneWidget);
    });

    testWidgets('the toggles in the rail are named there too', (
      WidgetTester tester,
    ) async {
      // Clear all clears them, so a strip that did not name them would be
      // answering "what is narrowing this list" wrongly.
      await openLibrary(tester);
      await reach(tester, find.text('Favourites'));

      expect(find.text('Only favourites'), findsOneWidget);
    });

    testWidgets('and nothing is shown when nothing is applied', (
      WidgetTester tester,
    ) async {
      await openLibrary(tester);
      expect(find.text('Clear all'), findsNothing);
    });

    testWidgets('Clear all clears everything', (WidgetTester tester) async {
      await openLibrary(tester);

      await reach(tester, find.text('Favourites'));
      await openFilters(tester);
      await reach(tester, find.text('Thai'));
      await reach(tester, find.text('Under 30 min'));
      await reach(tester, find.text('Paella experiments'));
      await closeFilters(tester);

      await reach(tester, find.text('Clear all'));

      final RecipeFilter after = filterOf(tester);
      expect(after.activeCount, 0);
      expect(after.cuisines, isEmpty);
      expect(after.collectionIds, isEmpty);
      expect(after.maxTotalTime, isNull);
      expect(after.favoritesOnly, isFalse);
      expect(shownIds(tester), hasLength(5));
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('and the old all-or-nothing button is gone', (
      WidgetTester tester,
    ) async {
      await openLibrary(tester);
      await pickInSheet(tester, 'Thai');

      expect(find.textContaining('Clear 1 filter'), findsNothing);
    });
  });

  group('accessibility (spec §6.3)', () {
    testWidgets('the rail survives 3x text on a small phone', (
      WidgetTester tester,
    ) async {
      await openLibrary(tester, size: const Size(320, 568), textScale: 3.0);

      expect(tester.takeException(), isNull, reason: 'the rail overflowed');
    });

    testWidgets('and so does the applied strip beneath it', (
      WidgetTester tester,
    ) async {
      await openLibrary(tester, size: const Size(320, 568), textScale: 3.0);

      await reach(tester, find.text('Favourites'));
      await reach(tester, find.text('Eaten out'));

      expect(tester.takeException(), isNull);
    });

    testWidgets('every control in the rail carries a label', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await openLibrary(tester);

      // Tooltips are not discoverability on a touch screen, so each of these
      // is a word on the screen as well as a semantics label.
      expect(find.bySemanticsLabel('Favourites'), findsOneWidget);
      expect(find.bySemanticsLabel('Eaten out'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Filters')), findsOneWidget);

      handle.dispose();
    });

    testWidgets('and a removable chip says what tapping it does', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await openLibrary(tester);
      await pickInSheet(tester, 'Thai');

      expect(
        find.bySemanticsLabel('Remove filter, Cuisine · Thai'),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}
