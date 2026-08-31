import 'package:hearth/data/adapters/edge_function_label_reader.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:test/test.dart';

/// The function's response, read into a [LabelReading].
///
/// The network cannot be exercised here without mocking Supabase's client
/// whole, but the parse can — against every shape the function might send,
/// including the malformed ones it should never send.
Map<Object?, Object?> panel({
  Object? name = 'Shredded Sharp Cheddar Cheese',
  Object? brand = 'Kirkland Signature',
  List<Object?>? servings,
  List<Object?> uncertain = const <Object?>[],
}) => <Object?, Object?>{
  'name': name,
  'brand': brand,
  'servings':
      servings ??
      <Object?>[
        <String, Object?>{
          'amount': 1,
          'unit': 'oz',
          'kcal': 110,
          'protein_g': 7,
          'carb_g': 1,
          'fat_g': 9,
        },
        <String, Object?>{
          'amount': 0.25,
          'unit': 'cup',
          'kcal': 110,
          'protein_g': 7,
          'carb_g': 1,
          'fat_g': 9,
        },
      ],
  'uncertain': uncertain,
};

void main() {
  group('a label that read cleanly', () {
    test('carries both ways the panel states one portion', () {
      // Brendan's Kirkland cheddar: "Serving size 1oz (28g/about 1/4 cup)".
      // The weight and the volume together are the only statement of how
      // dense this food is, and it is what lets a recipe line measured in
      // cups resolve against a food the shop sells by weight.
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(panel());

      expect(reading.servings, hasLength(2));
      expect(reading.servings[0].unitId, 'oz');
      expect(reading.servings[0].amount, 1);
      expect(reading.servings[0].kcal, 110);
      expect(reading.servings[1].unitId, 'cup');
      expect(reading.servings[1].amount, 0.25);
    });

    test('carries what the packet is called', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(panel());
      expect(reading.name, 'Shredded Sharp Cheddar Cheese');
      expect(reading.brand, 'Kirkland Signature');
    });

    test('a panel photographed alone has no name, and that is fine', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(name: null, brand: '   '),
      );
      expect(reading.name, isNull);
      expect(reading.brand, isNull);
    });

    test('what was hard to read comes through as a flag', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(
          uncertain: <Object?>[
            <String, Object?>{'field': 'fat', 'note': 'could be 9 g or 8 g'},
          ],
        ),
      );

      expect(reading.uncertain.single.field, 'fat');
      expect(reading.uncertain.single.note, 'could be 9 g or 8 g');
    });
  });

  group('what the app cannot use is dropped, not guessed at', () {
    test('a serving with no positive amount', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(
          servings: <Object?>[
            <String, Object?>{'amount': 0, 'unit': 'oz', 'kcal': 110},
            <String, Object?>{'amount': 1, 'unit': 'oz', 'kcal': 110},
          ],
        ),
      );

      expect(reading.servings, hasLength(1));
    });

    test('a serving whose unit means nothing here', () {
      // The function narrows the model to Hearth's own unit ids, so this
      // should never arrive — and if it does, defaulting it to grams would
      // put a wrong number into a day, which is the one failure a review
      // screen cannot catch, because it looks correct.
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(
          servings: <Object?>[
            <String, Object?>{'amount': 1, 'unit': '', 'kcal': 110},
            <String, Object?>{'amount': 1, 'unit': 'cup', 'kcal': 110},
          ],
        ),
      );

      expect(reading.servings.single.unitId, 'cup');
    });

    test('a macro that is missing is zero, not a blocker', () {
      // Flag, never block (§5.3): a known portion with unknown fat still
      // beats no food at all.
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(
          servings: <Object?>[
            <String, Object?>{'amount': 1, 'unit': 'oz', 'kcal': 110},
          ],
        ),
      );

      expect(reading.servings.single.fatG, 0);
      expect(reading.servings.single.kcal, 110);
    });
  });

  group('a reading with nothing in it says so', () {
    test('no servings at all', () {
      // A photo of a hand, or a panel too dark to read. Saying so beats
      // opening an editor full of blanks and letting the user work out why.
      expect(
        () => EdgeFunctionLabelReader.readingFrom(
          panel(servings: const <Object?>[]),
        ),
        throwsA(
          isA<RecipeAiException>().having(
            (RecipeAiException e) => e.message,
            'message',
            contains('No serving sizes'),
          ),
        ),
      );
    });

    test('every serving dropped is the same as none', () {
      expect(
        () => EdgeFunctionLabelReader.readingFrom(
          panel(
            servings: <Object?>[
              <String, Object?>{'amount': -1, 'unit': 'oz'},
            ],
          ),
        ),
        throwsA(isA<RecipeAiException>()),
      );
    });

    test('a response with no servings key at all', () {
      expect(
        () => EdgeFunctionLabelReader.readingFrom(<Object?, Object?>{}),
        throwsA(isA<RecipeAiException>()),
      );
    });
  });
}
