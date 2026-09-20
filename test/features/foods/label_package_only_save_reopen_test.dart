import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// A package-only read, through Save and back out again (spec R11).
///
/// The draft-level tests prove the merge; this one proves the round trip
/// somebody actually performs — the real editor, the real Save button, the
/// real repository, and the food reopened from the database it was written
/// to. Transcribed Great Value Chopped Onions facts only; no photograph is
/// stored in the repository.
class _FakeLabelReader implements LabelReader {
  _FakeLabelReader(this.answer);

  final LabelReading answer;

  @override
  Future<LabelReading> read(List<AiImage> images) async => answer;

  @override
  Future<PackReading> readPack(List<AiImage> images) async =>
      const PackReading();
}

class _FakeCamera implements PhotoPicker {
  @override
  bool get canUseCamera => true;

  static final Uint8List _onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async =>
      PickedPhoto(bytes: _onePixelPng, extension: 'png');

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => <PickedPhoto>[
    (await pick(PhotoOrigin.library))!,
  ];
}

void main() {
  /// A food whose panel has already been entered by hand.
  Food onions() => aFood(
    'Great Value Chopped Onions',
    id: 'food-onions',
    servingOptions: <ServingOption>[
      aServing(
        id: 'serving-cup',
        amount: 1,
        unit: Units.cup,
        macros: const Macros(kcal: 35, proteinG: 1, carbG: 8),
      ),
    ],
  );

  /// The front of the package, with a 100 g row volunteered beside it and its
  /// provenance forged as a panel reading. Only the package slot was filled,
  /// so nothing in that reply was read off a Nutrition Facts panel.
  LabelReading frontOnlyForged() => LabelReading(
    servings: const <LabelServing>[
      LabelServing(amount: 100, unitId: 'g', kcal: 40, carbG: 9.3),
    ],
    packageSize: Quantity.of(10, Units.ounce),
    packageBasis: 'unknown',
    fieldSources: const <String, String>{
      'package_amount': 'package',
      'servings': 'nutrition',
    },
  );

  testWidgets('a package-only read survives Save and a reopen', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(
      tester,
      foods: <Food>[onions()],
      labelReader: _FakeLabelReader(frontOnlyForged()),
      photoPicker: _FakeCamera(),
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Great Value Chopped Onions').first);
    await pumpFrames(tester);

    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('LabelSlot.package-camera')),
    );
    await pumpFrames(tester, frames: 10);
    await tester.tap(find.text('Read photos'));
    await pumpFrames(tester, frames: 10);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 15);
    // A duplicate warning is a soft warning, never a block. Answering it is
    // not what this test is about, so it is answered and got past.
    if (find.text('Save anyway').evaluate().isNotEmpty) {
      await tester.tap(find.text('Save anyway'));
      await pumpFrames(tester, frames: 15);
    }

    // Reopened from the library, which loads the food back out of the
    // database the save just wrote to.
    await tester.tap(find.text('Great Value Chopped Onions').first);
    await pumpFrames(tester, frames: 10);

    expect(find.text('Edit food'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '35'),
      findsOneWidget,
      reason: 'the entered calories must come back unchanged',
    );
    expect(find.text('cup'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '100'),
      findsNothing,
      reason: 'no panel was photographed, so no 100 g row was ever read',
    );

    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, '10 oz'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(TextField, '10 oz'), findsOneWidget);
  });
}
