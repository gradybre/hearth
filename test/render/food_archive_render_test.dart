@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fake_food_archive.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'food-archive-phone'),
  Scene(name: 'food-archive-dark', brightness: Brightness.dark),
  Scene(name: 'food-archive-desktop', size: Size(1280, 900)),
  Scene(name: 'food-archive-small-3x', size: Size(320, 568), textScale: 3),
  Scene(
    name: 'food-archive-small-3x-dark',
    size: Size(320, 568),
    textScale: 3,
    brightness: Brightness.dark,
  ),
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
    testWidgets('${scene.name}: options, contents and honest receipt', (
      WidgetTester tester,
    ) async {
      final FakeArchiveFileShare share = FakeArchiveFileShare();
      await pumpHearthApp(
        tester,
        size: scene.size,
        brightness: scene.brightness,
        textScale: scene.textScale,
        viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
        recipes: galleryRecipes(),
        foods: galleryFoods(),
        archiveShare: share,
      );
      final SweepTools tools = SweepTools(tester);
      await tools.reach(find.byTooltip('Settings').last);
      await tools.reach(find.text('Your data'));
      await tools.reach(find.text('Readable food archive'));
      await _capture(tester, scene, 'options-top');
      await tools.reach(find.text('Include recipe photos'));
      await tools.bring(find.text('Prepare archive'));
      await _capture(tester, scene, 'options-end');
      await tools.reach(find.text('Prepare archive'));
      expect(find.text('Review food archive'), findsOneWidget);
      expect(share.archives, isEmpty);
      await _capture(tester, scene, 'review-top');
      await tools.bring(find.text('1 included · 1 unavailable'));
      await _capture(tester, scene, 'photos');
      await tools.bring(find.text('Whose data and what is left out'));
      await tools.bring(find.text('This device at capture'));
      await tools.bring(find.text('Export reviewed archive'));
      await _capture(tester, scene, 'review-actions');
      await tools.reach(find.text('Export reviewed archive'));
      expect(find.text('Archive export receipt'), findsOneWidget);
      expect(share.archives, hasLength(1));
      await _capture(tester, scene, 'receipt');
      await tools.bring(find.text('Done'));
      expect(find.text('Done').hitTestable(), findsOneWidget);
      await _capture(tester, scene, 'receipt-actions');
    }, skip: !renderingGallery);
  }
}
