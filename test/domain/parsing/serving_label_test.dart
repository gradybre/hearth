import 'package:hearth/domain/parsing/serving_label.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  group('the measure a packet leads with', () {
    test('a volume in front of the metric figure', () {
      // Brendan's report: a Kirkland cheddar whose box says "1/4 cup" came
      // back offering nothing but grams.
      final Quantity? stated = statedHouseholdMeasure('1/4 cup (28 g)');
      expect(stated, isNotNull);
      expect(stated!.amountIn(Units.cup), closeTo(0.25, 1e-12));
    });

    test('a weight in front of the metric figure', () {
      final Quantity? stated = statedHouseholdMeasure('1 oz (28 g)');
      expect(stated!.amountIn(Units.ounce), closeTo(1, 1e-12));
    });

    test('a bare household measure with no metric figure beside it', () {
      // What the USDA function sends: "2 Tbsp", grams reported separately.
      final Quantity? stated = statedHouseholdMeasure('2 Tbsp');
      expect(stated!.amountIn(Units.tbsp), closeTo(2, 1e-12));
    });

    test('a vulgar fraction reads the same as a typed one', () {
      expect(
        statedHouseholdMeasure('¾ cup (28 g)')!.amountIn(Units.cup),
        closeTo(0.75, 1e-12),
      );
    });

    test('the metric figure itself is not a household measure', () {
      // There is nothing to restore: this is already what the source reports.
      expect(statedHouseholdMeasure('28 g'), isNull);
      expect(statedHouseholdMeasure('240 ml'), isNull);
    });

    test('things nobody can measure out are refused', () {
      // Guessing what a bar or a can weighs would put a wrong number into
      // someone's day.
      for (final String label in <String>[
        '1 serving (28 g)',
        '1 bar (43 g)',
        '0.5 Can (207 g)',
        'about a handful',
        '',
      ]) {
        expect(statedHouseholdMeasure(label), isNull, reason: label);
      }
    });
  });

  group('what a serving is stored as', () {
    test('a stated volume is kept, because it is the density', () {
      // "1/4 cup (28 g)" against a weight of grams is not a rounding of it —
      // it is this food's density, stated by its own maker, and often the
      // only place that fact exists.
      final Quantity amount = servingAmountFor('1/4 cup (28 g)', grams: 28);
      expect(amount.kind, UnitKind.volume);
      expect(amount.amountIn(Units.cup), closeTo(0.25, 1e-12));
    });

    test('a stated weight re-expresses the exact grams, not the label', () {
      // 1 oz is 28.35 g; the packet rounded it to 28 and the source kept 28.
      // The grams are what the maths uses, so they are what is stored.
      final Quantity amount = servingAmountFor('1 oz (28 g)', grams: 28);
      expect(amount.kind, UnitKind.mass);
      expect(amount.amountIn(Units.gram), closeTo(28, 1e-9));
      expect(amount.preferredUnit, Units.ounce);
    });

    test('a label naming nothing measurable leaves the grams alone', () {
      final Quantity amount = servingAmountFor('1 bar (43 g)', grams: 43);
      expect(amount.amountIn(Units.gram), closeTo(43, 1e-9));
      expect(amount.preferredUnit, Units.gram);
    });
  });
}
