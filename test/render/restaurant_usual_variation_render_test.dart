@Tags(<String>['render'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/week.dart';

import '../features/recipes/restaurant_usual_fixtures.dart';
import '../support/app_harness.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _scenes = <Scene>[
  Scene(name: 'restaurant-variation-phone'),
  Scene(name: 'restaurant-variation-dark', brightness: Brightness.dark),
  Scene(
    name: 'restaurant-variation-small-3x',
    size: Size(320, 568),
    textScale: 3,
  ),
  Scene(
    name: 'restaurant-variation-small-dark-3x',
    size: Size(320, 568),
    textScale: 3,
    brightness: Brightness.dark,
  ),
  Scene(name: 'restaurant-variation-desktop', size: Size(1280, 900)),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _scenes) {
    testWidgets('${scene.name}: separate recipe and personal portion review', (
      WidgetTester tester,
    ) async {
      final Recipe original = savedUsual().copyWith(
        photoUrl: 'fixture-household/saved-usual/hero.jpg',
        iconSvg:
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">'
            '<path d="M4 12h16M5 14c2 6 12 6 14 0"/></svg>',
      );
      final StreamController<List<Recipe>> updates =
          StreamController<List<Recipe>>.broadcast();
      addTearDown(() => unawaited(updates.close()));
      final HearthDatabase db = await pumpHearthApp(
        tester,
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
        foods: usualMenuFoods(),
        recipes: <Recipe>[original],
        recipeStream: () async* {
          yield <Recipe>[original];
          yield* updates.stream;
        }(),
        selectedDate: addDays(DateTime.now(), -2),
      );
      final SweepTools tools = SweepTools(tester);
      await tools.tab('Plan');
      await tools.reach(find.byTooltip('Add to dinner'));
      await tools.reach(find.text('Ate out — build it from a menu'));
      await tools.reach(find.text('Corner Kitchen'));
      await tools.reach(find.byKey(const Key('usual-customize-saved-usual')));
      await tools.reach(find.text('Lettuce wrap'));
      await _backTo(tester, find.byKey(const Key('usual-review-variation')));
      await tools.reach(find.byKey(const Key('usual-review-variation')));
      await _capture(tester, scene, 'intro');
      await tools.bring(
        find.text('The photo from your saved usual will be kept.'),
      );
      await _capture(tester, scene, 'artwork');
      await tools.bring(find.byKey(const Key('variation-save')));
      await _capture(tester, scene, 'save-review');

      // The input stays full-size with a keyboard-sized inset, and the long
      // action remains reachable through the same outer scrolling content.
      final Finder title = find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField &&
            widget.controller?.text == 'Our usual dinner (variation)',
      );
      await _backTo(tester, title);
      await tester.tap(title);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await pumpFrames(tester);
      await tools.bring(find.byKey(const Key('variation-save')));
      await _capture(tester, scene, 'keyboard-save-review');
      await tools.reach(find.byKey(const Key('variation-save')));
      tester.view.viewInsets = const FakeViewPadding();
      final List<RecipeRow> rows = await db.select(db.recipes).get();
      expect(rows, hasLength(2));
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      final Recipe variation = (await RecipeStore(
        db,
      ).byId(rows.singleWhere((RecipeRow row) => row.id != original.id).id))!;
      updates.add(<Recipe>[original, variation]);
      await pumpFrames(tester, frames: 16);
      await _capture(tester, scene, 'portion');
      await tools.bring(find.text('Log it'));
      await _capture(tester, scene, 'portion-action');
      expect(tester.takeException(), isNull);
    }, skip: !renderingGallery);
  }
}

Future<void> _capture(WidgetTester tester, Scene scene, String suffix) async {
  expect(tester.takeException(), isNull);
  await writeScene(tester, Scene(name: '${scene.name}-$suffix'));
}

Future<void> _backTo(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      target,
      SweepTools.verticalScroller,
      const Offset(0, 180),
      maxIteration: 100,
    );
  }
  await tester.ensureVisible(target);
  await pumpFrames(tester);
}
