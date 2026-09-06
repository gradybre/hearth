import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';
import 'package:test/test.dart';

/// A stated nutrient survives being looked at (spec §5.6, R02).
///
/// The editor writes a value into a field with `writeAmount`, which renders
/// friendly fractions — half a gram becomes "1/2", because that is what a
/// person types into a measuring field. Reading it back with `double.tryParse`
/// cannot read that, and the two failures it produces are different and both
/// silent:
///
///  * a **major** macro falls through `?? 0` and becomes a stated **zero** —
///    a wrong number, not a gap;
///  * a **minor** nutrient becomes **null** — a fact the food really did state
///    demoted to "nobody said", which is the one distinction §5.6 rests on.
///
/// Neither shows on screen: the field still reads "1/2".
void main() {
  Food storedWith(Macros macros) => Food(
    id: 'food-1',
    name: 'Guard yoghurt',
    source: FoodSource.manual,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'serving-1',
        label: '1 pot',
        amount: Quantity.of(1, Units.item),
        macros: macros,
      ),
    ],
  );

  /// Open the stored food in the editor and save it again, touching nothing.
  Macros reopenAndSave(Macros stored) =>
      FoodDraft.fromFood(storedWith(stored))
          .toFood()
          .servingOptions
          .single
          .macros;

  group('a value the editor renders as a fraction', () {
    test('survives a reopen and save untouched', () {
      // The whole bug in one line: open a food, change nothing, press Save.
      const Macros stored = Macros(
        kcal: 90,
        proteinG: 0.5,
        carbG: 1.5,
        fatG: 0.25,
        fiberG: 0.5,
        sodiumMg: 0.75,
        cholesterolMg: 0.125,
      );

      final Macros back = reopenAndSave(stored);

      expect(back.proteinG, 0.5, reason: 'a major macro must not become 0');
      expect(back.carbG, 1.5);
      expect(back.fatG, 0.25);
      expect(back.fiberG, 0.5, reason: 'a stated minor must not become null');
      expect(back.sodiumMg, 0.75);
      expect(back.cholesterolMg, 0.125);
    });

    test('and a decimal the fraction table cannot express already did', () {
      // 0.7 is not within 1e-9 of any friendly fraction, so it was written as
      // "0.7" and read back fine. It is here so the fix cannot be a rewrite
      // that breaks the case that worked.
      final Macros back = reopenAndSave(
        const Macros(kcal: 90, proteinG: 0.7, fiberG: 0.3),
      );

      expect(back.proteinG, closeTo(0.7, 1e-9));
      expect(back.fiberG, closeTo(0.3, 1e-9));
    });
  });

  group('the distinctions that must survive with it', () {
    test('unknown stays unknown and a stated zero stays zero', () {
      final Macros back = reopenAndSave(
        const Macros(kcal: 90, fiberG: 0, sodiumMg: null),
      );

      expect(back.fiberG, 0, reason: 'water really does have no sodium');
      expect(back.sodiumMg, isNull, reason: 'nobody was ever asked');
    });

    test('a zero major macro is still zero', () {
      expect(reopenAndSave(const Macros(kcal: 90)).fatG, 0);
    });

    test('a deduction keeps its sign through the round trip', () {
      // Freddy's lettuce wrap: −180 kcal with a *positive* half gram of fibre
      // (spec §5.2). The mixed signs are what a "negate everything" reading
      // gets backwards, and −0.5 is exactly the shape that used to be written
      // as an unreadable "-1 1/2".
      final Macros back = reopenAndSave(
        const Macros(kcal: -180, carbG: -25.5, fiberG: 0.5),
      );

      expect(back.kcal, -180);
      expect(back.carbG, -25.5);
      expect(back.fiberG, 0.5);
    });
  });

  group('several servings, and an edit that touches none of them', () {
    test('every row keeps its own fractions', () {
      final Food stored = Food(
        id: 'food-2',
        name: 'Guard oats',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[
          ServingOption(
            id: 's1',
            label: '1 scoop',
            amount: Quantity.of(1, Units.item),
            macros: const Macros(kcal: 120, proteinG: 2.5, fiberG: 1.5),
          ),
          ServingOption(
            id: 's2',
            label: '100 g',
            amount: Quantity.of(100, Units.gram),
            macros: const Macros(kcal: 380, fatG: 0.75, sodiumMg: 2.5),
          ),
        ],
      );

      // Rename it and save — an edit that says nothing about any nutrient.
      final Food back = FoodDraft.fromFood(stored)
          .copyWith(name: 'Guard oats, rolled')
          .toFood();

      expect(back.servingOptions[0].macros.proteinG, 2.5);
      expect(back.servingOptions[0].macros.fiberG, 1.5);
      expect(back.servingOptions[1].macros.fatG, 0.75);
      expect(back.servingOptions[1].macros.sodiumMg, 2.5);
    });

    test('and repeated reopening does not erode them', () {
      // Once was enough to lose it, but a value that survives one trip and
      // dies on the third is the harder bug to believe in.
      Macros carried = const Macros(kcal: 90, proteinG: 0.5, fiberG: 0.25);
      for (int i = 0; i < 3; i++) {
        carried = reopenAndSave(carried);
      }

      expect(carried.proteinG, 0.5);
      expect(carried.fiberG, 0.25);
    });
  });

  group('text that is not a number', () {
    FoodDraft draftWith({String protein = '', String fiber = ''}) => FoodDraft(
      name: 'Guard food',
      servings: <ServingDraft>[
        ServingDraft(
          amount: '1',
          unitId: 'item',
          kcal: '90',
          protein: protein,
          fiber: fiber,
        ),
      ],
    );

    test('is refused by name, not swallowed', () {
      // The old reader turned this into a silent 0 on a major macro. A number
      // nobody typed is worse than a complaint about the one they did.
      final FoodDraft draft = draftWith(protein: 'about 12');

      expect(draft.macrosError, contains('protein'));
      expect(draft.isValid, isFalse);
    });

    test('and names each field rather than telling you to check them all', () {
      final FoodDraft draft = draftWith(protein: 'lots', fiber: 'some');

      expect(draft.macrosError, contains('protein'));
      expect(draft.macrosError, contains('fibre'));
    });

    test('but blank is an answer, not a mistake', () {
      // For the minor three it is the *only* way to say "nobody asked".
      expect(draftWith().macrosError, isNull);
      expect(draftWith().isValid, isTrue);
    });

    test('and a fraction typed by hand is readable, so it is not one', () {
      // Asserting the value, not merely the absence of a complaint: the old
      // reader also returned no error here, because "1 1/2" became a silent
      // zero and zero is not negative. Only the number tells the two apart.
      final FoodDraft draft = draftWith(protein: '1 1/2', fiber: '1/4');

      expect(draft.macrosError, isNull);
      expect(draft.servings.single.macros.proteinG, 1.5);
      expect(draft.servings.single.macros.fiberG, 0.25);
    });

    test('and a number half-typed is not a mistake yet', () {
      // The error renders live, so complaining at the first character of
      // "-180" or ".5" would put a red line under somebody mid-word.
      expect(draftWith(protein: '-').macrosError, isNull);
      expect(draftWith(protein: '.').macrosError, isNull);
      expect(draftWith(protein: '−').macrosError, isNull);
    });
  });

  group('what the field shows when it reopens', () {
    String fieldFor(Macros stored, String Function(ServingDraft) pick) =>
        pick(FoodDraft.fromFood(storedWith(stored)).servings.single);

    test('is a decimal, because the keyboard has no slash on it', () {
      // The seven nutrient fields carry a decimal keypad. A stored 1.5
      // reopening as "1 1/2" was a value you could see, could break with one
      // backspace, and could not repair — there is no "/" to press.
      expect(
        fieldFor(const Macros(kcal: 90, proteinG: 1.5), (s) => s.protein),
        '1.5',
      );
      expect(
        fieldFor(const Macros(kcal: 90, fiberG: 0.5), (s) => s.fiber),
        '0.5',
      );
    });

    test('and a whole number keeps no decimal point', () {
      expect(
        fieldFor(const Macros(kcal: 90, proteinG: 12), (s) => s.protein),
        '12',
      );
    });

    test('and a stated zero still reads "0" for a minor nutrient', () {
      expect(fieldFor(const Macros(kcal: 90, fiberG: 0), (s) => s.fiber), '0');
    });
  });
}
