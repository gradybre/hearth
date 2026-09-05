import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
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
  withLabelTests();
  packetServingTests();

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

    test('a fractional serving reopens as a fraction, not a long decimal', () {
      // A ⅔ cup serving came back as 0.6666666666666666 in the field —
      // neither what was typed nor anything anyone would type over it.
      final Food food = aFood(
        'Frozen chopped onions',
        servingOptions: <ServingOption>[
          aServing(
            amount: 2 / 3,
            unit: Units.cup,
            macros: const Macros(kcal: 35),
          ),
          aServing(amount: 1.5, unit: Units.tsp, macros: const Macros(kcal: 5)),
          aServing(amount: 0.7, unit: Units.cup, macros: const Macros(kcal: 9)),
        ],
      );

      final FoodDraft reopened = FoodDraft.fromFood(food);
      expect(reopened.servings.first.amount, '2/3');
      // A mixed number reads the way a spoon is measured, and parseAmount
      // reads it straight back.
      expect(reopened.servings[1].amount, '1 1/2');
      // A decimal that is not a kitchen fraction keeps its digits rather than
      // being rounded into something the user never entered.
      expect(reopened.servings[2].amount, '0.7');
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

/// Merging a photographed label into whatever is already on screen (§5.5).
void withLabelTests() {
  LabelReading reading({
    String? name,
    String? brand,
    List<LabelServing> servings = const <LabelServing>[
      LabelServing(
        amount: 1,
        unitId: 'oz',
        kcal: 110,
        proteinG: 7,
        carbG: 1,
        fatG: 9,
      ),
      LabelServing(
        amount: 0.25,
        unitId: 'cup',
        kcal: 110,
        proteinG: 7,
        carbG: 1,
        fatG: 9,
      ),
    ],
  }) => LabelReading(servings: servings, name: name, brand: brand);

  group('FoodDraft.withLabel', () {
    test('a row the source left empty gives way to the label', () {
      // Open Food Facts answers with a name and no numbers constantly, and
      // that is exactly when somebody reaches for the camera. Keeping the
      // empty row would leave "100 g · 0 kcal" sitting above two rows read
      // off the packet, for the user to notice and delete.
      final FoodDraft merged = const FoodDraft(
        name: 'Shredded cheddar',
        servings: <ServingDraft>[
          ServingDraft(amount: '100', kcal: '0', protein: '0', carbs: '0'),
        ],
      ).withLabel(reading());

      expect(merged.servings, hasLength(2));
      expect(merged.servings.first.unitId, 'oz');
    });

    test('unless the food really is zero, in which case it stays', () {
      // A confirmed zero is an answer, not a gap (see Food.isZeroCalorie), and
      // a label that says nothing new must not delete it.
      final FoodDraft merged = const FoodDraft(
        name: 'Black coffee',
        isZeroCalorie: true,
        servings: <ServingDraft>[
          ServingDraft(amount: '240', unitId: 'ml', kcal: '0'),
        ],
      ).withLabel(reading());

      expect(merged.servings, hasLength(3));
      expect(merged.servings.first.amount, '240');
    });

    test('and a label with nothing to say never empties the draft', () {
      final FoodDraft merged = const FoodDraft(
        name: 'Shredded cheddar',
        servings: <ServingDraft>[ServingDraft(amount: '100', kcal: '0')],
      ).withLabel(const LabelReading(servings: <LabelServing>[]));

      expect(merged.servings, hasLength(1));
    });

    test('the weight and the volume of one portion both arrive', () {
      // The whole reason this exists. Brendan's Kirkland cheddar says
      // "1oz (28g/about 1/4 cup)"; those two rows together are the only
      // statement of the food's density, and without them a recipe line
      // measured in cups can never resolve against it.
      final FoodDraft merged = FoodDraft.blank().withLabel(reading());

      expect(merged.servings, hasLength(2));
      expect(merged.servings[0].unitId, 'oz');
      expect(merged.servings[0].amount, '1');
      expect(merged.servings[1].unitId, 'cup');
      expect(merged.servings[1].amount, '1/4');
      expect(merged.servings[1].kcal, '110');
    });

    test('an untouched starter row is replaced, not left above them', () {
      final FoodDraft merged = FoodDraft.blank().withLabel(reading());
      expect(
        merged.servings.any((ServingDraft s) => s.unitId == 'g'),
        isFalse,
        reason: 'the 100 g default was never an answer',
      );
    });

    test('a starter row someone has typed into is theirs and is kept', () {
      final FoodDraft typed = const FoodDraft(
        name: '',
        servings: <ServingDraft>[ServingDraft(amount: '100', kcal: '400')],
      ).withLabel(reading());

      expect(typed.servings, hasLength(3));
      expect(typed.servings.first.kcal, '400');
    });

    test('an existing food keeps every serving it already had', () {
      // The case this is reached from: a food that has grams and needs a cup.
      // Replacing rather than appending would be exactly backwards.
      final FoodDraft existing = const FoodDraft(
        name: 'Kirkland cheddar',
        existingId: 'food-1',
        servings: <ServingDraft>[
          ServingDraft(id: 'serving-1', amount: '28', kcal: '110'),
        ],
      ).withLabel(reading());

      expect(existing.servings.first.id, 'serving-1');
      expect(existing.servings.first.amount, '28');
      expect(existing.servings, hasLength(3));
    });

    test('a portion already on the draft is not added twice', () {
      final FoodDraft existing = const FoodDraft(
        name: 'Kirkland cheddar',
        servings: <ServingDraft>[
          ServingDraft(id: 'serving-1', amount: '1/4', unitId: 'cup'),
        ],
      ).withLabel(reading());

      expect(existing.servings, hasLength(2));
      expect(
        existing.servings.where((ServingDraft s) => s.unitId == 'cup'),
        hasLength(1),
      );
    });

    test('a typed name and brand survive the photo', () {
      // A photo is evidence, not an authority. Overwriting what someone typed
      // is the worst kind of helpful.
      final FoodDraft merged = const FoodDraft(
        name: 'Sharp cheddar',
        brand: 'Kirkland',
        servings: <ServingDraft>[ServingDraft(amount: '100')],
      ).withLabel(reading(name: 'SHREDDED SHARP CHEDDAR', brand: 'Costco'));

      expect(merged.name, 'Sharp cheddar');
      expect(merged.brand, 'Kirkland');
    });

    test('an empty name and brand are filled from the label', () {
      final FoodDraft merged = FoodDraft.blank().withLabel(
        reading(name: 'Shredded Sharp Cheddar', brand: 'Kirkland Signature'),
      );

      expect(merged.name, 'Shredded Sharp Cheddar');
      expect(merged.brand, 'Kirkland Signature');
    });

    test('the barcode and the food being edited are carried through', () {
      // Reached from a barcode miss: the whole point is that the food which
      // comes out of it is found by the next scan.
      final FoodDraft merged = FoodDraft.forBarcode('0096619364756')
          .withLabel(reading());

      expect(merged.barcode, '0096619364756');
      expect(merged.isValid, isFalse, reason: 'it still needs a name');
    });

    test("the source's arithmetic is not shown as though it were measured", () {
      final FoodDraft merged = FoodDraft.blank().withLabel(
        reading(
          servings: const <LabelServing>[
            LabelServing(
              amount: 1,
              unitId: 'oz',
              kcal: 109.87,
              proteinG: 7.049,
              carbG: 0.977,
              fatG: 8.999,
            ),
          ],
        ),
      );

      final ServingDraft serving = merged.servings.single;
      expect(serving.kcal, '110');
      expect(serving.protein, '7');
      expect(serving.carbs, '1');
      expect(serving.fat, '9');
    });
  });
}

/// A packet that names its own portion, and its weight, in one line.
///
/// "1 Scoop (30 g)" is two facts: the serving people actually measure, and
/// what it weighs. Keeping only the grams leaves a tub you cannot log by the
/// scoop; keeping only the scoop leaves a number nothing can convert. The pair
/// is what makes either useful.
void packetServingTests() {
  group('a label that states a packet unit and a weight', () {
    test('both arrive, with the packet word intact', () {
      const LabelReading reading = LabelReading(
        servings: <LabelServing>[
          LabelServing(
            amount: 1,
            unitId: 'scoop',
            kcal: 120,
            proteinG: 24,
            carbG: 3,
            fatG: 1,
          ),
          LabelServing(
            amount: 30,
            unitId: 'g',
            kcal: 120,
            proteinG: 24,
            carbG: 3,
            fatG: 1,
          ),
        ],
      );

      final FoodDraft merged = FoodDraft.blank().withLabel(reading);

      expect(merged.servings, hasLength(2));
      expect(merged.servings.first.unitId, 'scoop');
      expect(merged.servings.first.amount, '1');
      expect(merged.servings.last.unitId, 'g');
      expect(merged.servings.last.amount, '30');
      // Same portion, so the same macros — that is what makes the pair a
      // statement about weight rather than two different servings.
      expect(merged.servings.first.kcal, merged.servings.last.kcal);
    });

    test('the packet word survives the round trip to a food', () {
      final FoodDraft merged = FoodDraft.blank()
          .copyWith(name: 'Whey protein')
          .withLabel(
            const LabelReading(
              servings: <LabelServing>[
                LabelServing(amount: 1, unitId: 'scoop', kcal: 120),
              ],
            ),
          );

      final Food food = merged.toFood(idFactory: sequentialIds());

      expect(food.servingOptions.single.amount.preferredUnit, Units.scoop);
      expect(food.servingOptions.single.label, '1 scoop');
    });
  });

  group('the Walmart product a food is bought as (spec §5.7)', () {
    FoodDraft draft({String link = '', String pack = ''}) => FoodDraft.blank()
        .copyWith(name: 'Ground beef', walmartItemId: link, packSize: pack);

    test('a pasted product link is stored as the item number', () {
      // Stored as the id, never as the link: a URL that stops parsing later
      // is a URL nothing can use, and the failure would surface in a basket.
      final Food food = draft(
        link: 'https://www.walmart.com/ip/Ground-Beef-80-20/10450479?from=/search',
      ).toFood();

      expect(food.walmartItemId, '10450479');
    });

    test('and so is a bare item number', () {
      expect(draft(link: '10450479').toFood().walmartItemId, '10450479');
    });

    test('something with no item number in it is stored as nothing', () {
      // Better absent than wrong — the editor says so beside the field.
      expect(draft(link: 'ground beef').toFood().walmartItemId, isNull);
      expect(draft().toFood().walmartItemId, isNull);
    });

    test('a pack size becomes a quantity', () {
      expect(
        draft(pack: '1 lb').toFood().packSize,
        Quantity.of(1, Units.pound),
      );
      expect(
        draft(pack: '7.2 oz').toFood().packSize,
        Quantity.of(7.2, Units.ounce),
      );
    });

    test('half a pack size is no pack size', () {
      // A number with no unit, or a unit Hearth does not know, would order
      // the wrong amount silently rather than fail.
      for (final String raw in <String>['lb', 'a bag', '0 lb', '']) {
        expect(draft(pack: raw).toFood().packSize, isNull, reason: raw);
      }
    });

    test('an existing food fills the fields back in', () {
      final Food saved = draft(link: '10450479', pack: '1 lb').toFood();

      final FoodDraft reopened = FoodDraft.fromFood(saved);

      expect(reopened.walmartItemId, '10450479');
      expect(reopened.packSize, '1 lb');
      // And survives an untouched round trip.
      expect(reopened.toFood().packSize, Quantity.of(1, Units.pound));
    });
  });

  group('a deduction survives the draft (spec §5.2)', () {
    FoodDraft aDeduction() => const FoodDraft(
      name: 'Make it a Lettuce Wrap',
      brand: "Freddy's",
      source: FoodSource.restaurant,
      isModifier: true,
      servings: <ServingDraft>[
        ServingDraft(amount: '1', unitId: 'item', kcal: '-180', carbs: '-25'),
      ],
    );

    test('toFood carries the flag', () {
      // Dropped here, the switch is silently discarded: the row lands locally
      // as a restaurant food with negative macros and *no* flag, which means
      // nothing filters it out of the picker or the log sheet — and the write
      // then fails against the hosted check, in the queue, where nobody sees
      // it.
      expect(aDeduction().toFood().isModifier, isTrue);
    });

    test('and its negatives are not an error while it is flagged', () {
      expect(aDeduction().macrosError, isNull);
      expect(aDeduction().isValid, isTrue);
    });

    test('and a modifier stops being one when it stops being a restaurant', () {
      // The switch that offers it is gated on the restaurant one, so a flag
      // left set would be invisible and unclearable — on a food nothing in
      // the app can reach, since a menu needs `source == restaurant` and a
      // modifier is kept out of every picker.
      final FoodDraft home = aDeduction().copyWith(
        source: FoodSource.manual,
        isModifier: false,
      );

      expect(home.isModifier, isFalse);
      expect(home.macrosError, isNotNull);
    });

    test('but they are the moment it is not', () {
      final FoodDraft plain = aDeduction().copyWith(isModifier: false);

      expect(plain.macrosError, isNotNull);
      expect(plain.isValid, isFalse);
    });
  });
}
