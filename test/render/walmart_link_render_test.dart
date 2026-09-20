@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/walmart_fixtures.dart';
import 'gallery.dart';

Future<void> reach(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      220,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
      maxScrolls: 60,
    );
  }
  await t.ensureVisible(finder.last);
  await pumpFrames(t);
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });
  for (final scene in const [
    Scene(name: 'walmart-phone'),
    Scene(name: 'walmart-dark', brightness: Brightness.dark),
    Scene(name: 'walmart-desktop', size: Size(1280, 900)),
    Scene(name: 'walmart-small-2x', size: Size(320, 568), textScale: 2),
    Scene(name: 'walmart-small-3x', size: Size(320, 568), textScale: 3),
  ]) {
    testWidgets(scene.name, (t) async {
      await pumpHearthApp(
        t,
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        labelReader: WalmartFixtureReader(),
        photoPicker: WalmartFixturePicker(),
      );
      await t.tap(find.text('Foods').last);
      await pumpFrames(t);
      await t.tap(find.text('Add food'));
      await pumpFrames(t);
      await reach(t, find.text('Enter it by hand'));
      await t.tap(find.text('Enter it by hand'));
      await pumpFrames(t);
      final field = find.widgetWithText(TextField, 'walmart.com/ip/…/10450479');
      await reach(t, field);
      await t.enterText(field, '98765432');
      await reach(t, find.text('Read link from screenshot'));
      await t.tap(find.text('Read link from screenshot'));
      await pumpFrames(t);
      expect(t.takeException(), isNull);
      await writeScene(t, Scene(name: '${scene.name}-sheet'));
      await t.ensureVisible(find.text('Choose screenshot'));
      await t.tap(find.text('Choose screenshot'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await pumpFrames(t);
      await t.ensureVisible(find.text('Read link'));
      await pumpFrames(t);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await writeScene(t, Scene(name: '${scene.name}-selected'));
      await t.tap(find.text('Read link'));
      await pumpFrames(t);
      await reach(t, find.textContaining('A different Walmart link'));
      expect(t.takeException(), isNull);
      await writeScene(t, Scene(name: '${scene.name}-proposal'));
      await reach(t, find.text('Keep current link'));
      await writeScene(t, Scene(name: '${scene.name}-actions'));
      await t.tap(find.text('Keep current link'));
      await pumpFrames(t);
      expect(t.takeException(), isNull);
    }, skip: !renderingGallery);
  }
}
