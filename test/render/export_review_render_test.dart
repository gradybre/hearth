@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/data_export.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/recipe_store.dart';

import '../support/app_harness.dart';
import '../support/fake_file_share.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'export-review-phone'),
  Scene(name: 'export-review-dark', brightness: Brightness.dark),
  Scene(name: 'export-review-desktop', size: Size(1280, 900)),
  Scene(name: 'export-review-small-3x', size: Size(320, 568), textScale: 3),
];

Future<void> _capture(WidgetTester tester, Scene scene, String suffix) async {
  expect(tester.takeException(), isNull);
  await writeScene(tester, Scene(name: '${scene.name}-$suffix'));
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _devices) {
    testWidgets('${scene.name}: review and honest receipt', (
      WidgetTester tester,
    ) async {
      final FakeFileShare share = FakeFileShare();
      await pumpHearthApp(
        tester,
        size: scene.size,
        brightness: scene.brightness,
        textScale: scene.textScale,
        viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
        recipes: galleryRecipes(),
        foods: galleryFoods(),
        shoppingLines: galleryShoppingLines(),
        fileShare: share,
        extraOverrides: <Object>[
          dataExportProvider.overrideWith(
            (Ref ref) => DataExport(
              database: ref.watch(databaseProvider),
              recipes: RecipeStore(ref.watch(databaseProvider)),
              foods: FoodStore(ref.watch(databaseProvider)),
              clock: () => DateTime.utc(2026, 10, 1, 12),
            ),
          ),
        ],
      );
      final SweepTools tools = SweepTools(tester);
      await tools.reach(find.byTooltip('Settings').last);
      await tools.reach(find.text('Your data'));
      await tools.reach(find.text('Export food data (JSON)'));
      await pumpFrames(tester, frames: 20);
      expect(find.text('Review food export'), findsOneWidget);
      expect(share.files, isEmpty);
      await _capture(tester, scene, 'overview');

      await tools.bring(
        find.byKey(const ValueKey<String>('export-review-counts')),
      );
      await _capture(tester, scene, 'counts');
      await tools.bring(
        find.byKey(const ValueKey<String>('export-review-exclusions')),
      );
      await _capture(tester, scene, 'exclusions');
      await tools.bring(find.text('Export this device now'));
      expect(find.text('Export this device now').hitTestable(), findsOneWidget);
      await _capture(tester, scene, 'controls');
      await tools.reach(find.text('Export this device now'));
      expect(find.text('Export receipt'), findsOneWidget);
      expect(share.files, hasLength(1));
      expect(share.files.single.name, 'hearth-2026-10-01.json');
      await _capture(tester, scene, 'receipt');
      await tools.bring(find.text('Done'));
      expect(find.text('Done').hitTestable(), findsOneWidget);
      await _capture(tester, scene, 'receipt-controls');
    }, skip: !renderingGallery);
  }
}
