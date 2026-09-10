@Tags(<String>['render'])
library;

import 'package:flutter/widgets.dart';
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
/// HEARTH_RENDER=1 flutter test test/render          # → build/gallery/
/// HEARTH_RENDER=1 HEARTH_RENDER_DIR=docs/reviews/2026-09-11 \
///   flutter test test/render                        # → a deliverable
/// ```
///
/// **It writes images; it does not compare them.** Goldens were the obvious
/// mechanism and are the wrong one here: the day screen reads the wall clock
/// for its date, and the shopping range is derived from it too, so a
/// committed golden changes when the calendar does. Every later pull request
/// would then carry a spurious image diff, which is precisely the signal
/// these exist to provide. Producing artefacts to look at is what §9.1 asks
/// for; a pass/fail gate is not.
///
/// Opt-in by environment because they are slow and are design artefacts
/// rather than correctness gates. The ordinary suite is unaffected.
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
        extraOverrides: galleryOverrides(scene),
        recipes: galleryRecipes(),
        foods: galleryFoods(),
        entries: galleryEntries(day),
        targets: galleryTargets,
      );
      await pumpFrames(tester, frames: 20);

      for (final String label in scene.taps) {
        await pressLabel(tester, label);
        await pumpFrames(tester, frames: 20);
      }

      // A weak smoke assertion before the capture. Writing the file is not
      // itself proof of anything: a screen that failed to build its content
      // would still produce a perfectly valid picture of nothing, and the
      // gallery's whole job is to be looked at rather than checked.
      expect(
        find.byType(Text),
        findsAtLeastNWidgets(5),
        reason: '${scene.name} rendered almost no text; is it an error state?',
      );

      await writeScene(tester, scene);
    }, skip: !renderingGallery);
  }
}
