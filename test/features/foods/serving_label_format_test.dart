import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

/// How a serving row reads where it is *shown* (spec R6, R10).
///
/// The package/nutrition dropdown names the serving a package converts to,
/// and it named it "0.6666666666666666 cup" — a number nobody wrote and
/// nobody could check against the packet in their hand. A measuring amount is
/// written the way a jug is marked, which is what `writeAmount` is for.
///
/// Display only. The quantity a save stores is the one that was read, to the
/// last digit, and these tests say so rather than taking it on trust.
void main() {
  test('a fraction reads as a fraction', () {
    expect(const ServingDraft(amount: '2/3', unitId: 'cup').label, '2/3 cup');
    expect(
      const ServingDraft(amount: '1 1/2', unitId: 'tbsp').label,
      '1 1/2 tbsp',
    );
  });

  test('a whole number still reads as a whole number', () {
    expect(const ServingDraft(amount: '85', unitId: 'g').label, '85 g');
    expect(const ServingDraft(amount: '1', unitId: 'cup').label, '1 cup');
    // A count has no unit word to add.
    expect(const ServingDraft(amount: '2', unitId: 'item').label, '2');
  });

  test('a stored 2/3 cup reopens reading as 2/3 cup', () {
    final Food onions = aFood(
      'Great Value Chopped Onions',
      servingOptions: <ServingOption>[
        aServing(
          id: 'serving-cup',
          amount: 2 / 3,
          unit: Units.cup,
          macros: const Macros(kcal: 35),
        ),
      ],
    );

    final ServingDraft reopened = FoodDraft.fromFood(onions).servings.single;
    expect(reopened.label, '2/3 cup');
  });

  test('and the amount it saves back is the one it was given', () {
    final Food onions = aFood(
      'Great Value Chopped Onions',
      servingOptions: <ServingOption>[
        aServing(
          id: 'serving-cup',
          amount: 2 / 3,
          unit: Units.cup,
          macros: const Macros(kcal: 35),
        ),
      ],
    );

    final ServingOption saved = FoodDraft.fromFood(onions)
        .toFood()
        .servingOptions
        .single;

    expect(
      saved.amount.canonicalAmount,
      onions.servingOptions.single.amount.canonicalAmount,
      reason: 'how it reads must not change what it is',
    );
    expect(saved.amount.preferredUnit, Units.cup);
    expect(saved.id, 'serving-cup');
    // The label a food carries is written by the same getter, so the saved
    // food reads back the way the packet does.
    expect(saved.label, '2/3 cup');
  });

  test('a decimal nobody measures in keeps its digits', () {
    // Only the fractions a kitchen uses are recognised. Anything else is
    // shown as entered rather than rounded into a number the user never
    // typed.
    expect(const ServingDraft(amount: '0.7', unitId: 'cup').label, '0.7 cup');
  });
}
