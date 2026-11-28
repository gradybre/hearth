@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/recipe_art.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/recipe_artwork.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';
import 'gallery.dart';

/// One recipe per drawing that has shipped (spec §5.2).
///
/// A picture of the artwork in the place it actually appears — a library
/// row, at the size a library row gives it — rather than in a contact
/// sheet. It is also the check that the drawings are reachable at all: a
/// drawing whose id nothing matches, or whose file never made it into the
/// bundle, shows up here as a row with no picture on it.
///
/// A title per drawing, chosen the way a person would name the dish. If a
/// keyword change ever stops one of these finding its drawing, that is
/// worth knowing — these are the plainest names the categories have.
const Map<String, String> _dishes = <String, String>{
  'chilli-bowl': 'Weeknight chilli',
  'porridge-jar': 'Blueberry overnight oats',
  'pot-pie': 'Chicken pot pie',
  'ramen-bowl': 'Tonkotsu ramen',
  'soup-bowl': 'Tomato soup',
  'stew-pot': 'Beef stew',
};

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  test('every drawing that has shipped has a dish here', () {
    // Otherwise the picture below quietly stops covering the set.
    expect(_dishes.keys.toSet(), kArtworkShipped);
  });

  test('and each of those dishes finds its own drawing', () {
    for (final MapEntry<String, String> dish in _dishes.entries) {
      expect(
        pickRecipeArtwork(title: dish.value),
        dish.key,
        reason: '"${dish.value}" no longer finds ${dish.key}',
      );
    }
  });

  for (final Scene scene in <Scene>[
    const Scene(name: 'recipe-artwork'),
    const Scene(name: 'recipe-artwork-dark', brightness: Brightness.dark),
    const Scene(name: 'recipe-artwork-desktop', size: Size(1280, 900)),
  ]) {
    testWidgets('${scene.name}: a library of drawn dishes', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        size: scene.size,
        brightness: scene.brightness,
        recipes: <Recipe>[
          for (final MapEntry<String, String> dish in _dishes.entries)
            aRecipe(id: dish.key, title: dish.value, servings: 4),
        ],
      );
      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester, frames: 12);

      expect(
        find.byType(RecipeArt),
        findsNWidgets(_dishes.length),
        reason: 'a dish is not wearing its drawing',
      );

      // Decoded by hand before the picture is taken. A widget test paints
      // an asset image as nothing at all until its bytes have been read,
      // and reading them is asynchronous — so the first run of this wrote
      // six rows with six blank squares and still passed every assertion
      // above. The drawings are reachable; they were simply not there yet.
      await tester.runAsync(() async {
        for (final String id in _dishes.keys) {
          await precacheImage(
            AssetImage(RecipeArt.assetFor(id)),
            tester.element(find.byType(RecipeArt).first),
          );
        }
      });
      await pumpFrames(tester, frames: 4);

      await writeScene(tester, scene);
    });
  }
}
