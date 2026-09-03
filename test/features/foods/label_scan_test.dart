import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Reading a nutrition label off a photo (spec §5.5).
///
/// §5.5's chain ends at manual entry: a barcode that misses left typing four
/// macros and two servings off a packet already in your hand. This is that
/// fallback with the typing removed — and it answers what the databases above
/// it cannot, because it is reading the actual box.
class FakeLabelReader implements LabelReader {
  FakeLabelReader({LabelReading? answer, this.error})
    : answer = answer ?? cheddar();

  final LabelReading? answer;
  final RecipeAiException? error;
  int calls = 0;
  List<AiImage> lastImages = const <AiImage>[];

  @override
  Future<LabelReading> read(List<AiImage> images) async {
    calls++;
    lastImages = images;
    if (error != null) throw error!;
    return answer!;
  }
}

/// The Kirkland cheddar Brendan photographed: "1oz (28g/about 1/4 cup)".
LabelReading cheddar({
  String? name = 'Shredded Sharp Cheddar Cheese',
  List<AiUncertainty> uncertain = const <AiUncertainty>[],
}) => LabelReading(
  name: name,
  brand: 'Kirkland Signature',
  uncertain: uncertain,
  servings: const <LabelServing>[
    LabelServing(
      amount: 1,
      unitId: 'oz',
      kcal: 110,
      proteinG: 7,
      carbG: 1,
      fatG: 9,
    ),
    LabelServing(
      amount: 0.25,
      unitId: 'cup',
      kcal: 110,
      proteinG: 7,
      carbG: 1,
      fatG: 9,
    ),
  ],
);

class FakeCamera implements PhotoPicker {
  FakeCamera({this.canUseCamera = true, this.bytes});

  @override
  final bool canUseCamera;

  /// Null means a real (tiny) PNG. A size is for the too-large guard, where
  /// the bytes never reach a decoder.
  final int? bytes;

  PhotoOrigin? lastOrigin;

  static final Uint8List _onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async {
    lastOrigin = origin;
    return PickedPhoto(
      bytes: bytes == null ? _onePixelPng : Uint8List(bytes!),
      extension: 'png',
    );
  }

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => <PickedPhoto>[
    (await pick(PhotoOrigin.library))!,
  ];
}

Future<void> openFoods(
  WidgetTester tester, {
  List<Food> foods = const <Food>[],
  LabelReader? reader,
  PhotoPicker? picker,
}) async {
  await pumpHearthApp(
    tester,
    foods: foods,
    labelReader: reader,
    photoPicker: picker ?? FakeCamera(),
  );
  await tester.tap(find.text('Foods').last);
  await pumpFrames(tester);
}

/// Opens a new food's editor from the Foods tab.
Future<void> openEditor(
  WidgetTester tester, {
  LabelReader? reader,
  PhotoPicker? picker,
}) async {
  await openFoods(tester, reader: reader, picker: picker);
  await tester.tap(find.byTooltip('Add a food by hand'));
  await pumpFrames(tester);
}

Future<void> takePhoto(WidgetTester tester) async {
  await tester.tap(find.text('Take a photo'));
  await pumpFrames(tester, frames: 10);
}

void main() {
  testWidgets('the editor fills its servings from a photographed label', (
    WidgetTester tester,
  ) async {
    await openEditor(tester, reader: FakeLabelReader());
    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await takePhoto(tester);

    // Both ways the panel states one portion, which is the whole point: the
    // ounces and the cups together are this food's density.
    expect(find.text('oz'), findsOneWidget);
    expect(find.text('cup'), findsOneWidget);
    expect(find.widgetWithText(TextField, '110'), findsNWidgets(2));
  });

  testWidgets('nothing is saved by reading a label', (
    WidgetTester tester,
  ) async {
    // CLAUDE.md rule 4: the editor is the review screen, and it stays one.
    await openEditor(tester, reader: FakeLabelReader());
    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await takePhoto(tester);

    expect(find.text('New food'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });

  testWidgets('a typed name survives the photo', (WidgetTester tester) async {
    await openEditor(tester, reader: FakeLabelReader());
    await tester.enterText(find.byType(TextField).first, 'Sharp cheddar');
    await pumpFrames(tester);

    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await takePhoto(tester);

    expect(find.widgetWithText(TextField, 'Sharp cheddar'), findsOneWidget);
  });

  testWidgets('a figure that was hard to read is pointed at', (
    WidgetTester tester,
  ) async {
    // §5.3's flag-never-guess, at the one moment it matters: the user is
    // looking at numbers they are about to trust.
    await openEditor(
      tester,
      reader: FakeLabelReader(
        answer: cheddar(
          uncertain: const <AiUncertainty>[
            AiUncertainty(field: 'fat', note: 'the fat line is creased'),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await takePhoto(tester);

    expect(find.textContaining('the fat line is creased'), findsOneWidget);
  });

  testWidgets('a failure keeps the photo so a retry is one tap', (
    WidgetTester tester,
  ) async {
    final FakeLabelReader reader = FakeLabelReader(
      error: const RecipeAiException('The reader is busy.'),
    );
    await openEditor(tester, reader: reader);
    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await takePhoto(tester);

    expect(find.text('The reader is busy.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await pumpFrames(tester, frames: 10);

    // Asked again without making anybody photograph the packet twice.
    expect(reader.calls, 2);
  });

  testWidgets('a build with no backend does not offer a camera', (
    WidgetTester tester,
  ) async {
    // Offering one that leads nowhere is worse than not offering one.
    await openEditor(tester);
    expect(find.text('Read label'), findsNothing);
  });

  testWidgets('desktop is offered the library instead of a camera', (
    WidgetTester tester,
  ) async {
    await openEditor(
      tester,
      reader: FakeLabelReader(),
      picker: FakeCamera(canUseCamera: false),
    );
    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);

    expect(find.text('Take a photo'), findsNothing);
    expect(find.text('Choose a photo'), findsOneWidget);
  });

  testWidgets('the Foods list offers it for a food with no barcode at all', (
    WidgetTester tester,
  ) async {
    await openFoods(tester, reader: FakeLabelReader());
    expect(find.byTooltip('Read a label from a photo'), findsOneWidget);

    await tester.tap(find.byTooltip('Read a label from a photo'));
    await pumpFrames(tester);
    await takePhoto(tester);

    // Straight into the editor, filled in and unsaved.
    expect(find.text('New food'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Shredded Sharp Cheddar Cheese'),
      findsOneWidget,
    );
  });

  testWidgets('the Foods list hides it when there is no backend', (
    WidgetTester tester,
  ) async {
    await openFoods(tester);
    expect(find.byTooltip('Read a label from a photo'), findsNothing);
  });

  testWidgets('an existing food keeps the servings it already had', (
    WidgetTester tester,
  ) async {
    // The case this is reached from: grams on file, cups needed. Replacing
    // rather than adding would be exactly backwards.
    await openFoods(
      tester,
      foods: <Food>[
        aFood(
          'Kirkland cheddar',
          id: 'food-cheddar',
          servingOptions: <ServingOption>[
            aServing(
              id: 'serving-g',
              amount: 28,
              unit: Units.gram,
              macros: const Macros(kcal: 110),
            ),
          ],
        ),
      ],
      reader: FakeLabelReader(),
    );
    await tester.tap(find.text('Kirkland cheddar'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await takePhoto(tester);

    // Scrolled to, not assumed on screen. The editor is a lazy ListView and
    // these are three separate serving rows near its foot, so whether all
    // three are built at once depends on how tall everything above them
    // happens to be — which has broken this test twice for reasons that had
    // nothing to do with servings being kept.
    for (final String unit in <String>['g', 'oz', 'cup']) {
      await tester.scrollUntilVisible(
        find.text(unit),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(unit), findsOneWidget);
    }
  });

  testWidgets('reopening the sheet asks for a photo, not the last answer', (
    WidgetTester tester,
  ) async {
    // Brendan's report. The sheet reset the controller in a post-frame
    // callback — one frame too late. Its first build had already seen the
    // previous LabelScanDone and scheduled a pop carrying that reading, so
    // the second open handed back the last label instead of asking for a
    // photo. Backing out and coming in again "fixed" it, because by then the
    // reset had landed.
    await openEditor(tester, reader: FakeLabelReader());

    await tester.tap(find.text('Read label'));
    await pumpFrames(tester);
    await takePhoto(tester);
    expect(find.text('New food'), findsOneWidget);

    await tester.tap(find.text('Read label'));
    await pumpFrames(tester, frames: 10);

    // Still on the sheet, asking — not popped straight back with the old
    // reading.
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose a photo'), findsOneWidget);
  });
}
