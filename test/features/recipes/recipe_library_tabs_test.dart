import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_spacing.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/recipe_query.dart';
import 'package:hearth/features/recipes/recipe_filter_bar.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The library's scope tabs (spec §5.2, §6.3, and the November 2026
/// templates).
///
/// All and Favourites are two states of one control. The rail before them
/// had no "everything" to press: turning a narrowing off meant finding the
/// lit chip and tapping it a second time, which is a different gesture from
/// choosing where you are — and on a screen you arrive at already narrowed,
/// there was nothing on it that said "show me the lot".
void main() {
  List<Recipe> library() => <Recipe>[
    aRecipe(id: 'ribs', title: 'Braised short ribs', cuisine: 'French'),
    aRecipe(id: 'tacos', title: 'Tuesday tacos', cuisine: 'Mexican'),
    aRecipe(id: 'sushi', title: 'Hand rolls', cuisine: 'Japanese'),
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
      favorites: <String>{'sushi'},
    );
    await pumpFrames(tester, frames: 12);
  }

  RecipeFilter filterOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first))
          .read(recipeFilterProvider);

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await pumpFrames(tester, frames: 12);
  }

  /// The box that draws the chosen tab's rule. The tab's own, not an
  /// ancestor's: `.first` walks outwards from the word.
  BoxDecoration ruleUnder(WidgetTester tester, String label) =>
      tester
              .widget<DecoratedBox>(
                find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration;

  testWidgets('the library opens on All, showing everything', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester);

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(filterOf(tester).favoritesOnly, isFalse);
    expect(find.text('Braised short ribs'), findsOneWidget);
    expect(find.text('Hand rolls'), findsOneWidget);
  });

  testWidgets('Favourites narrows to them, and All brings the rest back', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester);

    await tapTab(tester, 'Favorites');
    expect(filterOf(tester).favoritesOnly, isTrue);
    expect(find.text('Hand rolls'), findsOneWidget);
    expect(find.text('Braised short ribs'), findsNothing);

    await tapTab(tester, 'All');
    expect(filterOf(tester).favoritesOnly, isFalse);
    expect(find.text('Braised short ribs'), findsOneWidget);
  });

  testWidgets('and pressing the tab you are on leaves you on it', (
    WidgetTester tester,
  ) async {
    // The reason the tabs set the scope rather than toggling it. A toggle
    // here would make "Favourites" mean "everything" on every second press
    // — the control would be reporting one thing and doing the opposite.
    await openLibrary(tester);

    await tapTab(tester, 'Favorites');
    await tapTab(tester, 'Favorites');
    expect(filterOf(tester).favoritesOnly, isTrue);

    await tapTab(tester, 'All');
    await tapTab(tester, 'All');
    expect(filterOf(tester).favoritesOnly, isFalse);
  });

  testWidgets('the chosen tab is marked by a rule, not only by a colour', (
    WidgetTester tester,
  ) async {
    // §6.3: never colour alone. The rule survives a greyscale print and a
    // simulation for deuteranopia; a tinted word does not.
    await openLibrary(tester);

    expect(
      (ruleUnder(tester, 'All').border! as Border).bottom.color,
      isNot(Colors.transparent),
      reason: 'the chosen tab carries no rule',
    );
    expect(
      (ruleUnder(tester, 'Favorites').border! as Border).bottom.color,
      Colors.transparent,
      reason: 'a tab that is not chosen is wearing the chosen tab\'s rule',
    );

    await tapTab(tester, 'Favorites');

    expect(
      (ruleUnder(tester, 'Favorites').border! as Border).bottom.color,
      isNot(Colors.transparent),
    );
    expect(
      (ruleUnder(tester, 'All').border! as Border).bottom.color,
      Colors.transparent,
    );
  });

  testWidgets('and the weight says it a third time', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester);

    final FontWeight? chosen = tester
        .widget<Text>(find.text('All'))
        .style
        ?.fontWeight;
    final FontWeight? other = tester
        .widget<Text>(find.text('Favorites'))
        .style
        ?.fontWeight;

    expect(chosen, isNotNull);
    expect(
      chosen!.value,
      greaterThan(other!.value),
      reason: 'the chosen tab is drawn no heavier than the others',
    );
  });

  testWidgets('a screen reader is told which one is chosen', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await openLibrary(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('All')),
      isSemantics(label: 'All', isSelected: true, isButton: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Favorites')),
      isSemantics(label: 'Favorites', isSelected: false),
    );

    // Filters is in the row and is not a scope: it opens a sheet. Announcing
    // it as unselected would invite somebody to look for a state it has not
    // got.
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Filters'))),
      isNot(isSemantics(isSelected: true)),
    );

    handle.dispose();
  });

  testWidgets('every tab is big enough to hit', (WidgetTester tester) async {
    // "All" is three characters, and its word is narrower than a fingertip
    // — so the floor is on both axes. The §6.3 sweep measures both
    // guidelines, and 44 passes one of them.
    await openLibrary(tester);

    for (final String label in <String>['All', 'Favorites', 'Filters']) {
      final Size size = tester.getSize(
        find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first,
      );
      expect(
        size.height,
        greaterThanOrEqualTo(HearthTouch.androidTarget),
        reason: '$label is $size',
      );
      expect(
        size.width,
        greaterThanOrEqualTo(HearthTouch.androidTarget),
        reason: '$label is $size',
      );
    }
  });

  testWidgets('the sort stays on the screen rather than behind Filters', (
    WidgetTester tester,
  ) async {
    // It is not a narrowing: it hides nothing and excludes nothing. Behind
    // the button the order the list is in — the one thing it exists to state
    // — would be invisible until somebody went looking for it in a sheet
    // called Filters.
    await openLibrary(tester);

    expect(
      find.descendant(
        of: find.byType(RecipeFilterBar),
        matching: find.text(RecipeSort.recent.label),
      ),
      findsOneWidget,
    );
  });
}
