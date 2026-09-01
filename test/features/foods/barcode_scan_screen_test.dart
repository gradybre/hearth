import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import 'label_scan_test.dart' show FakeCamera, FakeLabelReader;

/// A source that answers for exactly one barcode.
///
/// Standing in for Open Food Facts: the screen's job is to show what came
/// back, and a real HTTP call would make that test about the network.
class _StubSource implements NutritionSource {
  _StubSource(this.answers, {this.searchResults = const <NutritionMatch>[]});

  final Map<String, NutritionMatch> answers;
  final List<NutritionMatch> searchResults;

  @override
  String get displayName => 'Stub';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async => answers[barcode];

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async =>
      searchResults;
}

NutritionMatch aMatch({double confidence = 0.95}) => NutritionMatch(
  source: FoodSource.openFoodFacts,
  confidence: confidence,
  food: aFood(
    'Digestive biscuits',
    id: 'off:5000157024671',
    brand: 'McVitie',
    barcode: '5000157024671',
    source: FoodSource.openFoodFacts,
    servingOptions: <ServingOption>[
      aServing(
        id: 'off:5000157024671:100g',
        amount: 100,
        unit: Units.gram,
        macros: const Macros(kcal: 478, proteinG: 6.4, carbG: 63, fatG: 21),
      ),
    ],
  ),
);

Future<HearthDatabase> openScanner(
  WidgetTester tester, {
  Map<String, NutritionMatch> answers = const <String, NutritionMatch>{},
  List<NutritionMatch> searchResults = const <NutritionMatch>[],
  LabelReader? labelReader,
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    nutritionSources: <NutritionSource>[
      _StubSource(answers, searchResults: searchResults),
    ],
    labelReader: labelReader,
    photoPicker: FakeCamera(),
  );
  await tester.tap(find.text('Foods').last);
  await pumpFrames(tester);
  await tester.tap(find.text('Scan'));
  await pumpFrames(tester);
  return db;
}

Future<void> typeBarcode(WidgetTester tester, String barcode) async {
  await tester.enterText(find.byType(TextField).last, barcode);
  await tester.tap(find.text('Look it up'));
  await pumpFrames(tester);
}

void main() {
  produceTests();

  testWidgets('a device with no camera goes straight to typing', (
    WidgetTester tester,
  ) async {
    await openScanner(tester);

    expect(find.text('Type the number'), findsOneWidget);
    expect(find.textContaining('no camera'), findsOneWidget);
  });

  testWidgets('a hit shows the food, its source, and what it costs', (
    WidgetTester tester,
  ) async {
    await openScanner(
      tester,
      answers: <String, NutritionMatch>{'5000157024671': aMatch()},
    );
    await typeBarcode(tester, '5000157024671');

    expect(find.text('Digestive biscuits'), findsOneWidget);
    expect(find.text('McVitie'), findsOneWidget);
    // Where the numbers came from is on screen before anything is saved: a
    // user who disagrees with them needs to know who to disagree with (§5.3).
    expect(find.text('Open Food Facts'), findsOneWidget);
    expect(find.textContaining('478 kcal'), findsOneWidget);
  });

  testWidgets('a shaky match is flagged, not silently accepted', (
    WidgetTester tester,
  ) async {
    await openScanner(
      tester,
      answers: <String, NutritionMatch>{
        '5000157024671': aMatch(confidence: 0.4),
      },
    );
    await typeBarcode(tester, '5000157024671');

    expect(find.textContaining('looks incomplete'), findsOneWidget);
    // Never colour alone (§6.3): the warning carries an icon and words.
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  testWidgets('a confident match carries no warning', (
    WidgetTester tester,
  ) async {
    await openScanner(
      tester,
      answers: <String, NutritionMatch>{'5000157024671': aMatch()},
    );
    await typeBarcode(tester, '5000157024671');

    expect(find.textContaining('looks incomplete'), findsNothing);
  });

  testWidgets('nothing is saved until it has been reviewed', (
    WidgetTester tester,
  ) async {
    await openScanner(
      tester,
      answers: <String, NutritionMatch>{'5000157024671': aMatch()},
    );
    await typeBarcode(tester, '5000157024671');

    // The panel offers a review, never a save (CLAUDE.md rule 4).
    expect(find.text('Review and save'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Review and save'));
    await pumpFrames(tester);

    // Landing in the editor, prefilled and every field still editable.
    expect(find.text('Check and save'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Digestive biscuits',
    );
  });

  testWidgets('a food already in the library is not offered for saving', (
    WidgetTester tester,
  ) async {
    // Rescanning a packet already in the library is the common case after the
    // first week of use. Offering "review and save" there makes a second copy
    // of a food the household may already have corrected, and the badge alone
    // cannot warn about it: a food saved from Open Food Facts keeps that
    // source for life, so it reads identically to a fresh fetch.
    await openScanner(
      tester,
      answers: <String, NutritionMatch>{
        '5000157024671': NutritionMatch(
          food: aMatch().food,
          source: FoodSource.openFoodFacts,
          confidence: 1,
          fromLibrary: true,
        ),
      },
    );
    await typeBarcode(tester, '5000157024671');

    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.text('Review and save'), findsNothing);
    expect(find.text('Your library'), findsOneWidget);
  });

  testWidgets('a miss offers to add the food, keeping the barcode', (
    WidgetTester tester,
  ) async {
    await openScanner(tester);
    await typeBarcode(tester, '5000157024671');

    expect(find.textContaining('Nobody has heard of this one'), findsOneWidget);
    // The number is on screen because it is the thing being kept: a food added
    // here is found by the next scan of the same packet (§5.5).
    expect(
      find.textContaining('every future scan of 5000157024671'),
      findsOneWidget,
    );

    await tester.tap(find.text('Add it by hand'));
    await pumpFrames(tester);

    expect(find.text('Check and save'), findsOneWidget);
  });

  testWidgets('a miss leads with reading the packet, not typing it in', (
    WidgetTester tester,
  ) async {
    // The packet is in your hand at exactly this moment, which is the whole
    // argument for the order: §5.5 treats the miss as a first-class path, and
    // this is the fastest way off it.
    await openScanner(tester, labelReader: FakeLabelReader());
    await typeBarcode(tester, '5000157024671');

    expect(find.text('Read the label'), findsOneWidget);

    await tester.tap(find.text('Read the label'));
    await pumpFrames(tester);
    await tester.tap(find.text('Take a photo'));
    await pumpFrames(tester, frames: 10);

    // The same destination as adding by hand — this is manual entry with the
    // typing removed, not a way around the review (CLAUDE.md rule 4). The
    // barcode is still attached, so the next scan of this packet finds it.
    expect(find.text('Check and save'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Shredded Sharp Cheddar Cheese'),
      findsOneWidget,
    );
  });

  testWidgets('a miss without a backend still offers typing it in', (
    WidgetTester tester,
  ) async {
    await openScanner(tester);
    await typeBarcode(tester, '5000157024671');

    expect(find.text('Read the label'), findsNothing);
    expect(find.text('Add it by hand'), findsOneWidget);
  });

  testWidgets('a code that is not a product says so before looking anywhere', (
    WidgetTester tester,
  ) async {
    await openScanner(tester);
    await typeBarcode(tester, '12345');

    expect(find.text('That is not a product barcode'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

/// Produce codes typed instead of scanned (spec §5.5).
void produceTests() {
  NutritionMatch aBanana({bool fromLibrary = false}) => NutritionMatch(
    source: fromLibrary ? FoodSource.manual : FoodSource.usda,
    confidence: 0.9,
    fromLibrary: fromLibrary,
    food: aFood(
      'Bananas, raw',
      id: fromLibrary ? 'food-mine' : 'usda:banana',
      barcode: fromLibrary ? '4011' : null,
      servingOptions: <ServingOption>[
        aServing(
          amount: 100,
          unit: Units.gram,
          macros: const Macros(kcal: 89, proteinG: 1.1, carbG: 23),
        ),
      ],
    ),
  );

  group('a produce sticker', () {
    testWidgets('resolves to what it names, without a barcode lookup', (
      WidgetTester tester,
    ) async {
      // The load-bearing one. Open Food Facts has short codes of its own and
      // answers them confidently with unrelated food — 4062 is cucumber and
      // it returns pumpkin seeds at 600 kcal. A PLU must never reach it.
      // The source is primed to answer 4011 with a biscuit, exactly as Open
      // Food Facts would. The code must never reach it.
      await openScanner(
        tester,
        answers: <String, NutritionMatch>{'4011': aMatch()},
      );
      await typeBarcode(tester, '4011');

      expect(find.text('Bananas'), findsOneWidget);
      expect(find.textContaining('Produce code 4011'), findsOneWidget);
      expect(find.text('Digestive biscuits'), findsNothing);
    });

    testWidgets('a 9 in front says organic', (WidgetTester tester) async {
      await openScanner(tester);
      await typeBarcode(tester, '94011');

      expect(find.text('Organic Bananas'), findsOneWidget);
    });

    testWidgets('offers what the sources have for that produce', (
      WidgetTester tester,
    ) async {
      await openScanner(tester, searchResults: <NutritionMatch>[aBanana()]);
      await typeBarcode(tester, '4011');
      await tester.pump(const Duration(milliseconds: 400));
      await pumpFrames(tester);

      expect(find.textContaining('Bananas, raw'), findsOneWidget);
    });

    testWidgets('a code with no entry says so rather than guessing', (
      WidgetTester tester,
    ) async {
      await openScanner(tester);
      await typeBarcode(tester, '3999');

      expect(
        find.textContaining('Produce code 3999 is not one I know'),
        findsOneWidget,
      );
      expect(find.text('Add it by hand'), findsOneWidget);
    });

    testWidgets('adding by hand keeps the code and names the food', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openScanner(tester);
      await typeBarcode(tester, '4011');

      await tester.tap(find.text('Add it by hand'));
      await pumpFrames(tester);

      expect(find.text('Check and save'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Bananas'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester, frames: 12);

      // Asserted on the row, because the editor has no barcode field to look
      // at — the code is carried, not shown. It is what makes typing 4011
      // again find this food first, the property a scanned packet has.
      final List<FoodRow> rows = await db.select(db.foods).get();
      expect(rows.single.name, 'Bananas');
      expect(rows.single.barcode, '4011');
    });

    testWidgets('produce already saved under the code is the answer', (
      WidgetTester tester,
    ) async {
      // The household's own decision about what 4011 means to them beats
      // asking anybody else.
      await openScanner(
        tester,
        answers: <String, NutritionMatch>{'4011': aBanana(fromLibrary: true)},
      );
      await typeBarcode(tester, '4011');

      expect(find.text('Already in your library'), findsOneWidget);
      expect(find.textContaining('Produce code'), findsNothing);
    });

    testWidgets('a real barcode still takes the barcode road', (
      WidgetTester tester,
    ) async {
      await openScanner(
        tester,
        answers: <String, NutritionMatch>{'5000157024671': aMatch()},
      );
      await typeBarcode(tester, '5000157024671');

      expect(find.text('Digestive biscuits'), findsOneWidget);
      expect(find.textContaining('Produce code'), findsNothing);
    });
  });
}
