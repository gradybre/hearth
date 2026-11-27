import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/recipes/macro_calculator.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

/// "2 cans of black beans", imported from a photo of a recipe, matched to a
/// food built from photographs of the can's own front and back.
///
/// The food is the shape that flow really produces: the panel's one serving
/// stated twice (½ cup and 130 g, identical macros, which is what states the
/// food's density), the front's net weight as the pack size, and "about 3.5
/// servings per container" as the reviewed package relationship.
///
/// Before this was fixed the line came back `unconvertible` — "Black beans —
/// no serving in can" — while the food's own label sat there saying how many
/// servings a can holds.
void main() {
  const Macros perServing = Macros(
    kcal: 110,
    proteinG: 7,
    carbG: 20,
    fatG: 0.5,
    fiberG: 6,
    sodiumMg: 250,
  );

  ServingOption halfCup() => aServing(
    amount: 0.5,
    unit: Units.cup,
    id: 'serving-cup',
    macros: perServing,
  );

  Food cannedBeans({
    double servingsPerPackage = 3.5,
    bool approximate = true,
    Quantity? packSize,
    Quantity? reviewedPack,
    List<ServingOption>? servingOptions,
  }) {
    final Quantity pack = packSize ?? Quantity.of(15, Units.ounce);
    return Food(
      id: 'food-beans',
      name: 'Black beans',
      source: FoodSource.manual,
      servingOptions:
          servingOptions ??
          <ServingOption>[
            halfCup(),
            aServing(amount: 130, unit: Units.gram, macros: perServing),
          ],
      packSize: pack,
      packageNutrition: PackageNutrition.manual(
        servingsPerPackage: servingsPerPackage,
        servingOptionId: 'serving-cup',
        servingAmount: Quantity.of(0.5, Units.cup),
        packageAmount: reviewedPack ?? pack,
        isApproximate: approximate,
        source: PackageNutritionSource.photos,
      ),
    );
  }

  IngredientMacros resolve(num amount, Unit unit, Food food) =>
      MacroCalculator.forIngredient(
        anIngredient(
          'black beans',
          amount: amount,
          unit: unit,
          foodId: food.id,
        ),
        food: food,
      );

  group('a recipe line counted in whole packages (spec R9, R10)', () {
    test('2 cans is twice what one can holds', () {
      final IngredientMacros result = resolve(2, Units.can, cannedBeans());

      expect(result.status, IngredientMacroStatus.resolved);
      expect(result.servingCount, closeTo(7, 1e-9));
      expect(
        result.serving?.id,
        'serving-cup',
        reason: 'the row the relationship was reviewed against',
      );
      expect(result.macros.kcal, closeTo(770, 1e-9));
      expect(result.macros.proteinG, closeTo(49, 1e-9));
      expect(result.macros.fiberG, closeTo(42, 1e-9));
      expect(result.macros.sodiumMg, closeTo(1750, 1e-9));
    });

    test('an "about" count stays qualified as approximate', () {
      expect(
        resolve(2, Units.can, cannedBeans()).usesApproximatePackage,
        isTrue,
      );
      expect(
        resolve(
          2,
          Units.can,
          cannedBeans(servingsPerPackage: 4, approximate: false),
        ).usesApproximatePackage,
        isFalse,
        reason: 'an unqualified printed count is exact',
      );
    });

    test('half a can is half the count, not a refusal', () {
      final IngredientMacros result = resolve(0.5, Units.can, cannedBeans());
      expect(result.status, IngredientMacroStatus.resolved);
      expect(result.servingCount, closeTo(1.75, 1e-9));
    });

    test("the food's own density does not block it: no density answers a "
        'count at all', () {
      final Food beans = cannedBeans();
      expect(
        beans.ownGramsPerMillilitre,
        isNotNull,
        reason: '½ cup and 130 g of one serving state this food\'s density',
      );
      expect(
        resolve(2, Units.can, beans).status,
        IngredientMacroStatus.resolved,
      );
    });

    test('every container word reaches it, by alias too', () {
      for (final Unit unit in <Unit>[
        Units.can,
        Units.packet,
        Units.container,
        Units.bottle,
        Units.package,
      ]) {
        expect(
          resolve(1, unit, cannedBeans()).status,
          IngredientMacroStatus.resolved,
          reason: '1 ${unit.label}',
        );
      }
      expect(Units.parse('cans'), Units.can);
      expect(Units.parse('tins'), Units.can);
      expect(Units.parse('tubs'), Units.container);
    });
  });

  group('what the package count must not answer', () {
    test('a word naming a portion out of the package, not the package', () {
      // A box of twelve bars holds twelve servings. Reading "2 bars" as two
      // boxes would multiply the line by twelve.
      for (final Unit unit in <Unit>[
        Units.bar,
        Units.slice,
        Units.scoop,
        Units.patty,
        Units.piece,
        Units.stick,
        Units.square,
        Units.tortilla,
        Units.clove,
        Units.item,
      ]) {
        expect(unit.namesAPackage, isFalse, reason: unit.id);
      }
      final IngredientMacros result = resolve(2, Units.bar, cannedBeans());
      expect(result.status, IngredientMacroStatus.unconvertible);
    });

    test('a food with no package relationship reports the gap', () {
      final Food plain = aFood(
        'Black beans',
        servingOptions: <ServingOption>[
          aServing(amount: 130, unit: Units.gram, macros: perServing),
        ],
      );
      expect(
        resolve(2, Units.can, plain).status,
        IngredientMacroStatus.unconvertible,
      );
    });

    test('a relationship gone stale against a changed pack size', () {
      // The reviewed pack was 15 oz; the food now says 28 oz. R10's rule is
      // that the saved count no longer describes anything real, so the line
      // is a gap again rather than quietly costed at the old can's size.
      final Food moved = cannedBeans(
        packSize: Quantity.of(28, Units.ounce),
        reviewedPack: Quantity.of(15, Units.ounce),
      );
      expect(moved.hasStalePackageNutrition, isTrue);
      expect(
        resolve(2, Units.can, moved).status,
        IngredientMacroStatus.unconvertible,
      );
    });

    test('a relationship whose anchored serving has been deleted', () {
      final Food gone = cannedBeans(
        servingOptions: <ServingOption>[
          aServing(amount: 130, unit: Units.gram, macros: perServing),
        ],
      );
      expect(gone.activePackageServing, isNull);
      expect(
        resolve(2, Units.can, gone).status,
        IngredientMacroStatus.unconvertible,
      );
    });

    test('an invalid relationship activates nothing', () {
      // A fluid-ounce package amount: net contents are a weight, and R9
      // refuses a volume there, so the record states nothing this can use.
      // It must stay refused here as well, not be read for its count alone.
      final Food bad = Food(
        id: 'food-bad',
        name: 'Black beans',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[halfCup()],
        packSize: Quantity.of(15, Units.flOz),
        packageNutrition: PackageNutrition.manual(
          servingsPerPackage: 3.5,
          servingOptionId: 'serving-cup',
          servingAmount: Quantity.of(0.5, Units.cup),
          packageAmount: Quantity.of(15, Units.flOz),
        ),
      );
      expect(bad.packageNutrition!.isValid, isFalse);
      expect(bad.servingsPerActivePackage, isNull);
      expect(
        resolve(2, Units.can, bad).status,
        IngredientMacroStatus.unconvertible,
      );
    });

    test('a prepared or drained panel is never read as the package, and '
        'cannot be made one', () {
      // R9: a net weight including packing liquid cannot state a drained
      // serving's weight. `asPackaged` is the only basis that activates, and
      // the factory takes no other — so there is no way to build a food
      // whose drained panel answers "2 cans". Pinned here because the count
      // route leans on that guard rather than repeating it.
      expect(PackageNutritionBasis.values, <PackageNutritionBasis>[
        PackageNutritionBasis.asPackaged,
      ]);
      final PackageNutrition unknownBasis = PackageNutrition.fromJson(
        <String, dynamic>{
          'version': 1,
          'servings_per_package': 3.5,
          'serving_option_id': 'serving-cup',
          'serving_amount': <String, dynamic>{
            'canonical_amount': Quantity.of(0.5, Units.cup).canonicalAmount,
            'kind': 'volume',
            'unit': 'cup',
          },
          'package_amount': <String, dynamic>{
            'canonical_amount': Quantity.of(15, Units.ounce).canonicalAmount,
            'kind': 'mass',
            'unit': 'oz',
          },
          'is_approximate': true,
          'source': 'photos',
          'basis': 'drained',
        },
      );
      expect(unknownBasis.isValid, isFalse);
      final Food drained = Food(
        id: 'food-drained',
        name: 'Black beans',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[halfCup()],
        packSize: Quantity.of(15, Units.ounce),
        packageNutrition: unknownBasis,
      );
      expect(
        resolve(2, Units.can, drained).status,
        IngredientMacroStatus.unconvertible,
      );
    });
  });

  group('which serving a count reaches (spec R12 precedence)', () {
    test("a serving in the line's own unit wins over the package count", () {
      final Food withCanRow = Food(
        id: 'food-beans',
        name: 'Black beans',
        source: FoodSource.manual,
        servingOptions: <ServingOption>[
          halfCup(),
          aServing(
            amount: 1,
            unit: Units.can,
            id: 'serving-can',
            macros: const Macros(kcal: 400, proteinG: 25),
          ),
        ],
        packSize: Quantity.of(15, Units.ounce),
        packageNutrition: PackageNutrition.manual(
          servingsPerPackage: 3.5,
          servingOptionId: 'serving-cup',
          servingAmount: Quantity.of(0.5, Units.cup),
          packageAmount: Quantity.of(15, Units.ounce),
        ),
      );
      final IngredientMacros result = resolve(2, Units.can, withCanRow);
      expect(result.serving?.id, 'serving-can');
      expect(result.servingCount, closeTo(2, 1e-9));
      expect(result.macros.kcal, closeTo(800, 1e-9));
      expect(result.usesApproximatePackage, isFalse);
    });

    test('a count takes the row in its own unit, not whichever count row is '
        'first', () {
      final Food bread = aFood(
        'Sourdough',
        servingOptions: <ServingOption>[
          aServing(
            amount: 1,
            unit: Units.slice,
            macros: const Macros(kcal: 80),
          ),
          aServing(
            amount: 1,
            unit: Units.item,
            macros: const Macros(kcal: 1600),
          ),
        ],
      );
      final IngredientMacros loaf = MacroCalculator.forIngredient(
        anIngredient('sourdough', amount: 1, unit: Units.item),
        food: bread,
      );
      expect(loaf.macros.kcal, closeTo(1600, 1e-9));
      final IngredientMacros slices = MacroCalculator.forIngredient(
        anIngredient('sourdough', amount: 2, unit: Units.slice),
        food: bread,
      );
      expect(slices.macros.kcal, closeTo(160, 1e-9));
    });

    test(
      'a count with no row in its own unit still falls back to the kind',
      () {
        // "3 cloves" against a food served by the item: the loose same-kind
        // match is what has always answered this, and still does.
        final Food garlic = aFood(
          'Garlic',
          servingOptions: <ServingOption>[
            aServing(
              amount: 1,
              unit: Units.item,
              macros: const Macros(kcal: 4),
            ),
          ],
        );
        final IngredientMacros result = MacroCalculator.forIngredient(
          anIngredient('garlic', amount: 3, unit: Units.clove),
          food: garlic,
        );
        expect(result.status, IngredientMacroStatus.resolved);
        expect(result.macros.kcal, closeTo(12, 1e-9));
      },
    );
  });

  group('the recipe around the line', () {
    test('a recipe of two cans is complete and says its figures are '
        'approximate', () {
      final Food beans = cannedBeans();
      final Recipe recipe = aRecipe(
        servings: 4,
        ingredients: <RecipeIngredient>[
          anIngredient(
            'black beans',
            amount: 2,
            unit: Units.can,
            foodId: beans.id,
          ),
        ],
      );
      final RecipeMacros macros = MacroCalculator.forRecipe(
        recipe,
        foods: <String, Food>{beans.id: beans},
      );
      expect(macros.isIncomplete, isFalse);
      expect(macros.incompleteReason, isNull);
      expect(macros.usesApproximatePackageNutrition, isTrue);
      expect(macros.total.kcal, closeTo(770, 1e-9));
      expect(macros.perServing.kcal, closeTo(192.5, 1e-9));
      expect(
        macros.coverage.of(MinorNutrient.fiber),
        MinorCoverage.complete,
        reason: 'the one ingredient stated fiber',
      );
    });
  });

  group('the container words are curated', () {
    test('every one of them is a count, and the list has not grown by '
        'accident', () {
      final List<String> named = <String>[
        for (final Unit unit in Units.all)
          if (unit.namesAPackage) unit.id,
      ];
      expect(named..sort(), <String>[
        'bottle',
        'can',
        'container',
        'package',
        'packet',
      ]);
      for (final Unit unit in Units.all) {
        if (!unit.namesAPackage) continue;
        expect(unit.kind, UnitKind.count, reason: unit.id);
      }
    });
  });
}
