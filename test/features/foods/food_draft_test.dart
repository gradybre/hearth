import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../support/fixtures.dart';

String Function() sequentialIds() {
  int next = 0;
  return () => 'id-${next++}';
}

FoodDraft draft({String name = 'Greek yogurt', List<ServingDraft>? servings}) =>
    FoodDraft(
      name: name,
      servings:
          servings ??
          const <ServingDraft>[
            ServingDraft(amount: '170', kcal: '100', protein: '17', carbs: '6'),
          ],
    );

void main() {
  fromLookupTests();

  group('validation', () {
    test('a name is required', () {
      expect(draft(name: '  ').nameError, isNotNull);
      expect(draft().nameError, isNull);
    });

    test('at least one usable serving is required', () {
      expect(
        draft(servings: const <ServingDraft>[ServingDraft()]).servingsError,
        isNotNull,
      );
      expect(draft().servingsError, isNull);
    });

    test('a serving needs a positive amount to count', () {
      expect(const ServingDraft(amount: '0').isUsable, isFalse);
      expect(const ServingDraft(amount: '-5').isUsable, isFalse);
      expect(const ServingDraft(amount: 'abc').isUsable, isFalse);
      expect(const ServingDraft(amount: '100').isUsable, isTrue);
    });

    test('a serving written as a fraction is a real amount', () {
      // Brendan's report: a 2/3 cup serving could not be saved. The keyboard
      // was half of it; the other half was here, where the amount was read
      // with a plain double parse that rejects every fraction a measuring
      // cup is actually marked with.
      expect(const ServingDraft(amount: '2/3').isUsable, isTrue);
      expect(
        const ServingDraft(amount: '2/3').amountValue,
        closeTo(2 / 3, 1e-12),
      );
      expect(
        const ServingDraft(amount: '1 1/2').amountValue,
        closeTo(1.5, 1e-12),
      );
      expect(
        const ServingDraft(amount: '1.5').amountValue,
        closeTo(1.5, 1e-12),
      );
      expect(const ServingDraft(amount: '½').amountValue, closeTo(0.5, 1e-12));
    });

    test('missing macros do not block a save', () {
      // A food with a known portion and unknown calories still beats no food
      // at all — flag, never block (spec §5.3).
      final FoodDraft d = draft(
        servings: const <ServingDraft>[ServingDraft(amount: '100')],
      );
      expect(d.isValid, isTrue);
      expect(
        d.toFood(idFactory: sequentialIds()).servingOptions.single.macros.kcal,
        0,
      );
    });
  });

  group('building a food', () {
    test('carries the serving amount, unit, and macros', () {
      final Food food = draft().toFood(idFactory: sequentialIds());
      final ServingOption serving = food.servingOptions.single;

      expect(serving.amount.amountIn(Units.gram), 170);
      expect(serving.macros.kcal, 100);
      expect(serving.macros.proteinG, 17);
      expect(serving.macros.carbG, 6);
      expect(serving.macros.fatG, 0);
    });

    test('labels each serving readably', () {
      expect(
        draft().toFood(idFactory: sequentialIds()).servingOptions.single.label,
        '170 g',
      );
      expect(const ServingDraft(amount: '1', unitId: 'cup').label, '1 cup');
      expect(const ServingDraft(amount: '2', unitId: 'item').label, '2');
    });

    test('blank rows are dropped rather than saved empty', () {
      final Food food = draft(
        servings: const <ServingDraft>[
          ServingDraft(amount: '100', kcal: '165'),
          ServingDraft(),
          ServingDraft(amount: '1', unitId: 'item', kcal: '284'),
        ],
      ).toFood(idFactory: sequentialIds());

      expect(food.servingOptions, hasLength(2));
    });

    test('trims text fields and nulls the empty ones', () {
      final Food food = const FoodDraft(
        name: '  Greek yogurt  ',
        brand: '   ',
        servings: <ServingDraft>[ServingDraft(amount: '170')],
      ).toFood(idFactory: sequentialIds());

      expect(food.name, 'Greek yogurt');
      expect(food.brand, isNull);
    });

    test('manual entry is recorded as its source', () {
      expect(
        draft().toFood(idFactory: sequentialIds()).source,
        FoodSource.manual,
      );
    });
  });

  group('editing an existing food', () {
    test('keeps the id so a save updates rather than duplicates', () {
      final Food original = draft().toFood(idFactory: sequentialIds());
      final FoodDraft reopened = FoodDraft.fromFood(original);

      expect(reopened.isEditing, isTrue);
      expect(reopened.toFood(idFactory: sequentialIds()).id, original.id);
    });

    test('reopens with the amounts in the units they were entered in', () {
      final Food original = const FoodDraft(
        name: 'Olive oil',
        servings: <ServingDraft>[
          ServingDraft(amount: '1', unitId: 'tbsp', kcal: '119'),
        ],
      ).toFood(idFactory: sequentialIds());

      final FoodDraft reopened = FoodDraft.fromFood(original);
      expect(reopened.servings.single.amount, '1');
      expect(reopened.servings.single.unitId, 'tbsp');
      expect(reopened.servings.single.kcal, '119');
    });

    test('a zero macro reopens as an empty field, not a literal zero', () {
      // Regression: reopening showed "0" in every unset macro field, so
      // typing "250" into it produced "0250".
      final Food original = draft(
        servings: const <ServingDraft>[ServingDraft(amount: '100')],
      ).toFood(idFactory: sequentialIds());

      final ServingDraft reopened = FoodDraft.fromFood(original)
          .servings
          .single;
      expect(reopened.kcal, isEmpty);
      expect(reopened.protein, isEmpty);
      expect(reopened.carbs, isEmpty);
      expect(reopened.fat, isEmpty);
      // The amount is still shown: it is required and meaningful.
      expect(reopened.amount, '100');
    });

    test('a full round trip preserves the servings exactly', () {
      final Food original = draft(
        servings: const <ServingDraft>[
          ServingDraft(amount: '170', kcal: '100', protein: '17'),
          ServingDraft(amount: '1', unitId: 'cup', kcal: '220'),
        ],
      ).toFood(idFactory: sequentialIds());

      final Food reSaved = FoodDraft.fromFood(original)
          .toFood(idFactory: sequentialIds());

      expect(reSaved.servingOptions, hasLength(2));
      for (int i = 0; i < reSaved.servingOptions.length; i++) {
        expect(
          reSaved.servingOptions[i].amount.canonicalAmount,
          closeTo(original.servingOptions[i].amount.canonicalAmount, 1e-9),
        );
        expect(
          reSaved.servingOptions[i].macros,
          original.servingOptions[i].macros,
        );
        // Serving ids are reused, so a log pointing at one still resolves.
        expect(reSaved.servingOptions[i].id, original.servingOptions[i].id);
      }
    });
  });

  test('a blank draft starts on the unit packets are labelled in', () {
    final FoodDraft blank = FoodDraft.blank();
    expect(blank.servings.single.unitId, 'g');
    expect(blank.servings.single.amount, '100');
    expect(blank.isValid, isFalse, reason: 'it still needs a name');
  });
}

void fromLookupTests() {
  group('FoodDraft.fromLookup', () {
    Food offMatch() => aFood(
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
          macros: const Macros(kcal: 478, proteinG: 6.4),
        ),
      ],
    );

    test('keeps what the food is', () {
      final FoodDraft draft = FoodDraft.fromLookup(offMatch());

      expect(draft.name, 'Digestive biscuits');
      expect(draft.brand, 'McVitie');
      expect(draft.barcode, '5000157024671');
      expect(draft.source, FoodSource.openFoodFacts);
      expect(draft.servings.single.kcal, '478');
    });

    test('rounds the arithmetic the source scaled for us', () {
      // A source quotes per 100 g and scales to its own serving, so a 207 g
      // portion arrives as 9.729 g of protein. Saving spurious precision is
      // harmless; showing it on a review screen is not — it reads as a
      // measurement rather than a division, and it is what the user is being
      // asked to check.
      final FoodDraft draft = FoodDraft.fromLookup(
        aFood(
          'Beanz',
          servingOptions: <ServingOption>[
            aServing(
              id: 'off:1:serving',
              amount: 207,
              unit: Units.gram,
              macros: const Macros(
                kcal: 163.53,
                proteinG: 9.729,
                carbG: 26.703,
                fatG: 0.414,
              ),
            ),
          ],
        ),
      );

      final ServingDraft serving = draft.servings.single;
      expect(serving.kcal, '164');
      expect(serving.protein, '9.7');
      expect(serving.carbs, '26.7');
      expect(serving.fat, '0.4');
    });

    test('a food already in the library is never rounded behind the user', () {
      // Rounding on reopen would edit stored macros on the next save, which is
      // a silent change to data the user did not touch.
      final FoodDraft draft = FoodDraft.fromFood(
        aFood(
          'Beanz',
          servingOptions: <ServingOption>[
            aServing(
              id: 'serving-1',
              amount: 207,
              unit: Units.gram,
              macros: const Macros(kcal: 163.53, proteinG: 9.729),
            ),
          ],
        ),
      );

      expect(draft.servings.single.kcal, '163.53');
      expect(draft.servings.single.protein, '9.729');
    });

    test('drops the source\'s own ids so the save is a new food', () {
      final FoodDraft draft = FoodDraft.fromLookup(offMatch());

      // "off:5000157024671" is Open Food Facts' identity for the product, not
      // this library's. Carrying it through would put a non-uuid where the
      // server types a uuid: the row saves locally, then is rejected on its
      // first sync, long after the user believed it was safe.
      expect(draft.existingId, isNull);
      expect(draft.servings.single.id, isNull);

      final Food saved = draft.toFood();
      expect(saved.id, isNot(startsWith('off:')));
      expect(Uuid.isValidUUID(fromString: saved.id), isTrue);
      expect(
        Uuid.isValidUUID(fromString: saved.servingOptions.single.id),
        isTrue,
      );
    });
  });
}
