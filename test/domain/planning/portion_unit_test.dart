import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// The arithmetic behind typing a portion in grams (spec §5.6, F06).
///
/// The cheapest surface to hold it on: what a raw unit converts to is a pure
/// question about numbers, and the answer is what reaches the `servings`
/// column — a count of the food's default serving, whatever unit typed it.
void main() {
  final ServingOption pot = aServing(
    id: 'pot',
    label: '170 g pot',
    amount: 170,
    unit: Units.gram,
    macros: const Macros(kcal: 281, proteinG: 17),
  );
  final ServingOption hundred = aServing(
    id: 'hundred',
    label: '100 g',
    amount: 100,
    unit: Units.gram,
    macros: const Macros(kcal: 165, proteinG: 10),
  );
  final ServingOption spoon = aServing(
    id: 'spoon',
    label: '1 tbsp',
    amount: 1,
    unit: Units.tbsp,
    macros: const Macros(kcal: 15),
  );
  final ServingOption glass = aServing(
    id: 'glass',
    label: '250 ml glass',
    amount: 250,
    unit: Units.millilitre,
    macros: const Macros(kcal: 110),
  );
  final ServingOption oneBar = aServing(
    id: 'one',
    label: '1 bar',
    amount: 1,
    unit: Units.bar,
    macros: const Macros(kcal: 210),
  );

  group('what is offered', () {
    test('a food measured by mass is offered grams and ounces', () {
      final List<PortionUnit> units = portionUnitsFor(
        aFood('Yoghurt', servingOptions: <ServingOption>[pot, hundred]),
      );

      expect(units.map((PortionUnit u) => u.label), <String>[
        '170 g pot',
        '100 g',
        'g',
        'oz',
      ]);
      expect(units.first.isRaw, isFalse);
      expect(units.last.isRaw, isTrue);
    });

    test('a food measured by volume is offered ml and fl oz, never grams', () {
      final List<PortionUnit> units = portionUnitsFor(
        aFood('Orange juice', servingOptions: <ServingOption>[glass]),
      );

      expect(units.map((PortionUnit u) => u.label), <String>[
        '250 ml glass',
        'ml',
        'fl oz',
      ]);
    });

    test('a food counted in bars is offered no raw unit at all', () {
      // Its serving already *is* the unit, and a gram figure for it would
      // have to be invented (spec §5.5).
      final List<PortionUnit> units = portionUnitsFor(
        aFood('Protein bar', servingOptions: <ServingOption>[oneBar]),
      );

      expect(units.map((PortionUnit u) => u.label), <String>['1 bar']);
    });

    test('a serving of another kind is left out', () {
      // A tablespoon against a 170 g pot needs a density the food has not
      // stated, and the stored count is a multiple of the pot.
      final List<PortionUnit> units = portionUnitsFor(
        aFood('Yoghurt', servingOptions: <ServingOption>[pot, spoon]),
      );

      expect(
        units.map((PortionUnit u) => u.label),
        isNot(contains('1 tbsp')),
        reason: 'an option that cannot be converted is not offered',
      );
    });

    test('a food with no serving at all offers nothing', () {
      expect(portionUnitsFor(aFood('Mystery')), isEmpty);
      expect(portionUnitsFor(null), isEmpty);
    });
  });

  group('what gets stored', () {
    final Quantity standard = pot.amount;

    test('an amount in grams is stored as a count of the default serving', () {
      final PortionUnit grams = const PortionUnit.raw(Units.gram);

      expect(
        grams.toDefaultServings(85, standard: standard),
        closeTo(0.5, 1e-12),
      );
      expect(
        grams.toDefaultServings(125, standard: standard),
        closeTo(0.7352941176, 1e-9),
      );
    });

    test('and reads back as the same amount', () {
      final PortionUnit grams = const PortionUnit.raw(Units.gram);
      final PortionUnit ounces = const PortionUnit.raw(Units.ounce);

      expect(grams.countOf(0.5, standard: standard), closeTo(85, 1e-12));
      expect(ounces.countOf(0.5, standard: standard), closeTo(2.9983, 1e-4));
    });

    test('a round trip through ounces loses nothing', () {
      final PortionUnit ounces = const PortionUnit.raw(Units.ounce);
      final double stored = ounces.toDefaultServings(6, standard: standard);

      expect(ounces.countOf(stored, standard: standard), closeTo(6, 1e-12));
    });

    test('a stored serving still counts itself', () {
      expect(
        PortionUnit.serving(hundred).countOf(1, standard: standard),
        closeTo(1.7, 1e-12),
        reason: 'a 170 g pot read in 100 g units is 1.7 of them',
      );
      expect(
        PortionUnit.serving(pot).toDefaultServings(2, standard: standard),
        closeTo(2, 1e-12),
      );
    });

    test('nothing is invented when the two cannot be compared', () {
      // A volume against a mass, and a food with no serving to compare to.
      // Both hand the number back untouched rather than crossing a kind
      // without a density (spec §5.5).
      final PortionUnit millilitres = const PortionUnit.raw(Units.millilitre);

      expect(millilitres.toDefaultServings(250, standard: standard), 250);
      expect(millilitres.countOf(2, standard: null), 2);
    });
  });

  group('how it is typed', () {
    test('a raw unit steps by something you would actually weigh', () {
      expect(const PortionUnit.raw(Units.gram).step, 5);
      expect(const PortionUnit.raw(Units.ounce).step, 0.25);
      expect(const PortionUnit.raw(Units.millilitre).step, 10);
      expect(const PortionUnit.raw(Units.flOz).step, 0.5);
      expect(
        PortionUnit.serving(pot).step,
        0.25,
        reason: 'servings still move in quarters',
      );
    });

    test('a converted amount is rounded to something readable', () {
      // One pot is 5.996473604060913 oz, which is not a number anybody can
      // read back off a field.
      expect(
        const PortionUnit.raw(Units.ounce).forDisplay(5.996473604060913),
        6,
      );
      expect(const PortionUnit.raw(Units.gram).forDisplay(85.04), 85);
      expect(
        PortionUnit.serving(pot).forDisplay(1 / 3),
        1 / 3,
        reason: 'a serving count keeps its thirds — writeAmount renders them',
      );
    });

    test('identity survives a trip through the remembered preference', () {
      final List<PortionUnit> units = portionUnitsFor(
        aFood('Yoghurt', servingOptions: <ServingOption>[pot, hundred]),
      );

      expect(
        PortionUnit.withId(units, 'unit:g'),
        const PortionUnit.raw(Units.gram),
      );
      expect(
        PortionUnit.withId(units, 'serving:hundred'),
        PortionUnit.serving(hundred),
      );
      expect(
        PortionUnit.withId(units, 'serving:gone'),
        isNull,
        reason: 'a serving that no longer exists falls back rather than throws',
      );
      expect(PortionUnit.withId(units, null), isNull);
    });
  });
}
