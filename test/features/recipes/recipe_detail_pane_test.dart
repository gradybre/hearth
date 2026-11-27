import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/recipe_detail_screen.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The library's detail pane (spec §5.2, §6.2, and the November 2026 desktop
/// template).
///
/// The screenshot that prompted the redesign was the recipe library on a
/// 1280pt window: a correct layout by the letter of §6.2, a sidebar and one
/// bounded column, and the right half of the window empty paper. Above
/// `HearthLayout.detailPaneBreakpoint` the recipe opens beside the list
/// instead of over it.
///
/// `/recipe/:id` is still a real route. The pane is a layout, not a second
/// way of navigating.
void main() {
  // Wide enough that the section has room for two columns once the sidebar
  // has taken its 208 points: 1280 - 209 = 1071.
  const Size desktop = Size(1280, 900);

  // The sidebar is showing here and the pane is not: 1100 - 209 = 891, which
  // is one reading column and not two. The case that proves the breakpoint
  // is measured on the section rather than on the window.
  const Size halfScreen = Size(1100, 900);

  List<Recipe> library() => <Recipe>[
    aRecipe(id: 'chilli', title: 'Weeknight chilli', servings: 4),
    aRecipe(id: 'oats', title: 'Blueberry overnight oats'),
  ];

  Future<void> openLibrary(WidgetTester tester, {Size size = desktop}) async {
    await pumpHearthApp(tester, size: size, recipes: library());
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('a wide window opens the recipe beside the list', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester);

    await tester.tap(find.text('Weeknight chilli'));
    await pumpFrames(tester, frames: 16);

    // Both at once is the whole point: the list did not go anywhere.
    expect(find.byType(RecipeLibraryScreen), findsOneWidget);
    expect(find.text('Blueberry overnight oats'), findsOneWidget);
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(
      tester
          .widget<RecipeDetailScreen>(find.byType(RecipeDetailScreen))
          .embedded,
      isTrue,
    );
    // Nothing to go back to: the list it was opened from is on the screen.
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('and it opens on nothing, not on whatever is first', (
    WidgetTester tester,
  ) async {
    // A window wide enough for two columns is not a reason to open a recipe
    // nobody asked for — and the first row of a list sorted by "recent" is a
    // different recipe every week.
    await openLibrary(tester);

    expect(find.text('Choose a recipe'), findsOneWidget);
    expect(find.byType(RecipeDetailScreen), findsNothing);
  });

  testWidgets('the open row says so, and not only in a colour', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await openLibrary(tester);
    await tester.tap(find.text('Weeknight chilli'));
    await pumpFrames(tester, frames: 16);

    // §6.3: the bar down its leading edge is drawn as a ground the card is
    // inset from, so the row is 4 points narrower than its neighbour. That
    // difference survives a greyscale print; a tint does not.
    final double open = tester
        .getSize(
          find
              .ancestor(
                of: find.text('Weeknight chilli'),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;
    final double shut = tester
        .getSize(
          find
              .ancestor(
                of: find.text('Blueberry overnight oats'),
                matching: find.byType(Material),
              )
              .first,
        )
        .width;
    expect(open, lessThan(shut), reason: 'the open row carries no bar');

    // And said out loud for somebody who is not looking at it.
    // The first of the two: the pane beside the list is showing the same
    // recipe and its title answers to the same words, and the list comes
    // first in the Row. If that ever stopped being true this would be
    // reading the pane's title, which carries no selected state — so the
    // assertion catches the mix-up rather than quietly passing on it.
    final Finder named = find.bySemanticsLabel(RegExp('^Weeknight chilli'));
    expect(named, findsNWidgets(2));
    expect(tester.getSemantics(named.first), isSemantics(isSelected: true));

    handle.dispose();
  });

  testWidgets('choosing another recipe replaces the one in the pane', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester);
    await tester.tap(find.text('Weeknight chilli'));
    await pumpFrames(tester, frames: 16);
    expect(find.text('Serves 4'), findsWidgets);

    await tester.tap(find.text('Blueberry overnight oats'));
    await pumpFrames(tester, frames: 16);

    // The pane is keyed by recipe, so it is rebuilt rather than handed the
    // previous recipe's state — the servings it has been scaled to above
    // all, which would open a 12-serving stew as a doubled bowl of oats.
    expect(
      tester
          .widget<RecipeDetailScreen>(find.byType(RecipeDetailScreen))
          .recipeId,
      'oats',
    );
  });

  testWidgets('a window with no room for two columns still pushes', (
    WidgetTester tester,
  ) async {
    // The sidebar is showing at this width and the pane is not. Measured on
    // what the section has, not on the window.
    await openLibrary(tester, size: halfScreen);

    expect(find.text('Choose a recipe'), findsNothing);
    await tester.tap(find.text('Weeknight chilli'));
    await pumpFrames(tester, frames: 16);

    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(
      tester
          .widget<RecipeDetailScreen>(find.byType(RecipeDetailScreen))
          .embedded,
      isFalse,
    );
    // Pushed over the list, so there is a way back to it.
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('a phone pushes too, as it always has', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester, size: const Size(390, 844));

    await tester.tap(find.text('Weeknight chilli'));
    await pumpFrames(tester, frames: 16);

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Blueberry overnight oats'), findsNothing);
  });
}
