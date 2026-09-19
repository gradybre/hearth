@Tags(<String>['render'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../support/app_harness.dart';
import '../support/package_fixtures.dart';
import 'gallery.dart';

class _Photos implements PhotoPicker {
  _Photos({this.frontOnly = false});
  final bool frontOnly;
  int picks = 0;
  @override
  bool get canUseCamera => true;
  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async => PickedPhoto(
    bytes: File(
      frontOnly || picks++ > 0
          ? 'test/fixtures/package_front_10oz.png'
          : 'test/fixtures/package_nutrition_back.png',
    ).readAsBytesSync(),
    extension: 'png',
  );
  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => [];
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });
  const scenes = <Scene>[
    Scene(name: 'package-editor-phone'),
    Scene(name: 'package-editor-dark', brightness: Brightness.dark),
    Scene(name: 'package-editor-desktop', size: Size(1280, 900)),
    Scene(name: 'package-editor-small-2x', size: Size(320, 568), textScale: 2),
  ];
  for (final scene in scenes) {
    testWidgets(scene.name, (tester) async {
      await pumpHearthApp(
        tester,
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        foods: [packageCorn(approximate: true)],
      );
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);
      await tester.ensureVisible(find.text('Frozen corn'));
      await pumpFrames(tester);
      await tester.tap(find.text('Frozen corn'));
      await pumpFrames(tester);
      await tester.scrollUntilVisible(
        find.text('Package & nutrition'),
        250,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await tester.ensureVisible(find.text('Package & nutrition'));
      await pumpFrames(tester);
      expect(tester.takeException(), isNull);
      await writeScene(tester, scene);
      await tester.scrollUntilVisible(
        find.text('Weight display'),
        200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await tester.ensureVisible(find.text('Weight display'));
      await pumpFrames(tester);
      await writeScene(tester, Scene(name: '${scene.name}-lower'));
    }, skip: !renderingGallery);
  }
  for (final scene in const <Scene>[
    Scene(name: 'package-photos-phone'),
    Scene(name: 'package-photos-small-2x', size: Size(320, 568), textScale: 2),
  ]) {
    testWidgets(scene.name, (tester) async {
      await pumpHearthApp(
        tester,
        size: scene.size,
        textScale: scene.textScale,
        labelReader: PackageFixtureReader(),
        photoPicker: _Photos(),
      );
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Add food'));
      await pumpFrames(tester);
      await tester.tap(find.text('Read a label'));
      await pumpFrames(tester);
      expect(tester.takeException(), isNull);
      await writeScene(tester, scene);
      final back = find.byKey(
        const ValueKey<String>('LabelSlot.nutrition-camera'),
      );
      await tester.ensureVisible(back);
      await tester.tap(back);
      await pumpFrames(tester);
      final front = find.byKey(
        const ValueKey<String>('LabelSlot.package-camera'),
      );
      await tester.ensureVisible(front);
      await tester.tap(front);
      await pumpFrames(tester);
      await tester.ensureVisible(find.text('Read photos'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '${scene.name}-selected'));
      await tester.tap(find.text('Read photos'));
      await pumpFrames(tester);
      await tester.scrollUntilVisible(
        find.text('Package & nutrition'),
        250,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await tester.ensureVisible(find.text('Package & nutrition'));
      await pumpFrames(tester);
      await writeScene(tester, Scene(name: '${scene.name}-review'));
    }, skip: !renderingGallery);
  }
  testWidgets('package recipe amounts', (tester) async {
    await pumpHearthApp(
      tester,
      recipes: [packageRecipe()],
      foods: [packageCorn()],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Three-pack corn soup'));
    await pumpFrames(tester);
    expect(find.text('30 oz'), findsOneWidget);
    await writeScene(tester, const Scene(name: 'package-recipe'));
    await tester.tap(find.text('2×'));
    await pumpFrames(tester);
    expect(find.text('60 oz'), findsOneWidget);
    await writeScene(tester, const Scene(name: 'package-recipe-scaled'));
    await tester.tap(find.text('Cook'));
    await tester.pumpAndSettle();
    expect(find.textContaining('60 oz'), findsWidgets);
    await writeScene(tester, const Scene(name: 'package-cook-scaled'));
  }, skip: !renderingGallery);
  testWidgets('package shopping amounts', (tester) async {
    final food = packageCorn();
    await pumpHearthApp(
      tester,
      foods: [food],
      shoppingLines: [
        ShoppingLine(
          key: food.id,
          foodId: food.id,
          name: food.name,
          planned: [Quantity.of(30, Units.ounce)],
        ),
      ],
    );
    await tester.tap(find.text('Shopping').last);
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    await writeScene(tester, const Scene(name: 'package-shopping'));
    await tester.tap(find.text('3 × 10 oz'));
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsOneWidget);
    await writeScene(tester, const Scene(name: 'package-shopping-detail'));
  }, skip: !renderingGallery);
  testWidgets('two photos survive a failed read and retry', (tester) async {
    await pumpHearthApp(
      tester,
      labelReader: PackageFixtureReader(failFirst: true),
      photoPicker: _Photos(),
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Add food'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read a label'));
    await pumpFrames(tester);
    for (final slot in ['nutrition', 'package']) {
      final button = find.byKey(ValueKey<String>('LabelSlot.$slot-camera'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await pumpFrames(tester);
    }
    await tester.ensureVisible(find.text('Read photos'));
    await tester.tap(find.text('Read photos'));
    await pumpFrames(tester);
    expect(find.text('The reader is busy. Try again.'), findsOneWidget);
    expect(find.text('Photo selected'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Read photos'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await writeScene(tester, const Scene(name: 'package-photos-retry'));
    await tester.tap(find.text('Read photos'));
    await pumpFrames(tester);
    expect(find.text('New food'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !renderingGallery);
  testWidgets('front-only partial label review', (tester) async {
    await pumpHearthApp(
      tester,
      labelReader: PackageFixtureReader(partial: true),
      photoPicker: _Photos(frontOnly: true),
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Add food'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read a label'));
    await pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('LabelSlot.package-camera')),
    );
    await pumpFrames(tester);
    await tester.ensureVisible(find.text('Read photos'));
    await tester.tap(find.text('Read photos'));
    await pumpFrames(tester);
    await tester.scrollUntilVisible(
      find.text('Package & nutrition'),
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.ensureVisible(find.text('Package & nutrition'));
    await pumpFrames(tester);
    expect(find.text('Package servings in use.'), findsNothing);
    await writeScene(tester, const Scene(name: 'package-partial-review'));
  }, skip: !renderingGallery);
}
