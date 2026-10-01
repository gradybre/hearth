@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });
  for (final Scene scene in <Scene>[
    const Scene(name: 'target-continuity-phone'),
    const Scene(name: 'target-continuity-dark', brightness: Brightness.dark),
    const Scene(name: 'target-continuity-desktop', size: Size(1280, 900)),
    const Scene(
      name: 'target-continuity-small-3x',
      size: Size(320, 568),
      textScale: 3,
    ),
  ]) {
    for (final bool ongoing in <bool>[false, true]) {
      testWidgets('${scene.name}: ${ongoing ? 'ongoing' : 'enable'}', (
        WidgetTester tester,
      ) async {
        await pumpHearthApp(
          tester,
          size: scene.size,
          brightness: scene.brightness,
          textScale: scene.textScale,
          viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
          targets: galleryTargets,
          targetsAreOngoing: ongoing,
        );
        final SweepTools tools = SweepTools(tester);
        await tools.tab('Plan');
        await tools.reach(
          find.text(
            ongoing
                ? 'Using ongoing targets · Change'
                : 'This week’s targets · Change',
          ),
        );
        expect(find.text('Weekly targets'), findsOneWidget);
        final String variant = ongoing ? 'ongoing' : 'enable';
        await writeScene(tester, Scene(name: '${scene.name}-$variant-top'));
        await tools.bring(find.text('Save targets'));
        if (ongoing) {
          await tools.bring(find.text('Stop carrying forward after this week'));
        }
        expect(tester.takeException(), isNull);
        await writeScene(
          tester,
          Scene(name: '${scene.name}-$variant-controls'),
        );
      }, skip: !renderingGallery);
    }
  }
}
