import 'package:hearth/data/adapters/shopping_export.dart';
import 'package:hearth/data/adapters/walmart_export.dart';
import 'package:hearth/domain/format/food_quantity_format.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/recipes/ingredient_consolidator.dart';
import 'package:hearth/domain/shopping/cart_quantity.dart';
import 'package:hearth/domain/shopping/pack_display.dart';
import 'package:hearth/domain/shopping/shopping_contribution.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/shopping/shopping_list_builder.dart';
import 'package:hearth/domain/units/mass_display_mode.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// A packaged food on a shopping list (spec R5-R9, R12).
///
/// The worked example throughout: a 10 oz package, a 1 cup nutrition
/// serving, and 2 servings in the package. One cup of it is therefore 5 oz,
/// 30 oz is three packages, and a recipe asking for cups can be shopped for
/// in jars without anybody typing a density.
///
/// The name is deliberately one no density table has heard of, so every
/// conversion here is the food's own or none at all.
void main() {
  const String name = 'sparkle powder';

  Food packaged({
    String id = 'f-sparkle',
    Quantity? pack,
    Quantity? reviewedPack,
    Quantity? serving,
    double servingsPerPackage = 2,
    MassDisplayMode mode = MassDisplayMode.automatic,
  }) {
    final Quantity packAmount = pack ?? Quantity.of(10, Units.ounce);
    final Quantity servingAmount = serving ?? Quantity.of(1, Units.cup);
    return Food(
      id: id,
      householdId: 'household-1',
      name: 'Sparkle powder',
      source: FoodSource.manual,
      packSize: packAmount,
      massDisplayMode: mode,
      servingOptions: <ServingOption>[
        ServingOption(
          id: '$id-cup',
          label: '1 cup',
          amount: servingAmount,
          macros: const Macros(kcal: 100, proteinG: 7, carbG: 1, fatG: 8),
        ),
      ],
      packageNutrition: PackageNutrition.manual(
        servingsPerPackage: servingsPerPackage,
        servingOptionId: '$id-cup',
        servingAmount: servingAmount,
        // Reviewed against a package that may since have changed, which is
        // what makes a relationship go stale.
        packageAmount: reviewedPack ?? packAmount,
      ),
    );
  }

  Food bare(String id) => Food(
    id: id,
    householdId: 'household-1',
    name: 'Sparkle powder',
    source: FoodSource.manual,
    servingOptions: const <ServingOption>[],
  );

  ShoppingLine lineOf(
    List<Quantity> planned, {
    Quantity? onHand,
    Quantity? wanted,
    String foodId = 'f-sparkle',
  }) => ShoppingLine(
    key: foodId,
    name: name,
    planned: planned,
    onHand: onHand,
    wanted: wanted,
    foodId: foodId,
  );

  List<Quantity> shopped(List<Quantity> amounts, Food? food) =>
      IngredientConsolidator.combine(
        amounts,
        displayName: name,
        food: food,
        preferPackKind: true,
      );

  group('the package relationship answers the shop', () {
    test('30 oz of a 10 oz package is three of them', () {
      final Food food = packaged();
      final ShoppingLine line = lineOf(<Quantity>[
        Quantity.of(30, Units.ounce),
      ]);

      expect(CartQuantity.forLine(line: line, pack: food.packSize), 3);
      expect(PackDisplay.forLine(line: line, pack: food.packSize), '3 × 10 oz');
    });

    test('and two cups of it is one of them', () {
      // 2 servings of 1 cup is the whole 10 oz package, so a recipe written
      // in cups can be counted in packages without anybody stating a
      // density — the label already did.
      final List<Quantity> total = shopped(<Quantity>[
        Quantity.of(2, Units.cup),
      ], packaged());

      expect(total.single.kind, UnitKind.mass);
      expect(total.single.amountIn(Units.ounce), closeTo(10, 1e-9));
      // In the package's own unit, not grams.
      expect(total.single.preferredUnit, Units.ounce);
    });

    test('mass and volume asked for together add up', () {
      final List<Quantity> total = shopped(<Quantity>[
        Quantity.of(5, Units.ounce),
        Quantity.of(1, Units.cup),
      ], packaged());

      expect(total, hasLength(1));
      expect(total.single.amountIn(Units.ounce), closeTo(10, 1e-9));
    });

    test('and a cup already in the cupboard comes off a need in ounces', () {
      // ShoppingLine.toBuy alone ignores an on-hand amount of another kind,
      // which sends you for the whole thing. The food is what makes the
      // subtraction legal.
      final ResolvedShoppingLine resolved = ShoppingLineResolver.resolve(
        line: lineOf(<Quantity>[
          Quantity.of(30, Units.ounce),
        ], onHand: Quantity.of(1, Units.cup)),
        food: packaged(),
      );

      expect(resolved.toBuy!.amountIn(Units.ounce), closeTo(25, 1e-9));
    });

    test('an amount set by hand is what gets counted', () {
      final ShoppingLine line = lineOf(<Quantity>[
        Quantity.of(30, Units.ounce),
      ], wanted: Quantity.of(20, Units.ounce));
      expect(CartQuantity.forLine(line: line, pack: line.wanted), 1);
      expect(
        PackDisplay.forLine(line: line, pack: Quantity.of(10, Units.ounce)),
        '2 × 10 oz',
      );
    });
  });

  group('what the relationship may not do', () {
    test('a stale one converts nothing', () {
      // The package is 12 oz now; the count was reviewed against 10 oz, so
      // it no longer describes anything real and the cups stay cups.
      final Food stale = packaged(
        pack: Quantity.of(12, Units.ounce),
        reviewedPack: Quantity.of(10, Units.ounce),
      );
      expect(stale.activePackageServing, isNull);
      expect(stale.hasStalePackageNutrition, isTrue);

      final List<Quantity> total = shopped(<Quantity>[
        Quantity.of(2, Units.cup),
      ], stale);
      expect(total.single.kind, UnitKind.volume);
    });

    test('and another product cannot borrow it for sharing a name', () {
      // Same name, different food. Density is scoped to the matched id, so
      // nothing crosses between them.
      final List<Quantity> total = shopped(<Quantity>[
        Quantity.of(2, Units.cup),
      ], bare('f-other'));

      expect(total.single.kind, UnitKind.volume);
      expect(packaged().effectiveGramsPerMillilitre, isNotNull);
      expect(bare('f-other').effectiveGramsPerMillilitre, isNull);
    });

    test('taking a source back off leaves the rest as it was written', () {
      final Food food = packaged();
      final ShoppingLine line = ShoppingContributions.settle(
        lineOf(const <Quantity>[]),
        contributions: <ShoppingContribution>[
          ShoppingContribution(
            kind: ShoppingSourceKind.recipe,
            refId: 'r-1',
            quantities: <Quantity>[Quantity.of(28, Units.ounce)],
          ),
          ShoppingContribution(
            kind: ShoppingSourceKind.recipe,
            refId: 'r-2',
            quantities: <Quantity>[Quantity.of(2, Units.cup)],
          ),
        ],
        food: food,
      );
      expect(line.planned.single.amountIn(Units.ounce), closeTo(38, 1e-9));

      final ShoppingLine after = ShoppingContributions.settle(
        line,
        contributions: ShoppingContributions.without(
          line.contributions,
          'recipe:r-2',
        ),
        food: food,
      );
      // Recomputed from the ask that is left, not subtracted from a total.
      expect(after.planned.single.amountIn(Units.ounce), closeTo(28, 1e-9));
      expect(after.planned.single.preferredUnit, Units.ounce);
    });
  });

  group('foods planned on their own', () {
    final DateTime day = DateTime.utc(2026, 9, 21);

    Food twoRows() => Food(
      id: 'f-yog',
      householdId: 'household-1',
      name: 'Yoghurt',
      source: FoodSource.manual,
      servingOptions: <ServingOption>[
        ServingOption(
          id: 'pot',
          label: '170 g pot',
          amount: Quantity.of(170, Units.gram),
          macros: const Macros(kcal: 100),
        ),
        ServingOption(
          id: 'big',
          label: '500 g tub',
          amount: Quantity.of(500, Units.gram),
          macros: const Macros(kcal: 300),
        ),
      ],
    );

    MealPlanEntry plannedEntry(String id, double servings, String? servingId) =>
        MealPlanEntry(
          id: id,
          dayId: 'day-1',
          slot: MealSlot.lunch,
          refType: PlanRefType.food,
          refId: 'f-yog',
          servings: servings,
          servingOptionId: servingId,
        );

    List<ShoppingLine> build(List<MealPlanEntry> entries, Food food) =>
        ShoppingListBuilder.forRange(
          from: day,
          to: day,
          entriesByDay: <DateTime, List<MealPlanEntry>>{day: entries},
          recipes: const <String, Recipe>{},
          foods: <String, Food>{food.id: food},
        );

    test('two servings rows are converted before either is added', () {
      // Two 170 g pots and one 500 g tub is 840 g — never three of
      // anything, which is what adding the counts first would have said.
      final List<ShoppingLine> lines = build(<MealPlanEntry>[
        plannedEntry('e-1', 2, 'pot'),
        plannedEntry('e-2', 1, 'big'),
      ], twoRows());

      expect(
        lines.single.planned.single.amountIn(Units.gram),
        closeTo(840, 1e-9),
      );
      expect(lines.single.hasUnquantified, isFalse);
    });

    test('a deleted row leaves the food on the list, unmeasured', () {
      final List<ShoppingLine> lines = build(<MealPlanEntry>[
        plannedEntry('e-1', 6, 'gone'),
      ], twoRows());

      // Skipping it entirely was a silently understated shop.
      expect(lines, hasLength(1));
      expect(lines.single.foodId, 'f-yog');
      // No invented count, either: nothing states what six of a row that no
      // longer exists comes to.
      expect(lines.single.planned, isEmpty);
      expect(lines.single.hasUnquantified, isTrue);
    });

    test('and what can be measured on that food still is', () {
      final List<ShoppingLine> lines = build(<MealPlanEntry>[
        plannedEntry('e-1', 2, 'pot'),
        plannedEntry('e-2', 6, 'gone'),
      ], twoRows());

      expect(
        lines.single.planned.single.amountIn(Units.gram),
        closeTo(340, 1e-9),
      );
      expect(lines.single.hasUnquantified, isTrue);
    });
  });

  group('how the total reads', () {
    test('Ounces pins ounces and Weight runs the ladder', () {
      final Quantity amount = Quantity.of(24, Units.ounce);
      expect(
        FoodQuantityFormat.format(
          amount,
          food: packaged(mode: MassDisplayMode.ounces),
        ),
        '24 oz',
      );
      expect(
        FoodQuantityFormat.format(
          amount,
          food: packaged(mode: MassDisplayMode.weight),
        ),
        '1.5 lb',
      );
    });

    test('12 oz corn doubled is two packages, not a pound and a half', () {
      final Food corn = Food(
        id: 'f-corn',
        householdId: 'household-1',
        name: 'Frozen corn',
        source: FoodSource.manual,
        servingOptions: const <ServingOption>[],
        packSize: Quantity.of(12, Units.ounce),
      );
      final ShoppingLine line = ShoppingLine(
        key: 'f-corn',
        name: 'frozen corn',
        planned: <Quantity>[Quantity.of(24, Units.ounce)],
        foodId: 'f-corn',
      );
      expect(PackDisplay.forLine(line: line, pack: corn.packSize), '2 × 12 oz');
    });

    test('and 56 oz of beans is two 28 oz cans', () {
      final ShoppingLine line = ShoppingLine(
        key: 'f-beans',
        name: 'canned beans',
        planned: <Quantity>[Quantity.of(56, Units.ounce)],
        foodId: 'f-beans',
      );
      expect(
        PackDisplay.forLine(line: line, pack: Quantity.of(28, Units.ounce)),
        '2 × 28 oz',
      );
    });

    test('and the export says exactly what the list says', () {
      final Food food = packaged();
      final ShoppingLine line = lineOf(<Quantity>[
        Quantity.of(30, Units.ounce),
      ]);

      final List<ShoppingExportItem> items = exportableLines(
        <ShoppingLine>[line],
        foods: <String, Food>{food.id: food},
      );
      expect(
        items.single.quantityLabel,
        PackDisplay.forLine(line: line, pack: food.packSize),
      );
      expect(items.single.quantity, 3);
    });
  });

  group('an ask keeps the measure it was written in', () {
    ShoppingLine asked(List<ShoppingContribution> asks, Food? food) =>
        ShoppingContributions.settle(
          lineOf(const <Quantity>[]),
          contributions: asks,
          food: food,
        );

    ShoppingContribution cups(String recipeId, double amount) =>
        ShoppingContribution(
          kind: ShoppingSourceKind.recipe,
          refId: recipeId,
          quantities: <Quantity>[Quantity.of(amount, Units.cup)],
        );

    test('the same recipe added twice is still cups', () {
      final Food food = packaged();
      final ShoppingLine once = asked(<ShoppingContribution>[
        cups('r-1', 2),
      ], food);
      final ShoppingLine twice = ShoppingContributions.settle(
        once,
        contributions: ShoppingContributions.merge(
          once.contributions,
          <ShoppingContribution>[cups('r-1', 2)],
          displayName: name,
          food: food,
        ),
        food: food,
      );

      final ShoppingContribution ask = twice.contributions.single;
      expect(ask.quantities.single.kind, UnitKind.volume);
      expect(ask.quantities.single.amountIn(Units.cup), closeTo(4, 1e-9));
      // Derived, and only derived.
      expect(twice.planned.single.amountIn(Units.ounce), closeTo(20, 1e-9));
    });

    test('and changing the servings per package changes only the total', () {
      final ShoppingLine line = asked(<ShoppingContribution>[
        cups('r-1', 2),
      ], packaged());
      expect(line.planned.single.amountIn(Units.ounce), closeTo(10, 1e-9));

      // Four 1 cup servings in the same 10 oz package: a cup weighs 2.5 oz
      // now, so the very same two cups is half as much to buy.
      final ShoppingLine again = ShoppingContributions.settle(
        line,
        contributions: line.contributions,
        food: packaged(servingsPerPackage: 4),
      );
      expect(
        again.contributions.single.quantities.single.kind,
        UnitKind.volume,
      );
      expect(again.planned.single.amountIn(Units.ounce), closeTo(5, 1e-9));
    });

    test('and taking the relation away puts the cups back', () {
      final ShoppingLine line = asked(<ShoppingContribution>[
        cups('r-1', 2),
      ], packaged());
      final ShoppingLine after = ShoppingContributions.settle(
        line,
        contributions: line.contributions,
        // Same identity, nothing left to convert with.
        food: bare('f-sparkle'),
      );
      expect(after.planned.single.kind, UnitKind.volume);
      expect(after.planned.single.amountIn(Units.cup), closeTo(2, 1e-9));
    });

    test('an amount written in ounces is untouched by any of it', () {
      final ShoppingLine line = asked(<ShoppingContribution>[
        ShoppingContribution(
          kind: ShoppingSourceKind.recipe,
          refId: 'r-2',
          quantities: <Quantity>[Quantity.of(30, Units.ounce)],
        ),
      ], packaged());

      expect(
        line.contributions.single.quantities.single.amountIn(Units.ounce),
        closeTo(30, 1e-9),
      );
      expect(line.planned.single.amountIn(Units.ounce), closeTo(30, 1e-9));
    });

    test('a pound and eight ounces is a pound and a half either way', () {
      final Quantity pound = Quantity.of(1, Units.pound);
      final Quantity eight = Quantity.of(8, Units.ounce);
      for (final List<Quantity> order in <List<Quantity>>[
        <Quantity>[pound, eight],
        <Quantity>[eight, pound],
      ]) {
        final List<Quantity> total = IngredientConsolidator.combine(
          order,
          displayName: 'beef',
        );
        expect(FoodQuantityFormat.format(total.single), '1.5 lb');
      }
    });
  });
}
