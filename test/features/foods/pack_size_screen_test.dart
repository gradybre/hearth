import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import 'label_scan_test.dart' show FakeCamera, FakeLabelReader;

/// Filling in the pack sizes a library never had (spec §5.7).
///
/// The shopping list counts jars rather than weighing them, and across the
/// real household library not one food had a pack size — so the feature was
/// invisible. This is the way in, and it writes, which makes every proposal a
/// thing shown and ticked before anything lands (CLAUDE.md rule 4).
void main() {
  Food marinara({String id = 'f-marinara', String? barcode}) => aFood(
    'Marinara sauce',
    id: id,
    brand: "Rao's",
    barcode: barcode,
    servingOptions: <ServingOption>[
      aServing(
        id: '$id-s',
        amount: 100,
        unit: Units.gram,
        macros: const Macros(kcal: 90, proteinG: 2, carbG: 6, fatG: 6),
      ),
    ],
  );

  /// A source that answers the barcodes it was given, and nothing else.
  ///
  /// [fromLibrary] is the interesting knob: the real chain asks the
  /// household's own library first, and that copy is the very food whose pack
  /// size is missing.
  StubPackSource stub(
    Map<String, Quantity?> known, {
    String name = 'Open Food Facts',
    bool fromLibrary = false,
  }) => StubPackSource(known, name: name, fromLibrary: fromLibrary);

  Future<HearthDatabase> openPackSizes(
    WidgetTester tester, {
    List<Food> foods = const <Food>[],
    List<ShoppingLine> shoppingLines = const <ShoppingLine>[],
    List<NutritionSource> sources = const <NutritionSource>[],
    LabelReader? labelReader,
    PhotoPicker? photoPicker,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      size: size,
      textScale: scale,
      foods: foods,
      shoppingLines: shoppingLines,
      nutritionSources: sources,
      labelReader: labelReader,
      photoPicker: photoPicker,
    );
    await tester.tap(find.text('Foods').last);
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Foods with no pack size'));
    await pumpFrames(tester, frames: 12);
    return db;
  }

  /// The pack size as the database actually holds it.
  Future<({double? canonical, String? unit})> packOf(
    HearthDatabase db,
    String id,
  ) async {
    final List<FoodRow> rows = await db.select(db.foods).get();
    final FoodRow row = rows.firstWhere((FoodRow r) => r.id == id);
    return (canonical: row.packCanonical, unit: row.packUnit);
  }

  group('finding them', () {
    testWidgets('the Foods menu opens the list', (WidgetTester tester) async {
      await openPackSizes(tester, foods: <Food>[marinara()]);

      expect(find.text('Pack sizes'), findsOneWidget);
      expect(find.text('1 food has no pack size'), findsOneWidget);
      expect(find.text('Marinara sauce'), findsOneWidget);
    });

    testWidgets('a food that already has one is not in it', (
      WidgetTester tester,
    ) async {
      await openPackSizes(
        tester,
        foods: <Food>[marinara().withPack(Quantity.of(24, Units.ounce))],
      );

      expect(find.text('Every food has a pack size'), findsOneWidget);
      expect(find.text('Marinara sauce'), findsNothing);
    });

    testWidgets('what is on the shopping list is under its own heading', (
      WidgetTester tester,
    ) async {
      await openPackSizes(
        tester,
        foods: <Food>[
          marinara(),
          aFood('Almonds', id: 'f-almonds'),
        ],
        shoppingLines: <ShoppingLine>[
          ShoppingLine(
            key: 'f-marinara',
            name: 'Marinara sauce',
            planned: <Quantity>[Quantity.of(64, Units.ounce)],
            foodId: 'f-marinara',
          ),
        ],
      );

      expect(find.text('On your shopping list'), findsOneWidget);
      expect(find.text('Everything else'), findsOneWidget);
      // The heading that leads is the one for the food you are about to stand
      // in front of.
      final double list = tester
          .getTopLeft(find.text('On your shopping list'))
          .dy;
      final double rest = tester.getTopLeft(find.text('Everything else')).dy;
      expect(list, lessThan(rest));
    });
  });

  group('the barcode run', () {
    testWidgets('offers what it found and saves none of it', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openPackSizes(
        tester,
        foods: <Food>[marinara(barcode: '5000157024671')],
        sources: <NutritionSource>[
          stub(<String, Quantity?>{
            '5000157024671': Quantity.of(24, Units.ounce),
          }),
        ],
      );

      await tester.tap(find.text('Look up 1 barcode'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Use 24 oz, from Open Food Facts'), findsOneWidget);
      expect(find.text('Save 1 pack size'), findsOneWidget);
      // Rule 4: the proposal is on the screen and nowhere else.
      expect((await packOf(db, 'f-marinara')).canonical, isNull);
    });

    testWidgets('and the save is what writes it', (WidgetTester tester) async {
      final HearthDatabase db = await openPackSizes(
        tester,
        foods: <Food>[marinara(barcode: '5000157024671')],
        sources: <NutritionSource>[
          stub(<String, Quantity?>{
            '5000157024671': Quantity.of(24, Units.ounce),
          }),
        ],
      );

      await tester.tap(find.text('Look up 1 barcode'));
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.text('Save 1 pack size'));
      await pumpFrames(tester, frames: 30);

      final ({double? canonical, String? unit}) pack = await packOf(
        db,
        'f-marinara',
      );
      expect(pack.canonical, closeTo(680.4, 0.5));
      // Stored in the unit the packet was printed in: "24 oz", not "1.5 lb".
      expect(pack.unit, 'oz');
      expect(find.text('1 pack size saved'), findsOneWidget);
    });

    testWidgets('an unticked proposal is left behind by the save', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await openPackSizes(
        tester,
        foods: <Food>[marinara(barcode: '5000157024671')],
        sources: <NutritionSource>[
          stub(<String, Quantity?>{
            '5000157024671': Quantity.of(24, Units.ounce),
          }),
        ],
      );

      await tester.tap(find.text('Look up 1 barcode'));
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.byType(Checkbox));
      await pumpFrames(tester, frames: 12);

      // Nothing ticked, so there is nothing to save and no bar offering to.
      expect(find.textContaining('Save '), findsNothing);
      expect((await packOf(db, 'f-marinara')).canonical, isNull);
    });

    testWidgets('discarding takes the proposal off the screen', (
      WidgetTester tester,
    ) async {
      await openPackSizes(
        tester,
        foods: <Food>[marinara(barcode: '5000157024671')],
        sources: <NutritionSource>[
          stub(<String, Quantity?>{
            '5000157024671': Quantity.of(24, Units.ounce),
          }),
        ],
      );

      await tester.tap(find.text('Look up 1 barcode'));
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.text('Discard'));
      await pumpFrames(tester, frames: 12);

      expect(find.textContaining('Use 24 oz'), findsNothing);
      expect(find.text('Look it up'), findsOneWidget);
    });

    testWidgets('a barcode nobody has a pack size for says so', (
      WidgetTester tester,
    ) async {
      await openPackSizes(
        tester,
        foods: <Food>[marinara(barcode: '5000157024671')],
        sources: <NutritionSource>[
          // Found, with no pack size on it: knowing the food is not knowing
          // the jar.
          stub(<String, Quantity?>{'5000157024671': null}),
        ],
      );

      await tester.tap(find.text('Look up 1 barcode'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.text('No pack size on record for that barcode.'),
        findsOneWidget,
      );
    });

    testWidgets('a library hit does not end the chain', (
      WidgetTester tester,
    ) async {
      // `NutritionLookup.byBarcode` stops at the first source with a *match*,
      // and the first source is the household's own library — which has this
      // food, by definition, and has it without a pack size. Stopping there
      // would make this whole screen find nothing, for ever.
      final StubPackSource library = stub(
        <String, Quantity?>{'5000157024671': null},
        name: 'Your foods',
        fromLibrary: true,
      );
      await openPackSizes(
        tester,
        foods: <Food>[marinara(barcode: '5000157024671')],
        sources: <NutritionSource>[
          library,
          stub(<String, Quantity?>{
            '5000157024671': Quantity.of(24, Units.ounce),
          }),
        ],
      );

      await tester.tap(find.text('Look up 1 barcode'));
      await pumpFrames(tester, frames: 20);

      expect(library.asked, isNotEmpty, reason: 'the chain is still in order');
      expect(find.text('Use 24 oz, from Open Food Facts'), findsOneWidget);
    });
  });

  group('the photograph', () {
    testWidgets('reads the net contents off the packet', (
      WidgetTester tester,
    ) async {
      await openPackSizes(
        tester,
        foods: <Food>[marinara()],
        labelReader: FakeLabelReader(
          pack: PackReading(size: Quantity.of(24, Units.ounce)),
        ),
        photoPicker: FakeCamera(),
      );

      await tester.tap(find.text('Photograph it'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Use 24 oz, from the photo'), findsOneWidget);
    });

    testWidgets('a flagged reading arrives unticked', (
      WidgetTester tester,
    ) async {
      // The reader has said in as many words that this is the one to look at.
      // Pre-ticking it would be Hearth overruling its own warning on a value
      // that fails silently at a shelf.
      await openPackSizes(
        tester,
        foods: <Food>[marinara()],
        labelReader: FakeLabelReader(
          pack: PackReading(
            size: Quantity.of(24, Units.ounce),
            uncertain: const <AiUncertainty>[
              AiUncertainty(field: 'amount', note: 'The 4 could be a 1.'),
            ],
          ),
        ),
        photoPicker: FakeCamera(),
      );

      await tester.tap(find.text('Photograph it'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('The 4 could be a 1.'), findsOneWidget);
      expect(find.textContaining('Save '), findsNothing);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets('a photo with no net contents on it says so', (
      WidgetTester tester,
    ) async {
      await openPackSizes(
        tester,
        foods: <Food>[marinara()],
        labelReader: FakeLabelReader(),
        photoPicker: FakeCamera(),
      );

      await tester.tap(find.text('Photograph it'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.text('No net contents could be read off that photo.'),
        findsOneWidget,
      );
      expect(find.textContaining('Save '), findsNothing);
    });

    testWidgets('a build with no reader does not offer a camera', (
      WidgetTester tester,
    ) async {
      await openPackSizes(
        tester,
        foods: <Food>[marinara()],
        photoPicker: FakeCamera(),
      );

      expect(find.text('Photograph it'), findsNothing);
      // Typing it in is always there, and is what the other two fall back to.
      expect(find.text('Type it in'), findsOneWidget);
    });
  });

  // The §6.3 baseline, checked by Flutter's own auditors. The shared sweep in
  // `guidelines_test.dart` only walks the four tabs, and this screen is two
  // taps past one of them — so the check comes with it rather than being
  // somebody's later good intention.
  for (final Brightness brightness in Brightness.values) {
    final String theme = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('every control here is reachable, labelled and legible in '
        '$theme', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpHearthApp(
        tester,
        brightness: brightness,
        foods: <Food>[marinara(barcode: '5000157024671')],
        nutritionSources: <NutritionSource>[
          stub(<String, Quantity?>{
            '5000157024671': Quantity.of(24, Units.ounce),
          }),
        ],
        labelReader: FakeLabelReader(),
        photoPicker: FakeCamera(),
      );
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Foods with no pack size'));
      await pumpFrames(tester, frames: 12);

      // The three ways in, as the row first offers them.
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      // And the review state, which has the tick, the discard and the save
      // bar — none of which exist until something has been found.
      await tester.tap(find.text('Look up 1 barcode'));
      await pumpFrames(tester, frames: 20);

      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  testWidgets('the list survives a small phone at three times the text', (
    WidgetTester tester,
  ) async {
    // A row of counted lines with three labelled buttons under it is exactly
    // the shape that breaks at large text, and this screen opens no sheet, so
    // the surface sweep never visits it.
    await openPackSizes(
      tester,
      foods: <Food>[marinara(barcode: '5000157024671')],
      sources: <NutritionSource>[
        stub(<String, Quantity?>{
          '5000157024671': Quantity.of(24, Units.ounce),
        }),
      ],
      size: const Size(320, 568),
      scale: 3,
    );

    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Look up 1 barcode'));
    await pumpFrames(tester);
    await tester.tap(find.text('Look up 1 barcode'));
    await pumpFrames(tester, frames: 20);

    // The row is below the fold at this size, and a lazy list does not build
    // what is off the screen — so a check that only looked at the first
    // viewport would pass on a row that overflows.
    await tester.dragUntilVisible(
      find.textContaining('Use 24 oz'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await pumpFrames(tester, frames: 4);

    expect(find.textContaining('Use 24 oz'), findsOneWidget);
    expect(find.text('Save 1 pack size'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// A nutrition source that answers the barcodes it was handed.
class StubPackSource implements NutritionSource {
  StubPackSource(this.known, {required this.name, required this.fromLibrary});

  /// Barcode to the pack size that source has for it. A null value is a food
  /// it knows with no pack size on record, which is the common real answer.
  final Map<String, Quantity?> known;

  final String name;
  final bool fromLibrary;
  final List<String> asked = <String>[];

  @override
  String get displayName => name;

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async {
    asked.add(barcode);
    if (!known.containsKey(barcode)) return null;
    return NutritionMatch(
      food: Food(
        id: 'external-$barcode',
        name: 'Marinara sauce',
        source: FoodSource.openFoodFacts,
        barcode: barcode,
        packSize: known[barcode],
        servingOptions: const <ServingOption>[],
      ),
      source: FoodSource.openFoodFacts,
      confidence: 1,
      fromLibrary: fromLibrary,
    );
  }

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async =>
      const <NutritionMatch>[];
}
