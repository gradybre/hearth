@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import 'gallery.dart';

/// Draws the screen gallery (review §9.1).
///
/// The review's own gallery was built outside the repository, which means it
/// cannot be redrawn after a change — and §9.1 asks for *before and after*
/// designs, which is a diff. This makes the gallery a thing the repository
/// owns: run it, get PNGs, change the UI, run it again, and the difference is
/// reviewable in the pull request rather than described in prose.
///
/// It doubles as the golden accessibility surface WP8 left open, which is why
/// the small-phone-at-2x scene is in the list rather than being a separate
/// exercise nobody runs.
///
/// ```bash
/// HEARTH_RENDER=1 flutter test --update-goldens test/render
/// ```
///
/// Opt-in by environment for two reasons: a golden rendered on macOS does not
/// match one rendered on CI's Linux, so running these by default would put a
/// permanent red light in front of everybody; and they are design artefacts,
/// not correctness gates. The correctness suite is unaffected either way.
void main() {
  setUpAll(() async {
    if (!renderingGallery) return;
    await loadIconFont();
  });

  for (final Scene scene in scenes) {
    testWidgets('gallery: ${scene.name}', (WidgetTester tester) async {
      final DateTime day = DateTime(2026, 9, 10);

      await pumpHearthApp(
        tester,
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        // A real phone reserves these; a test view does not, and a layout
        // that only works without them is a layout that ships broken.
        viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
        launchTarget: scene.target,
        recipes: galleryRecipes(),
        foods: galleryFoods(),
        entries: galleryEntries(day),
        targets: galleryTargets,
      );
      await pumpFrames(tester, frames: 20);

      if (scene.tab case final String tab) {
        await tester.tap(find.text(tab).last);
        await pumpFrames(tester, frames: 20);
      }

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('gallery/${scene.name}.png'),
      );
    }, skip: !renderingGallery);
  }
}
