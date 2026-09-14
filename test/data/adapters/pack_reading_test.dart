import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/edge_function_label_reader.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/domain/units/unit.dart';

/// Reading net contents off what the `pack` mode sends back (spec §5.7).
///
/// The parse is the seam worth testing, the same as the label parse beside it:
/// the function can be exercised against every shape it might send, including
/// the ones it should never send.
void main() {
  Map<Object?, Object?> jar({
    Object? amount = 24,
    Object? unit = 'oz',
    Object? name = 'Marinara Sauce',
    Object? brand = "Rao's Homemade",
    List<Object?> uncertain = const <Object?>[],
  }) => <Object?, Object?>{
    'amount': amount,
    'unit': unit,
    'name': name,
    'brand': brand,
    'uncertain': uncertain,
  };

  test('a printed net weight becomes a quantity in its own unit', () {
    final PackReading reading = EdgeFunctionLabelReader.packFrom(jar());

    expect(reading.size!.amountIn(Units.ounce), closeTo(24, 0.001));
    // The shop's own words. A 1.5-pound jar is the same weight and the wrong
    // thing to print on a shopping list.
    expect(reading.size!.preferredUnit, Units.ounce);
    expect(reading.name, 'Marinara Sauce');
    expect(reading.brand, "Rao's Homemade");
  });

  group('what is not an answer', () {
    test('no amount is no pack size, not a zero', () {
      final PackReading reading = EdgeFunctionLabelReader.packFrom(
        jar(amount: null),
      );

      expect(reading.size, isNull);
      expect(reading.isEmpty, isTrue);
    });

    test('nor an amount with no unit', () {
      // Half a pack size is not most of one: "24" of what decides whether the
      // shopping list asks for one jar or four.
      expect(EdgeFunctionLabelReader.packFrom(jar(unit: '')).size, isNull);
    });

    test('nor a unit this app cannot convert', () {
      // Dropped rather than defaulted to grams. A packet silently
      // reinterpreted as a weight it is not reads exactly as correct.
      expect(
        EdgeFunctionLabelReader.packFrom(jar(unit: 'furlong')).size,
        isNull,
      );
    });

    test('nor zero or a negative number', () {
      expect(EdgeFunctionLabelReader.packFrom(jar(amount: 0)).size, isNull);
      expect(EdgeFunctionLabelReader.packFrom(jar(amount: -24)).size, isNull);
    });

    test('and an empty envelope is an empty reading rather than a throw', () {
      // "The photo did not say" is the useful answer here, not a failure. A
      // pack size that was invented rather than read does not fail loudly — it
      // silently buys the wrong amount.
      final PackReading reading = EdgeFunctionLabelReader.packFrom(
        <Object?, Object?>{},
      );

      expect(reading.isEmpty, isTrue);
      expect(reading.name, isNull);
      expect(reading.uncertain, isEmpty);
    });
  });

  test('what the reader was unsure of comes with it', () {
    final PackReading reading = EdgeFunctionLabelReader.packFrom(
      jar(
        amount: null,
        uncertain: <Object?>[
          <Object?, Object?>{
            'field': 'amount',
            'note': 'This is a 6 x 250 ml multipack.',
          },
        ],
      ),
    );

    expect(reading.size, isNull);
    expect(reading.uncertain.single.note, 'This is a 6 x 250 ml multipack.');
  });

  test('a volume in litres survives as a volume', () {
    final PackReading reading = EdgeFunctionLabelReader.packFrom(
      jar(amount: 1.5, unit: 'l'),
    );

    expect(reading.size!.kind, UnitKind.volume);
    expect(reading.size!.amountIn(Units.litre), closeTo(1.5, 0.001));
  });
}
