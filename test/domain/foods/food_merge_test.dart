import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/food_merge.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// What merging two foods would do, worked out before anything is written
/// (review N05).
///
/// The safety note the review attaches to this one: "two foods with similar
/// names may have different servings or macros. A merge must show the
/// difference, preserve or convert compatible serving references explicitly,
/// protect pending writes, and never recalculate old logs."
void main() {
  Food yogurt({
    String id = 'f-keep',
    double amount = 170,
    Unit unit = Units.gram,
    String? barcode,
    double? density,
  }) => aFood(
    'Greek yogurt',
    id: id,
    barcode: barcode,
    gramsPerMillilitre: density,
    servingOptions: <ServingOption>[
      aServing(
        id: '$id-s',
        amount: amount,
        unit: unit,
        macros: const Macros(kcal: 100, proteinG: 17, carbG: 6),
      ),
    ],
  );

  MergePlan planOf({
    required Food survivor,
    required Food retiring,
    List<({String id, double servings})> planned =
        const <({String id, double servings})>[],
    int recipeLines = 0,
    List<StrandedLine> stranded = const <StrandedLine>[],
    int shoppingLines = 0,
    int rememberedMatches = 0,
    int loggedMeals = 0,
  }) => MergePlan.build(
    survivor: survivor,
    retiring: retiring,
    recipeLines: recipeLines,
    stranded: stranded,
    plannedEntries: planned,
    shoppingLines: shoppingLines,
    rememberedMatches: rememberedMatches,
    loggedMeals: loggedMeals,
  );

  group('the servings are unioned', () {
    test('a food that knew grams and one that knew cups knows both', () {
      // Strictly better for every reference either of them had, and what
      // keeps most recipe lines counting through the merge.
      final MergePlan plan = planOf(
        survivor: yogurt(amount: 170),
        retiring: yogurt(id: 'f-go', amount: 1, unit: Units.cup),
      );

      expect(plan.mergedServings, hasLength(2));
      expect(plan.merged.servingOptions, hasLength(2));
    });

    test('and the same portion twice is kept once, the survivor winning', () {
      final Food keep = yogurt(amount: 100);
      final MergePlan plan = planOf(
        survivor: keep,
        retiring: yogurt(id: 'f-go', amount: 100),
      );

      expect(plan.mergedServings, hasLength(1));
      expect(plan.mergedServings.single.id, keep.servingOptions.single.id);
    });

    test(
      'the same portion written in different units is still one portion',
      () {
        // 1000 g and 1 kg are the same portion. Both are canonicalised to
        // grams, so the collision is on what they measure rather than on how
        // either was typed.
        final MergePlan plan = planOf(
          survivor: yogurt(amount: 1000, unit: Units.gram),
          retiring: yogurt(id: 'f-go', amount: 1, unit: Units.kilogram),
        );

        expect(plan.mergedServings, hasLength(1));
      },
    );
  });

  group('what the survivor adopts', () {
    test('a barcode, when it has none of its own', () {
      // A barcode is how a packet is found again; dropping one costs a future
      // scan, and there is nothing to overwrite.
      final MergePlan plan = planOf(
        survivor: yogurt(),
        retiring: yogurt(id: 'f-go', barcode: '5000157024671'),
      );

      expect(plan.adoptedBarcode, '5000157024671');
      expect(plan.merged.barcode, '5000157024671');
    });

    test('and never over one it already has', () {
      final MergePlan plan = planOf(
        survivor: yogurt(barcode: '111'),
        retiring: yogurt(id: 'f-go', barcode: '222'),
      );

      expect(plan.adoptedBarcode, isNull);
      expect(plan.merged.barcode, '111');
    });

    test('a density, for the same reason', () {
      final MergePlan plan = planOf(
        survivor: yogurt(),
        retiring: yogurt(id: 'f-go', density: 1.03),
      );

      expect(plan.merged.gramsPerMillilitre, 1.03);
    });
  });

  group('a planned meal moves with its serving', () {
    test('the count changes so the food does not', () {
      // 1 x 170 g becomes 1.7 x 100 g. The plan still means 170 g of yogurt,
      // which is the whole point: a count is a count *of* something.
      final MergePlan plan = planOf(
        survivor: yogurt(amount: 100),
        retiring: yogurt(id: 'f-go', amount: 170),
        planned: <({String id, double servings})>[(id: 'e1', servings: 1)],
      );

      final PlannedMealMove move = plan.plannedMeals.single;
      expect(move.canConvert, isTrue);
      expect(move.toServings, closeTo(1.7, 0.0001));
      expect(move.isUnchanged, isFalse);
    });

    test('and does not change when the servings already match', () {
      final MergePlan plan = planOf(
        survivor: yogurt(amount: 170),
        retiring: yogurt(id: 'f-go', amount: 170),
        planned: <({String id, double servings})>[(id: 'e1', servings: 2)],
      );

      expect(plan.plannedMeals.single.isUnchanged, isTrue);
      expect(plan.canProceed, isTrue);
    });

    test('across mass and volume, when the food says what it weighs', () {
      // A food that knows what a millilitre of it weighs can answer for both.
      final MergePlan plan = planOf(
        survivor: yogurt(amount: 100, unit: Units.gram),
        retiring: yogurt(
          id: 'f-go',
          amount: 100,
          unit: Units.millilitre,
          density: 1.03,
        ),
        planned: <({String id, double servings})>[(id: 'e1', servings: 1)],
      );

      expect(plan.plannedMeals.single.toServings, closeTo(1.03, 0.0001));
    });

    test('but not from a count, which nothing can weigh', () {
      // "1 pot" against a food measured in grams: nothing says what one pot
      // weighs, and inventing a number would change what somebody planned.
      final MergePlan plan = planOf(
        survivor: yogurt(amount: 100, unit: Units.gram),
        retiring: yogurt(id: 'f-go', amount: 1, unit: Units.item),
        planned: <({String id, double servings})>[(id: 'e1', servings: 1)],
      );

      expect(plan.plannedMeals.single.canConvert, isFalse);
      expect(plan.unconvertible, hasLength(1));
      expect(
        plan.canProceed,
        isFalse,
        reason: 'the merge must refuse rather than guess at a plan',
      );
    });

    test('and a merge with nothing planned always can', () {
      expect(
        planOf(
          survivor: yogurt(),
          retiring: yogurt(id: 'f-go'),
        ).canProceed,
        isTrue,
      );
    });
  });

  group('what is counted, and what is left alone', () {
    test('everything that moves is added up for the button', () {
      final MergePlan plan = planOf(
        survivor: yogurt(),
        retiring: yogurt(id: 'f-go'),
        recipeLines: 4,
        stranded: <StrandedLine>[
          const StrandedLine(
            recipeId: 'r1',
            recipeTitle: 'Chilli',
            ingredientName: 'yogurt',
            unitLabel: 'cup',
          ),
        ],
        planned: <({String id, double servings})>[(id: 'e1', servings: 1)],
        shoppingLines: 1,
        rememberedMatches: 2,
        loggedMeals: 17,
      );

      expect(plan.moves, 9);
    });

    test('and logged meals are reported without being among them', () {
      // The reason a merge is safe at all: a logged entry freezes its macros
      // *and* its name, so a past day needs no reference to follow. Nothing
      // here may touch one, and the count exists to say so on the screen.
      final MergePlan plan = planOf(
        survivor: yogurt(),
        retiring: yogurt(id: 'f-go'),
        loggedMeals: 17,
      );

      expect(plan.loggedMeals, 17);
      expect(plan.moves, 0);
    });
  });
}
