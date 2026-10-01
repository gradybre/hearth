@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/recipes/recipe_nutrition_receipt_test.dart'
    show
        beansRecipe,
        inIngredient,
        openReceiptRecipe,
        pressReceiptTarget,
        reachReceiptTarget;
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'receipt-phone'),
  Scene(name: 'receipt-phone-dark', brightness: Brightness.dark),
  Scene(name: 'receipt-desktop', size: Size(1280, 900)),
  Scene(
    name: 'receipt-desktop-dark',
    size: Size(1280, 900),
    brightness: Brightness.dark,
  ),
  Scene(name: 'receipt-small-3x', size: Size(320, 568), textScale: 3),
  Scene(
    name: 'receipt-small-3x-dark',
    size: Size(320, 568),
    textScale: 3,
    brightness: Brightness.dark,
  ),
];

const Key _entry = ValueKey<String>('recipe-nutrition-receipt');
const Key _back = ValueKey<String>('receipt-back');

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _devices) {
    testWidgets('${scene.name}: nutrition, receipt and missing contribution', (
      WidgetTester tester,
    ) async {
      await _open(tester, scene);
      await reachReceiptTarget(tester, find.byKey(_entry));
      await _capture(tester, '${scene.name}-entry');
      await pressReceiptTarget(tester, find.byKey(_entry));
      await _capture(tester, '${scene.name}-top');

      await reachReceiptTarget(
        tester,
        inIngredient(0, 'Serving basis: 1 can · 400 kcal'),
      );
      await _capture(tester, '${scene.name}-serving-basis');
      await reachReceiptTarget(
        tester,
        inIngredient(1, 'No food match — contribution is unknown, not zero.'),
      );
      await _capture(tester, '${scene.name}-missing');
      expect(find.byKey(_back).hitTestable(), findsOneWidget);
      await pressReceiptTarget(tester, find.byKey(_back));
    }, skip: !renderingGallery);

    if (scene.textScale > 1) {
      testWidgets(
        '${scene.name}: editor Whole dish receipt and excluded line',
        (WidgetTester tester) async {
          await _open(tester, scene);
          await pressReceiptTarget(tester, find.text('Edit'));
          await pressReceiptTarget(tester, find.text('Whole dish'));
          await reachReceiptTarget(tester, find.byKey(_entry));
          await _capture(tester, '${scene.name}-editor-entry');
          await pressReceiptTarget(tester, find.byKey(_entry));
          await reachReceiptTarget(tester, inIngredient(0, '800 kcal'));
          await _capture(tester, '${scene.name}-editor-whole-dish');
          await reachReceiptTarget(
            tester,
            inIngredient(2, 'Optional ingredient — excluded from nutrition.'),
          );
          await _capture(tester, '${scene.name}-editor-excluded');
          await pressReceiptTarget(tester, find.byKey(_back));
        },
        skip: !renderingGallery,
      );
    }
  }
}

Future<void> _open(WidgetTester tester, Scene scene) async {
  await openReceiptRecipe(
    tester,
    recipe: beansRecipe(partial: true),
    size: scene.size,
    scale: scene.textScale,
    brightness: scene.brightness,
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  await writeScene(tester, Scene(name: name));
}
