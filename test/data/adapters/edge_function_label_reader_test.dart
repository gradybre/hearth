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
  test(
    'photo field provenance keeps known facts and drops arbitrary values',
    () {
      final reading = EdgeFunctionLabelReader.readingFrom(
        panel()
          ..['field_sources'] = {
            'package_amount': 'package',
            'servings': 'nutrition',
            'servings_per_container': 'invented',
            'extra': 'both',
          },
      );
      expect(reading.fieldSources, {
        'package_amount': 'package',
        'servings': 'nutrition',
      });
    },
  );

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
            contains('Nothing legible'),
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

  group('a packet unit and its weight', () {
    /// Exactly what the deployed function returned for a real protein tub
    /// reading "Serving Size 1 Rounded Scoop (31g)".
    ///
    /// Kept verbatim because the bug this guards against was a disagreement
    /// between the two ends: the server offered the model "scoop" and then
    /// filtered it out again on the way back, so the app never saw one. The
    /// live test crosses that seam; this one is the cheap half that runs
    /// without a key.
    Map<Object?, Object?> tub() => <Object?, Object?>{
      'name': null,
      'brand': null,
      'servings': <Object?>[
        <String, Object?>{
          'amount': 1,
          'unit': 'scoop',
          'kcal': 120,
          'protein_g': 24,
          'carb_g': 3,
          'fat_g': 1,
        },
        <String, Object?>{
          'amount': 31,
          'unit': 'g',
          'kcal': 120,
          'protein_g': 24,
          'carb_g': 3,
          'fat_g': 1,
        },
      ],
      'uncertain': <Object?>[],
    };

    test('both rows arrive, with the packet word intact', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(tub());

      expect(reading.servings, hasLength(2));
      expect(reading.servings.first.unitId, 'scoop');
      expect(reading.servings.first.amount, 1);
      expect(reading.servings.last.unitId, 'g');
      expect(reading.servings.last.amount, 31);
    });

    test('with the same macros, which is what makes the pair worth having', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(tub());

      expect(reading.servings.first.kcal, reading.servings.last.kcal);
      expect(reading.servings.first.proteinG, 24);
    });
  });

  group('the three minor nutrients (spec §5.6)', () {
    test('are read off the panel when the model returns them', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(
          servings: <Object?>[
            <String, Object?>{
              'amount': 1,
              'unit': 'oz',
              'kcal': 110,
              'protein_g': 7,
              'fiber_g': 0,
              'sodium_mg': 180,
              'cholesterol_mg': 30,
            },
          ],
        ),
      );

      expect(reading.servings.single.sodiumMg, 180);
      expect(reading.servings.single.cholesterolMg, 30);
      // Cheddar has no fibre and the panel prints a 0. That is a reading, not
      // a gap, and it has to arrive as one.
      expect(reading.servings.single.fiberG, 0);
    });

    test('a cropped panel leaves them unknown rather than zero', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(
          servings: <Object?>[
            <String, Object?>{
              'amount': 1,
              'unit': 'oz',
              'kcal': 110,
              'protein_g': 7,
            },
          ],
        ),
      );

      expect(reading.servings.single.fiberG, isNull);
      expect(reading.servings.single.sodiumMg, isNull);
      expect(reading.servings.single.cholesterolMg, isNull);
      expect(reading.servings.single.kcal, 110);
    });
  });

  group('the front-of-package facts (spec R9/R11)', () {
    test('a package amount and count read cleanly', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(servings: const <Object?>[])..addAll(<String, Object?>{
          'package_amount': 24,
          'package_unit': 'oz',
          'servings_per_container': 6,
          'servings_approximate': false,
          'package_basis': 'as_packaged',
        }),
      );

      expect(reading.packageSize, isNotNull);
      expect(reading.servingsPerContainer, 6);
      expect(reading.servingsApproximate, isFalse);
      expect(reading.packageBasis, 'as_packaged');
    });

    test('a front-only read is not treated as empty', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel(servings: const <Object?>[])..addAll(<String, Object?>{
          'package_amount': 24,
          'package_unit': 'oz',
        }),
      );

      expect(reading.servings, isEmpty);
      expect(reading.packageSize, isNotNull);
    });

    test('a zero or negative count is dropped, not treated as read', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel()..addAll(<String, Object?>{'servings_per_container': 0}),
      );
      expect(reading.servingsPerContainer, isNull);
    });

    test('an unrecognised basis reads as unknown', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel()..addAll(<String, Object?>{'package_basis': 'cooked'}),
      );
      expect(reading.packageBasis, 'unknown');
    });

    test('a missing basis reads as unknown', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(panel());
      expect(reading.packageBasis, 'unknown');
    });

    test('a package amount with no unit is dropped', () {
      final LabelReading reading = EdgeFunctionLabelReader.readingFrom(
        panel()..addAll(<String, Object?>{'package_amount': 24}),
      );
      expect(reading.packageSize, isNull);
    });

    test('nothing at all still throws', () {
      expect(
        () => EdgeFunctionLabelReader.readingFrom(
          panel(servings: const <Object?>[]),
        ),
        throwsA(isA<RecipeAiException>()),
      );
    });
  });
}
