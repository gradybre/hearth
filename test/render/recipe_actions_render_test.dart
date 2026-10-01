@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../support/app_harness.dart';
import '../support/package_fixtures.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'recipe-actions-phone'),
  Scene(name: 'recipe-actions-dark', brightness: Brightness.dark),
  Scene(name: 'recipe-actions-desktop', size: Size(1280, 900)),
  Scene(name: 'recipe-actions-small-3x', size: Size(320, 568), textScale: 3),
];

Future<void> _open(WidgetTester tester, Scene scene) async {
  await pumpHearthApp(
    tester,
    size: scene.size,
    textScale: scene.textScale,
    brightness: scene.brightness,
    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
    recipes: <Recipe>[packageRecipe()],
    foods: <Food>[packageCorn(approximate: true)],
  );
  await _press(tester, 'Recipes');
  await _press(tester, 'Three-pack corn soup');
  await pumpFrames(tester, frames: 12);
  expect(tester.takeException(), isNull);
}

Future<void> _press(WidgetTester tester, String label) async {
  // The detail's busy indicator continues behind an open review. Advancing
  // bounded frames visits the actual UI without waiting for it to stop.
  await SweepTools(tester).reach(find.text(label));
}

Future<void> _writes(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await pumpFrames(tester, frames: 20);
}

/// Returning to an earlier control needs an upward journey through the page.
/// At large text, lazy recipe children above the scale control are disposed.
Future<void> _bringEarlier(WidgetTester tester, String label) async {
  final Finder target = find.text(label);
  if (target.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      target,
      SweepTools.verticalScroller,
      const Offset(0, 120),
    );
    await pumpFrames(tester, frames: 4);
  }
  await SweepTools(tester).bring(target);
}

Future<void> _capture(WidgetTester tester, Scene scene, String suffix) async {
  expect(tester.takeException(), isNull);
  if (find.byType(SnackBar).evaluate().isNotEmpty) {
    final Finder bar = find.byType(SnackBar);
    final Rect bounds = tester.getRect(bar);
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(scene.size.height));
    final Finder message = find
        .descendant(of: bar, matching: find.byType(Text))
        .first;
    expect(
      tester.getSize(message).width,
      greaterThanOrEqualTo(bounds.width - 64),
      reason:
          'The confirmation needs the full row, with room for page gutters.',
    );
    // A snackbar can fit while its message continues below its own clipped
    // surface. Check the words people need to read, not only the outer box.
    for (final Element text
        in find.descendant(of: bar, matching: find.byType(Text)).evaluate()) {
      final Rect words = tester.getRect(find.byWidget(text.widget));
      expect(words.left, greaterThanOrEqualTo(bounds.left));
      expect(words.right, lessThanOrEqualTo(bounds.right));
      expect(words.top, greaterThanOrEqualTo(bounds.top));
      expect(
        words.bottom,
        lessThanOrEqualTo(bounds.bottom),
        reason:
            'The complete confirmation and action must fit: '
            '${(text.widget as Text).data}',
      );
    }
  }
  await writeScene(tester, Scene(name: '${scene.name}-$suffix'));
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _devices) {
    testWidgets('${scene.name}: personal plan review and Undo', (
      WidgetTester tester,
    ) async {
      await _open(tester, scene);
      await _press(tester, 'Plan');
      expect(find.text('My plan'), findsOneWidget);
      await _capture(tester, scene, 'plan');
      await SweepTools(tester)
          .reach(find.byKey(const ValueKey<String>('recipe-plan-date')));
      expect(find.text('Plan date'), findsOneWidget);
      await _capture(tester, scene, 'plan-date');
      await SweepTools(tester).bring(find.text('Use date'));
      await _capture(tester, scene, 'plan-date-controls');
      await SweepTools(tester).reach(find.text('Use date'));
      await SweepTools(tester).bring(find.text('Add to my plan'));
      await _capture(tester, scene, 'plan-controls');
      await _press(tester, 'Add to my plan');
      await _writes(tester);
      final SnackBar confirmation = tester.widget<SnackBar>(
        find.byType(SnackBar),
      );
      expect(confirmation.duration, const Duration(seconds: 6));
      expect(confirmation.persist, isFalse);
      expect(find.text('Undo').hitTestable(), findsOneWidget);
      await _capture(tester, scene, 'plan-added');
      await _press(tester, 'Undo');
      await _writes(tester);
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Removed from My plan.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, skip: !renderingGallery);

    testWidgets('${scene.name}: scaled shopping review and list', (
      WidgetTester tester,
    ) async {
      await _open(tester, scene);
      await _press(tester, '2×');
      await _bringEarlier(tester, 'Shop');
      await _press(tester, 'Shop');
      expect(find.text('Add ingredients'), findsOneWidget);
      await _capture(tester, scene, 'shop');
      await SweepTools(tester).bring(find.text('6 servings'));
      expect(find.text('6 servings'), findsOneWidget);
      await _capture(tester, scene, 'shop-quantity');
      await SweepTools(tester).bring(find.text('Add to the list'));
      await _capture(tester, scene, 'shop-controls');
      await _press(tester, 'Add to the list');
      await _writes(tester);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isTrue);
      expect(find.text('View list').hitTestable(), findsOneWidget);
      await _capture(tester, scene, 'shop-added');
      await _press(tester, 'View list');
      await _writes(tester);
      expect(find.text('Frozen corn'), findsOneWidget);
      await _capture(tester, scene, 'shopping-list');
    }, skip: !renderingGallery);

    testWidgets('${scene.name}: per serving and whole dish nutrition', (
      WidgetTester tester,
    ) async {
      await _open(tester, scene);
      await SweepTools(tester).bring(find.text('Per serving'));
      await _capture(tester, scene, 'per-serving');
      await _press(tester, 'Whole dish');
      await _capture(tester, scene, 'whole-dish');
      await _press(tester, '2×');
      await _bringEarlier(tester, 'Whole dish');
      await _capture(tester, scene, 'whole-dish-scaled');
    }, skip: !renderingGallery);
  }
}
