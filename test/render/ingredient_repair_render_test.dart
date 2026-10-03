@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/auth/local_auth_gateway.dart';

import '../features/foods/label_scan_test.dart' show FakeLabelReader;
import '../support/app_harness.dart';
import '../support/fixtures.dart';
import 'gallery.dart';

const _scenes = <Scene>[
  Scene(name: 'ingredient-repair-phone'),
  Scene(name: 'ingredient-repair-dark', brightness: Brightness.dark),
  Scene(name: 'ingredient-repair-desktop', size: Size(1280, 900)),
  Scene(name: 'ingredient-repair-small-3x', size: Size(320, 568), textScale: 3),
  Scene(
    name: 'ingredient-repair-small-dark-3x',
    size: Size(320, 568),
    textScale: 3,
    brightness: Brightness.dark,
  ),
];

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await pumpFrames(tester, frames: 20);
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });
  for (final scene in _scenes) {
    testWidgets('${scene.name}: every ingredient repair choice is reachable', (
      tester,
    ) async {
      await pumpHearthApp(
        tester,
        size: scene.size,
        brightness: scene.brightness,
        viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
        labelReader: FakeLabelReader(),
        foods: [
          aFoodPer100g(
            'White onion',
            id: 'onion',
            kcal: 40,
          ).withHousehold(LocalAuthGateway.account.householdId),
        ],
      );
      await addRecipeVia(tester, 'Write a recipe');
      final ingredients = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.hintText ?? '').startsWith('2 tbsp olive oil'),
      );
      await tester.enterText(ingredients, '2 tbsp white onion, finely chopped');
      await pumpFrames(tester, frames: 20);
      await _tap(tester, find.text('white onion, finely chopped'));
      await _tap(tester, find.text('White onion'));
      await _tap(tester, find.text('white onion, finely chopped'));
      // Model an OS text-size change while this real production sheet is open.
      tester.platformDispatcher.textScaleFactorTestValue = scene.textScale;
      await pumpFrames(tester, frames: 12);
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '${scene.name}-start'));
      final choices = <String>[
        'Add a serving in tbsp',
        "Read the packet's label",
        'Match a different food',
        'Scan the packet instead',
        'Unmatch this line',
        "Nothing to match — it's a seasoning",
      ];
      for (var index = 0; index < choices.length; index++) {
        final choice = find.text(choices[index]);
        await tester.ensureVisible(choice);
        await pumpFrames(tester, frames: 4);
        expect(choice.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await writeScene(tester, Scene(name: '${scene.name}-choice-$index'));
      }
    }, skip: !renderingGallery);
  }
}
