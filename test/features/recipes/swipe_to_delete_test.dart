import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Removing a recipe from the shared library (spec §5.2, §4).
Future<void> openLibrary(WidgetTester tester, List<Recipe> recipes) async {
  await pumpHearthApp(tester, recipes: recipes);
  await pumpFrames(tester);
}

/// Swipes the row at a fixed point, the way a thumb does.
///
/// Not anchored to the card's own text: once the card slides, that text moves
/// with it and can leave the row entirely.
Future<void> swipe(WidgetTester tester, double dx) async {
  final Offset row = tester.getCenter(find.byType(RecipeCard).first);
  await tester.dragFrom(Offset(200, row.dy), Offset(dx, 0));
  await pumpFrames(tester, frames: 12);
}

void main() {
  testWidgets('deleting a row does not leave the next one hanging open', (
    WidgetTester tester,
  ) async {
    // The rows had no keys, so when a recipe left the list the element at that
    // index was reused for the one below — and its open state came with it.
    // Deleting the top recipe left the next one already swiped aside with its
    // delete showing.
    final StreamController<List<Recipe>> library =
        StreamController<List<Recipe>>();
    addTearDown(library.close);

    final Recipe ribs = aRecipe(title: 'Braised short ribs', id: 'ribs');
    final Recipe soup = aRecipe(title: 'Leek and potato soup', id: 'soup');

    await pumpHearthApp(tester, recipeStream: library.stream);
    library.add(<Recipe>[ribs, soup]);
    await pumpFrames(tester);

    await swipe(tester, -120);
    await tester.tap(find.widgetWithText(TextButton, 'Delete').first);
    await pumpFrames(tester, frames: 12);

    // The library now holds only the soup, exactly as a real delete leaves it.
    library.add(<Recipe>[soup]);
    await pumpFrames(tester, frames: 12);

    expect(find.text('Leek and potato soup'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Delete'))
          .onPressed,
      isNull,
      reason: 'the surviving recipe must not inherit the deleted one\'s swipe',
    );
  });

  testWidgets('delete is hidden until the card is swiped aside', (
    WidgetTester tester,
  ) async {
    // One flick must not remove something from a shared library. The swipe
    // uncovers the button; the button still has to be pressed.
    await openLibrary(tester, <Recipe>[aRecipe(title: 'Braised short ribs')]);

    final Finder delete = find.widgetWithText(TextButton, 'Delete');
    expect(tester.widget<TextButton>(delete).onPressed, isNull);

    await swipe(tester, -200);

    expect(tester.widget<TextButton>(delete).onPressed, isNotNull);
  });

  testWidgets('swiping back puts it away again', (WidgetTester tester) async {
    await openLibrary(tester, <Recipe>[aRecipe(title: 'Braised short ribs')]);

    await swipe(tester, -200);
    await swipe(tester, 200);

    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Delete'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('deleting offers an undo, because the delete is only a hide', (
    WidgetTester tester,
  ) async {
    await openLibrary(tester, <Recipe>[aRecipe(title: 'Braised short ribs')]);

    await swipe(tester, -200);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('Deleted Braised short ribs'), findsOneWidget);
    // Soft-deleted (§4), so undo restores the same recipe rather than making a
    // new one — every meal already logged against it still resolves.
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('deleting is reachable without the gesture', (
    WidgetTester tester,
  ) async {
    // A swipe is not something a screen reader user can discover (§6.3).
    await openLibrary(tester, <Recipe>[aRecipe(title: 'Braised short ribs')]);

    final SemanticsNode node = tester.getSemantics(
      find.byType(RecipeCard).first,
    );
    expect(
      node.getSemanticsData().customSemanticsActionIds,
      isNotNull,
      reason: 'delete must be offered as a semantics action',
    );
  });
}
