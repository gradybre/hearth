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
  testWidgets('a drawn kind beats the recipe\'s own sketch', (
    WidgetTester tester,
  ) async {
    // The order was the other way round at first, on the reasoning that a
    // drawing of this recipe beats a drawing of its category. That holds
    // only while the specific one is good — and side by side on a phone it
    // is not, because the sketches are a language model's doodle and the
    // drawings are engravings.
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[
        aRecipe(
          id: 'chilli',
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

    expect(find.byType(RecipeArt), findsOneWidget);
    expect(find.byType(RecipeIcon), findsNothing);
  });

  testWidgets('and the sketch still stands in for a kind nobody has drawn', (
    WidgetTester tester,
  ) async {
    // Which is most of them, and the job the sketch is better suited to.
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[
        aRecipe(
          id: 'x',
          title: 'Leftovers from Tuesday',
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
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a recipe whose kind has been drawn wears the drawing', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[aRecipe(id: 'chilli', title: 'Weeknight chilli')],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester, frames: 12);

    expect(find.byType(RecipeArt), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('and one whose kind has not draws nothing at all', (
    WidgetTester tester,
  ) async {
    // Not a gap, not a placeholder, not a broken image: the set of
    // drawings runs behind the registry on purpose, and a row for a kind
    // nobody has drawn looks exactly as it did before any of this.
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[aRecipe(id: 'x', title: 'Leftovers from Tuesday')],
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
      expect(RecipeArt.assetFor('stew-pot'), 'assets/art/stew-pot.png');
    });
  });
}
