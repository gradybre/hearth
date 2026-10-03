@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/foods/label_scan_test.dart' show FakeLabelReader;
import '../features/recipes/match_resolution_harness.dart';
import '../features/recipes/match_review_test.dart' show usda;
import '../support/app_harness.dart' show pumpFrames;
import 'gallery.dart';

const scenes = [
  Scene(name: 'ingredient-resolution-phone'),
  Scene(name: 'ingredient-resolution-phone-dark', brightness: Brightness.dark),
  Scene(name: 'ingredient-resolution-desktop', size: Size(1280, 900)),
  Scene(
    name: 'ingredient-resolution-desktop-dark',
    size: Size(1280, 900),
    brightness: Brightness.dark,
  ),
  Scene(
    name: 'ingredient-resolution-small-3x',
    size: Size(320, 568),
    textScale: 3,
  ),
  Scene(
    name: 'ingredient-resolution-small-3x-dark',
    size: Size(320, 568),
    textScale: 3,
    brightness: Brightness.dark,
  ),
];

Future<void> capture(WidgetTester tester, Scene scene, String step) async {
  expect(tester.takeException(), isNull);
  await writeScene(tester, Scene(name: '${scene.name}-$step'));
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });
  for (final scene in scenes) {
    testWidgets('${scene.name}: review and ingredient capture', (tester) async {
      await pumpResolution(
        tester,
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        reader: FakeLabelReader(),
        source: ResolutionSource(
          answers: {
            'olive oil': [usda('Olive oil')],
          },
        ),
      );
      await capture(tester, scene, 'review');
      await tester.ensureVisible(find.byKey(const Key('match-row-1')));
      await tester.pumpAndSettle();
      await capture(tester, scene, 'unresolved');
      await resolutionTap(tester, find.byKey(const Key('match-1-search')));
      await capture(tester, scene, 'search');
      await resolutionTap(
        tester,
        find.byKey(const Key('ingredient-picker-manual')),
      );
      await capture(tester, scene, 'manual');
      await tester.tap(
        scene.textScale > 1 ? find.byTooltip('Cancel') : find.text('Cancel'),
      );
      await pumpFrames(tester, frames: 20);
      Navigator.of(tester.element(find.text('200 g cottage cheese').last))
          .pop();
      await pumpFrames(tester, frames: 20);
      await resolutionTap(tester, find.byKey(const Key('match-1-scan')));
      await capture(tester, scene, 'scan');
      Navigator.of(tester.element(find.text('Scan a barcode'))).pop();
      await pumpFrames(tester, frames: 20);
      await resolutionTap(tester, find.byKey(const Key('match-1-label')));
      await capture(tester, scene, 'read-label');
      Navigator.of(tester.element(find.text('200 g cottage cheese').last))
          .pop();
      await pumpFrames(tester, frames: 20);
      await resolutionTap(tester, find.byKey(const Key('match-1-skip')));
      await tester.ensureVisible(find.byKey(const Key('match-review-apply')));
      await tester.pumpAndSettle();
      await capture(tester, scene, 'apply');
    }, skip: !renderingGallery);
  }
  for (final scene in scenes) {
    testWidgets('${scene.name}: grouped wording with every authored amount', (
      tester,
    ) async {
      await pumpResolution(
        tester,
        lines: '1 tbsp Olive Oil\n2 tbsp olive   oil\n200 g cottage cheese',
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        source: ResolutionSource(
          answers: {
            'Olive Oil': [usda('Olive oil')],
          },
        ),
      );
      expect(find.text('Applies to 2 recipe lines'), findsOneWidget);
      await capture(tester, scene, 'grouped-review');
      await Scrollable.ensureVisible(
        tester.element(find.text('1 tbsp Olive Oil')),
        alignment: 0,
      );
      await tester.pumpAndSettle();
      await capture(tester, scene, 'grouped-lines');
      await resolutionTap(tester, find.byKey(const Key('match-0-remember')));
      await capture(tester, scene, 'grouped-remember');
    }, skip: !renderingGallery);

    testWidgets('${scene.name}: synthetic camera with long ingredient', (
      tester,
    ) async {
      final scanner = useResolutionScanner();
      await pumpResolution(
        tester,
        lines: '200 g low-fat cottage cheese, drained and brought to room temperature',
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        cameraAvailable: true,
        reader: FakeLabelReader(),
      );
      await resolutionTap(tester, find.byKey(const Key('match-0-scan')));
      expect(scanner.starts, 1);
      await capture(tester, scene, 'camera-context');
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('synthetic-camera-preview'))),
        alignment: 0,
      );
      await tester.pumpAndSettle();
      await capture(tester, scene, 'camera-preview');
      await tester.ensureVisible(
        find.byKey(const Key('ingredient-camera-label')),
      );
      await tester.pumpAndSettle();
      await capture(tester, scene, 'camera-recovery');
    }, skip: !renderingGallery);
  }

  for (final brightness in Brightness.values) {
    testWidgets('ingredient search result 3x ${brightness.name}', (
      tester,
    ) async {
      final source = ResolutionSource();
      await pumpResolution(
        tester,
        size: const Size(320, 568),
        textScale: 3,
        brightness: brightness,
        source: source,
      );
      source.answers = {
        'cottage cheese': [usda('Cottage cheese')],
      };
      await resolutionTap(tester, find.byKey(const Key('match-1-search')));
      await tester.pump(const Duration(milliseconds: 400));
      await pumpFrames(tester, frames: 20);
      final picker = find.byKey(const Key('ingredient-food-picker-scroll'));
      final result = find.descendant(
        of: picker,
        matching: find.text('Cottage cheese'),
      );
      await tester.scrollUntilVisible(
        result,
        180,
        scrollable: find
            .descendant(of: picker, matching: find.byType(Scrollable))
            .first,
      );
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
      await capture(
        tester,
        Scene(name: 'ingredient-resolution-small-3x-${brightness.name}'),
        'search-result',
      );
    }, skip: !renderingGallery);
  }
}
