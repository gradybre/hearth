import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

/// Typing a portion in a unit the food only knows through its package
/// (spec R9–R12).
///
/// A jar of shredded cheddar states 10 oz on the front and 'about 2 servings'
/// of 1 cup on the back. That is enough to answer 'how much is 30 oz of it',
/// and until it was used the answer was a data gap on an otherwise
/// well-described food.
void main() {
  ServingOption cup(String id, {required double kcal, double? fiberG}) =>
      ServingOption(
        id: id,
        label: '1 cup',
        amount: Quantity.of(1, Units.cup),
        macros: Macros(kcal: kcal, proteinG: 1, fiberG: fiberG),
      );

  /// Two rows that read identically and carry different numbers, because the
  /// relationship is anchored to one of them and not to whichever is first.
  Food cheese({
    bool approximate = true,
    Quantity? pack,
    List<ServingOption>? servings,
    double selectedKcal = 100,
  }) => Food(
    id: 'food-cheese',
    name: 'Shredded cheddar',
    source: FoodSource.manual,
    servingOptions:
        servings ??
        <ServingOption>[
          // States fibre; the selected row does not.
          cup('cup-a', kcal: 200, fiberG: 7),
          cup('cup-b', kcal: selectedKcal),
        ],
    packSize: pack ?? Quantity.of(10, Units.ounce),
    packageNutrition: PackageNutrition.manual(
      servingsPerPackage: 2,
      servingOptionId: 'cup-b',
      servingAmount: Quantity.of(1, Units.cup),
      packageAmount: Quantity.of(10, Units.ounce),
      isApproximate: approximate,
    ),
  );

  const PortionUnit ounces = PortionUnit.raw(Units.ounce);

  group('what is offered', () {
    test('a package relationship earns the raw mass units', () {
      final List<String> labels = portionUnitsFor(cheese())
          .map((PortionUnit u) => u.label)
          .toList();

      expect(labels, contains('oz'));
      expect(labels, contains('g'));
      expect(labels.first, '1 cup');
    });

    test('a stale relationship earns nothing', () {
      // The jar was re-measured at 16 oz; the saved count describes a package
      // that is no longer this one, so it cannot answer for it (spec R10).
      final Food stale = cheese(pack: Quantity.of(16, Units.ounce));

      expect(stale.hasStalePackageNutrition, isTrue);
      expect(
        portionUnitsFor(stale).map((PortionUnit u) => u.label),
        isNot(contains('oz')),
      );
    });
  });

  group('what 30 oz comes to', () {
    test('six of the package serving', () {
      final PackagePortion? portion = packagePortionFor(
        food: cheese(),
        basis: ounces,
        servings: ounces.toDefaultServings(
          30,
          standard: Quantity.of(1, Units.cup),
          food: cheese(),
        ),
      );

      expect(portion, isNotNull);
      expect(portion!.servingCount, closeTo(6, 1e-9));
    });

    test('and the selected row is the one that costs it', () {
      // Both rows read '1 cup'. 600, not 1200: the relationship was reviewed
      // against the second one.
      final Food food = cheese();
      final double stored = ounces.toDefaultServings(
        30,
        standard: food.defaultServing!.amount,
        food: food,
      );

      expect(stored, closeTo(6, 1e-9));
      expect(
        packagePortionFor(
          food: food,
          basis: ounces,
          servings: stored,
        )!.macros.kcal,
        closeTo(600, 1e-9),
      );
    });

    test('and it carries the row it was costed from', () {
      final PackagePortion portion = packagePortionFor(
        food: cheese(),
        basis: ounces,
        servings: 6,
      )!;

      // Not cup-a, which reads identically and states fibre. Whoever freezes
      // these macros has to freeze that row's coverage beside them.
      expect(portion.serving.id, 'cup-b');
      expect(portion.macros.fiberG, isNull);
    });

    test('the About qualifier travels with it', () {
      expect(
        packagePortionFor(
          food: cheese(),
          basis: ounces,
          servings: 6,
        )!.isApproximate,
        isTrue,
      );
      expect(
        packagePortionFor(
          food: cheese(approximate: false),
          basis: ounces,
          servings: 6,
        )!.isApproximate,
        isFalse,
      );
    });

    test('a zero-calorie food converts too', () {
      // Nothing here divides by energy, so a food that carries none still has
      // a package that weighs something (spec R12).
      final PackagePortion? portion = packagePortionFor(
        food: cheese(selectedKcal: 0),
        basis: ounces,
        servings: 6,
      );

      expect(portion, isNotNull);
      expect(portion!.servingCount, closeTo(6, 1e-9));
      expect(portion.macros.kcal, 0);
    });
  });

  group('counted against a chosen serving', () {
    test('a half-cup row makes thirty ounces twelve of it', () {
      final Food food = cheese(
        servings: <ServingOption>[
          cup('cup-a', kcal: 200, fiberG: 7),
          cup('cup-b', kcal: 100),
          ServingOption(
            id: 'half',
            label: '1/2 cup',
            amount: Quantity.of(0.5, Units.cup),
            macros: const Macros(kcal: 50, proteinG: 1),
          ),
        ],
      );
      final ServingOption half = food.servingOptions.last;

      // The same weight, counted in half cups, is twelve of them.
      expect(
        const PortionUnit.raw(Units.ounce)
            .toDefaultServings(30, standard: half.amount, food: food),
        closeTo(12, 1e-9),
      );
      // And the package still answers in the row it was reviewed against,
      // which is six — not twelve, and not six of the first cup.
      final PackagePortion portion = packagePortionFor(
        food: food,
        basis: ounces,
        servings: 12,
        standard: half,
      )!;
      expect(portion.servingCount, closeTo(6, 1e-9));
      expect(portion.serving.id, 'cup-b');
      expect(portion.macros.kcal, closeTo(600, 1e-9));
    });

    test('and the units offered follow that row', () {
      final Food food = cheese();
      expect(
        portionUnitsFor(
          food,
          standard: food.servingOptions.last,
        ).map((PortionUnit u) => u.label),
        contains('oz'),
      );
    });
  });

  group('when it does not apply', () {
    test('a serving chip is answered directly', () {
      expect(
        packagePortionFor(
          food: cheese(),
          basis: PortionUnit.serving(cup('cup-a', kcal: 200)),
          servings: 1,
        ),
        isNull,
        reason: 'the food answers its own serving without a package',
      );
    });

    test('a food with a density of its own uses it', () {
      // Precedence (spec R12): a package fills a missing link, it does not
      // override one the food already has.
      final Food withOwn = cheese(
        servings: <ServingOption>[
          cup('cup-a', kcal: 200),
          cup('cup-b', kcal: 100),
          ServingOption(
            id: 'weight',
            label: '100 g',
            amount: Quantity.of(100, Units.gram),
            macros: const Macros(kcal: 80, proteinG: 1),
          ),
        ],
      );

      expect(withOwn.ownGramsPerMillilitre, isNotNull);
      expect(
        packagePortionFor(food: withOwn, basis: ounces, servings: 6),
        isNull,
      );
    });

    test('a stale relationship answers nothing at all', () {
      expect(
        packagePortionFor(
          food: cheese(pack: Quantity.of(16, Units.ounce)),
          basis: ounces,
          servings: 6,
        ),
        isNull,
      );
    });

    test('and without a food nothing is invented', () {
      // The old signature's behaviour, unchanged: no food, no crossing.
      expect(
        ounces.toDefaultServings(30, standard: Quantity.of(1, Units.cup)),
        30,
      );
      expect(packagePortionFor(food: null, basis: ounces, servings: 6), isNull);
    });
  });
}
