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

/// Reading a label from the editor, through the real sheet (spec §5.5, R11).
///
/// Two shapes of read, because they fail in opposite directions: the front of
/// a package alone, which must add package facts and touch nothing else, and
/// both faces together, which must produce the two printed portions and no
/// invented third.
///
/// The numbers are transcribed Great Value Chopped Onions facts — NET WT
/// 10 OZ, 2/3 cup (85 g), 35 kcal. No real screenshot is used or stored.

/// A reader that answers with whatever it was given, and remembers what it
/// was asked for.
class _FakeLabelReader implements LabelReader {
  _FakeLabelReader(this.answer);

  final LabelReading answer;
  int calls = 0;
  List<AiImage> lastImages = const <AiImage>[];

  @override
  Future<LabelReading> read(List<AiImage> images) async {
    calls++;
    lastImages = images;
    return answer;
  }

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
  /// A food whose portion is recorded but whose macros are still to be typed —
  /// the ordinary half-finished state, and the one a photo must not tidy away.
  Food onions() => aFood(
    'Great Value Chopped Onions',
    id: 'food-onions',
    servingOptions: <ServingOption>[
      aServing(
        id: 'serving-cup',
        amount: 1,
        unit: Units.cup,
        macros: const Macros(kcal: 0),
      ),
    ],
  );

  /// Front-of-package facts, with a 100 g row volunteered beside them — and
  /// with its provenance *forged* as a panel reading.
  ///
  /// The draft cannot tell this from a real panel. What can is the request
  /// itself: only the package slot was filled, so nothing in that reply was
  /// read off a Nutrition Facts panel.
  LabelReading frontOnlyWithForgedNutrition() => LabelReading(
    servings: const <LabelServing>[
      LabelServing(
        amount: 100,
        unitId: 'g',
        kcal: 40,
        proteinG: 1.1,
        carbG: 9.3,
        fatG: 0.1,
      ),
    ],
    packageSize: Quantity.of(10, Units.ounce),
    packageBasis: 'unknown',
    fieldSources: const <String, String>{
      'package_amount': 'package',
      'servings': 'nutrition',
    },
  );

  /// Both faces: the panel's two printed portions, and the net contents.
  LabelReading bothFaces() => LabelReading(
    name: 'Chopped Onions',
    brand: 'Great Value',
    packageSize: Quantity.of(10, Units.ounce),
    servingsPerContainer: 3.5,
    servingsApproximate: true,
    packageBasis: 'as_packaged',
    fieldSources: const <String, String>{
      'package_amount': 'package',
      'servings': 'nutrition',
    },
    servings: const <LabelServing>[
      LabelServing(
        amount: 2 / 3,
        unitId: 'cup',
        kcal: 35,
        proteinG: 1,
        carbG: 8,
        fatG: 0,
        fiberG: 1,
        sodiumMg: 0,
        cholesterolMg: 0,
      ),
      LabelServing(
        amount: 85,
        unitId: 'g',
        kcal: 35,
        proteinG: 1,
        carbG: 8,
        fatG: 0,
        fiberG: 1,
        sodiumMg: 0,
        cholesterolMg: 0,
      ),
    ],
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
  }

  Future<void> fillSlot(WidgetTester tester, String slot) async {
    await tester.tap(find.byKey(ValueKey<String>('$slot-camera')));
    await pumpFrames(tester, frames: 10);
  }

  Future<_FakeLabelReader> openExistingAndReadFront(WidgetTester tester) async {
    final _FakeLabelReader reader = _FakeLabelReader(
      frontOnlyWithForgedNutrition(),
    );
    await pumpHearthApp(
      tester,
      foods: <Food>[onions()],
      labelReader: reader,
      photoPicker: _FakeCamera(),
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Great Value Chopped Onions'));
    await pumpFrames(tester);

    await openSheet(tester);
    await fillSlot(tester, 'LabelSlot.package');
    await tester.tap(find.text('Read photos'));
    await pumpFrames(tester, frames: 10);
    return reader;
  }

  group('the front of a package, over a food that already has a serving', () {
    testWidgets('the package slot alone is sent as one request', (
      WidgetTester tester,
    ) async {
      final _FakeLabelReader reader = await openExistingAndReadFront(tester);

      expect(reader.calls, 1);
      expect(reader.lastImages, hasLength(1));
      expect(reader.lastImages.single.role, 'package');
    });

    testWidgets('the serving already on the food is still there', (
      WidgetTester tester,
    ) async {
      await openExistingAndReadFront(tester);

      // The Serving sizes header was on screen a moment ago — Read label sits
      // in the same row — so its one row is too.
      expect(find.text('Serving sizes'), findsOneWidget);
      expect(
        find.text('cup'),
        findsOneWidget,
        reason: "a package photo must not remove the user's serving row",
      );
    });

    testWidgets('no 100 g row appears, however the reply is labelled', (
      WidgetTester tester,
    ) async {
      await openExistingAndReadFront(tester);

      expect(find.text('Serving sizes'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, '100'),
        findsNothing,
        reason: 'no panel was photographed, so no panel was read',
      );
    });
  });

  group('both faces, on a new food', () {
    Future<void> openNewAndReadBoth(WidgetTester tester) async {
      await pumpHearthApp(
        tester,
        labelReader: _FakeLabelReader(bothFaces()),
        photoPicker: _FakeCamera(),
      );
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Add food'));
      await pumpFrames(tester);
      await tester.tap(find.text('Enter it by hand'));
      await pumpFrames(tester);

      await openSheet(tester);
      await fillSlot(tester, 'LabelSlot.nutrition');
      await fillSlot(tester, 'LabelSlot.package');
      await tester.tap(find.text('Read photos'));
      await pumpFrames(tester, frames: 10);
    }

    testWidgets('the cup portion is shown, in cups', (
      WidgetTester tester,
    ) async {
      await openNewAndReadBoth(tester);

      expect(find.text('cup'), findsOneWidget);
      expect(find.widgetWithText(TextField, '2/3'), findsOneWidget);
    });

    testWidgets('and the gram portion beside it, at 85 g', (
      WidgetTester tester,
    ) async {
      await openNewAndReadBoth(tester);

      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, '85'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.widgetWithText(TextField, '85'), findsOneWidget);
      // One 'g' row, not two: the starter is gone rather than sitting above
      // the rows that were actually read.
      expect(find.text('g'), findsOneWidget);
    });

    testWidgets('and nothing is left showing 100 g', (
      WidgetTester tester,
    ) async {
      await openNewAndReadBoth(tester);

      expect(find.text('Serving sizes'), findsOneWidget);
      expect(find.widgetWithText(TextField, '100'), findsNothing);
    });
  });
}
