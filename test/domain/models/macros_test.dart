import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/macros.dart';

/// The three minor nutrients (spec §5.6), and the one distinction the whole
/// feature rests on: **null is unknown, not zero.**
///
/// A food with no fibre data showing "0 g fibre" is a wrong number where no
/// number was the honest answer, and every arithmetic operator below is a
/// place that mistake would fit.
void main() {
  group('unknown is not zero', () {
    test('a food that says nothing about fibre says null, not 0', () {
      const Macros m = Macros(kcal: 100, proteinG: 10);
      expect(m.fiberG, isNull);
      expect(m.sodiumMg, isNull);
      expect(m.cholesterolMg, isNull);
    });

    test('and a food that says zero says zero', () {
      // Water genuinely has no sodium. That is a fact, not a gap, and it has
      // to survive every round trip below as one.
      const Macros m = Macros(sodiumMg: 0);
      expect(m.sodiumMg, 0);
      expect(m.sodiumMg, isNotNull);
    });

    test('two foods differing only in an unknown are not equal', () {
      expect(
        const Macros(kcal: 100),
        isNot(const Macros(kcal: 100, fiberG: 0)),
      );
      expect(
        const Macros(kcal: 100).hashCode,
        isNot(const Macros(kcal: 100, fiberG: 0).hashCode),
      );
    });

    test('isZero is about the four, and an unknown does not disturb it', () {
      expect(const Macros().isZero, isTrue);
      expect(const Macros(fiberG: 3).isZero, isTrue);
      expect(const Macros(kcal: 1, fiberG: 3).isZero, isFalse);
    });
  });

  group('adding', () {
    test('two known values add', () {
      const Macros a = Macros(kcal: 100, fiberG: 2, sodiumMg: 100);
      const Macros b = Macros(kcal: 50, fiberG: 3, sodiumMg: 50);
      expect((a + b).fiberG, 5);
      expect((a + b).sodiumMg, 150);
    });

    test('a known and an unknown keep the known', () {
      // The alternative — poisoning the total with null the moment one
      // ingredient is unmatched — would leave these blank essentially always,
      // which is the same as not having them (spec §4, §5.6).
      const Macros known = Macros(fiberG: 4);
      const Macros unknown = Macros();
      expect((known + unknown).fiberG, 4);
      expect((unknown + known).fiberG, 4);
    });

    test('two unknowns stay unknown', () {
      expect((const Macros() + const Macros()).fiberG, isNull);
      expect((const Macros() + const Macros()).sodiumMg, isNull);
      expect((const Macros() + const Macros()).cholesterolMg, isNull);
    });

    test('a known zero is not an unknown, and adding proves it', () {
      // 0 + unknown is 0 — somebody said zero, and that answer stands.
      expect((const Macros(fiberG: 0) + const Macros()).fiberG, 0);
    });
  });

  group('subtracting', () {
    test('two known values subtract', () {
      expect((const Macros(fiberG: 5) - const Macros(fiberG: 2)).fiberG, 3);
    });

    test('an unknown on either side leaves the known one alone', () {
      expect((const Macros(fiberG: 5) - const Macros()).fiberG, 5);
      expect((const Macros() - const Macros(fiberG: 5)).fiberG, -5);
      expect((const Macros() - const Macros()).fiberG, isNull);
    });
  });

  group('scaling', () {
    test('scales what is known', () {
      const Macros m = Macros(kcal: 100, fiberG: 3, sodiumMg: 200);
      expect(m.scaledBy(2).fiberG, 6);
      expect(m.scaledBy(2).sodiumMg, 400);
    });

    test('leaves unknown unknown, at any factor', () {
      // Half of "we do not know" is still "we do not know". Zero times it too:
      // scaling to nothing must not invent a number.
      expect(const Macros(kcal: 10).scaledBy(0.5).fiberG, isNull);
      expect(const Macros(kcal: 10).scaledBy(0).fiberG, isNull);
    });
  });

  group('summing a recipe', () {
    test('sums what is known across a mixed list', () {
      const List<Macros> parts = <Macros>[
        Macros(kcal: 100, fiberG: 2),
        Macros(kcal: 100),
        Macros(kcal: 100, fiberG: 3),
      ];
      final Macros total = Macros.sum(parts);
      expect(total.kcal, 300);
      expect(total.fiberG, 5);
    });

    test('is unknown only when nothing in the list knew', () {
      const List<Macros> parts = <Macros>[Macros(kcal: 100), Macros(kcal: 50)];
      expect(Macros.sum(parts).fiberG, isNull);
    });

    test('an empty sum is the zero macros with everything unknown', () {
      expect(Macros.sum(const <Macros>[]), Macros.zero);
      expect(Macros.sum(const <Macros>[]).fiberG, isNull);
    });
  });

  group('how much of a total was actually seen', () {
    test('a total nobody contributed to is not partial, it is absent', () {
      expect(const Macros().knows(MinorNutrient.fiber), isFalse);
    });

    test('a total with one contributor knows it', () {
      expect(const Macros(fiberG: 1).knows(MinorNutrient.fiber), isTrue);
      expect(const Macros(fiberG: 1).knows(MinorNutrient.sodium), isFalse);
    });

    test('each nutrient is read by its own kind, in its own unit', () {
      const Macros m = Macros(fiberG: 3, sodiumMg: 200, cholesterolMg: 15);
      expect(m.minor(MinorNutrient.fiber), 3);
      expect(m.minor(MinorNutrient.sodium), 200);
      expect(m.minor(MinorNutrient.cholesterol), 15);
    });
  });

  group('less than nothing (spec §5.2)', () {
    // One predicate, because two places ask this question — the eat-out
    // builder before it assembles a meal, and the macro calculator before it
    // lets one be logged — and two copies of it would drift.
    test('a meal that adds up is not below nothing', () {
      expect(const Macros(kcal: 380, carbG: 30).isBelowNothing, isFalse);
      expect(Macros.zero.isBelowNothing, isFalse);
    });

    test('a total under zero is, on any column', () {
      expect(const Macros(kcal: -377).isBelowNothing, isTrue);
      expect(const Macros(kcal: 10, carbG: -1).isBelowNothing, isTrue);
      expect(const Macros(proteinG: -1).isBelowNothing, isTrue);
      expect(const Macros(fatG: -1).isBelowNothing, isTrue);
    });

    test('and on a minor nutrient, which nobody watches', () {
      // A deduction can leave the calories standing while the fibre goes
      // under. Checking kcal alone would log a negative macro in silence.
      expect(const Macros(kcal: 10, fiberG: -1).isBelowNothing, isTrue);
      expect(const Macros(kcal: 10, sodiumMg: -1).isBelowNothing, isTrue);
      expect(const Macros(kcal: 10, cholesterolMg: -1).isBelowNothing, isTrue);
    });

    test('unknown is not negative', () {
      // Null means nobody said, and a gap is not a number below zero.
      expect(const Macros(kcal: 10).isBelowNothing, isFalse);
    });
  });
}
