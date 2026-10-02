@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../features/recipes/restaurant_usual_fixtures.dart';
import '../support/app_harness.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _scenes = <Scene>[
  Scene(name: 'restaurant-usuals-phone'),
  Scene(name: 'restaurant-usuals-dark', brightness: Brightness.dark),
  Scene(name: 'restaurant-usuals-small-3x', size: Size(320, 568), textScale: 3),
  Scene(name: 'restaurant-usuals-desktop', size: Size(1280, 900)),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _scenes) {
    testWidgets('${scene.name}: usual actions and customization receipt', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
        foods: usualMenuFoods(),
        recipes: <Recipe>[savedUsual()],
      );
      final SweepTools tools = SweepTools(tester);
      await tools.tab('Recipes');
      await tools.reach(find.text('Add recipe'));
      await tools.reach(find.text('Eat out'));
      await tools.reach(find.text('Corner Kitchen'));
      await tools.bring(find.byKey(const Key('usual-log-saved-usual')));
      await _capture(tester, scene, 'actions');
      await tools.reach(find.byKey(const Key('usual-log-saved-usual')));
      await tools.bring(find.text('Which day and meal?'));
      await _capture(tester, scene, 'destination');
      await tools.reach(find.text('Cancel'));
      await tools.reach(find.byKey(const Key('usual-customize-saved-usual')));
      await _capture(tester, scene, 'base');
      await tools.reach(find.text('Lettuce wrap'));
      await tools.reach(find.byTooltip('Take Lettuce out'));
      await _backTo(tester, find.text('Added'));
      await _capture(tester, scene, 'added');
      await tools.bring(find.text('Removed'));
      await _capture(tester, scene, 'removed');
      await tools.bring(find.byKey(const Key('usual-review-variation')));
      await _capture(tester, scene, 'review-actions');
      await tools.bring(find.byTooltip('One more'));
      await _capture(tester, scene, 'portion-controls');
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
