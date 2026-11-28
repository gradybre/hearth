import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/recipe_art.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/recipe_icon.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// The picture a library row wears, and the order it chooses one in
/// (spec §5.2, §6.3).
///
/// Three sources, from the one that knows most about the recipe to the one
/// that knows least: a photograph of this dish, this recipe's own sketch of
/// itself, and the house's drawing of the category. The last only ever
/// fills a slot that would have been empty.
void main() {
  testWidgets('a recipe with its own sketch keeps it', (
    WidgetTester tester,
  ) async {
    // The artwork is the fallback, not a replacement: a sketch drawn for
    // this recipe beats a drawing of its category.
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[
        aRecipe(
          id: 'stew',
          title: 'Weeknight chilli',
          iconSvg:
              '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
              '<path d="M4 12 L20 12" fill="none" stroke="currentColor"/>'
              '</svg>',
        ),
      ],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester, frames: 12);

    expect(find.byType(RecipeIcon), findsOneWidget);
  });

  testWidgets('and one with nothing draws nothing while nothing is drawn', (
    WidgetTester tester,
  ) async {
    // The plumbing ships before the pictures. Until a drawing exists the
    // row looks exactly as it did — no gap, no placeholder, no broken
    // image, and no asset asked for that is not there.
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[aRecipe(id: 'stew', title: 'Weeknight chilli')],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester, frames: 12);

    expect(find.byType(RecipeIcon), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('the widget itself', () {
    testWidgets('draws nothing for a category with no drawing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RecipeArt(artworkId: 'stew-pot', size: 40, shipped: <String>{}),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and nothing at all when nothing matched', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: RecipeArt(artworkId: null, size: 40)),
      );

      expect(find.byType(Image), findsNothing);
    });

    test('knows where a drawing would live', () {
      // The brief tells the artist to name files exactly this way, so the
      // two have to agree in one direction at least.
      expect(RecipeArt.assetFor('stew-pot'), 'assets/art/stew-pot.webp');
    });
  });
}
