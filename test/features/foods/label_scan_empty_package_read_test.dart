import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';

import '../../support/app_harness.dart';

/// A package-only read whose reply held nothing but nutrition (spec R11).
///
/// Once the gate has dropped nutrition nobody asked for, there is nothing
/// left to merge. That used to close the sheet with the draft unchanged and
/// no word about why; it now says so, and keeps the photo so trying again is
/// one tap rather than another trip to the cupboard.
class _FakeLabelReader implements LabelReader {
  _FakeLabelReader(this.answer);

  final LabelReading answer;
  int calls = 0;

  @override
  Future<LabelReading> read(List<AiImage> images) async {
    calls++;
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
  /// Nutrition and nothing else, answering a request that asked for the
  /// package: no net contents, no count, no link.
  LabelReading nutritionOnly() => const LabelReading(
    servings: <LabelServing>[LabelServing(amount: 100, unitId: 'g', kcal: 40)],
  );

  Future<_FakeLabelReader> readFrontOnly(WidgetTester tester) async {
    final _FakeLabelReader reader = _FakeLabelReader(nutritionOnly());
    await pumpHearthApp(
      tester,
      labelReader: reader,
      photoPicker: _FakeCamera(),
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Add food'));
    await pumpFrames(tester);
    await tester.tap(find.text('Enter it by hand'));
    await pumpFrames(tester);

    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('LabelSlot.package-camera')),
    );
    await pumpFrames(tester, frames: 10);
    await tester.tap(find.text('Read photos'));
    await pumpFrames(tester, frames: 10);
    return reader;
  }

  testWidgets('it says so rather than closing on an unchanged draft', (
    WidgetTester tester,
  ) async {
    await readFrontOnly(tester);

    expect(find.textContaining('No package size'), findsOneWidget);
    // Still on the sheet, not back on an editor that looks untouched.
    expect(find.text('Read photos'), findsOneWidget);
  });

  testWidgets('and keeps the photo, so a retry is one tap', (
    WidgetTester tester,
  ) async {
    final _FakeLabelReader reader = await readFrontOnly(tester);

    expect(
      find.byKey(const ValueKey<String>('LabelSlot.package-remove')),
      findsOneWidget,
      reason: 'the photo it was given is still chosen',
    );

    await tester.tap(find.text('Read photos'));
    await pumpFrames(tester, frames: 10);
    expect(reader.calls, 2);
  });
}
