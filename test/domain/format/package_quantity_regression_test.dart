// Regression-first tests for package/quantity display bugs (spec §4, §5.2).
//
// These document *current* behaviour that is wrong, ahead of a fix:
//  * Mass amounts >= 10 lose their fractional part entirely on display
//    (`_decimal` rounds to a whole number once the value reaches 10), so an
//    authored "14.5 oz" or "15.25 oz" package prints as a lie.
//  * The imperial mass ladder (oz -> lb) promotes as soon as the pound
//    amount reaches 1, so a doubled 28 oz can is silently re-labelled in
//    pounds even though the recipe was authored, and should stay, in ounces.
//
// Several tests here are expected to fail until those are fixed; they exist
// to prove the bug before it is patched, not to describe desired new API.
import 'package:hearth/domain/format/quantity_format.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/ingredient_consolidator.dart';
import 'package:hearth/domain/recipes/recipe_scaler.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  group('authored ounce packages should print exactly as authored', () {
    test('28 oz stays 28 oz', () {
      expect(QuantityFormat.format(Quantity.of(28, Units.ounce)), '28 oz');
    });

    test('14.5 oz stays 14.5 oz', () {
      expect(
        QuantityFormat.formatAsAuthored(Quantity.of(14.5, Units.ounce)),
        '14.5 oz',
      );
    });

    test('15.25 oz stays 15.25 oz', () {
      expect(
        QuantityFormat.formatAsAuthored(Quantity.of(15.25, Units.ounce)),
        '15.25 oz',
      );
    });
  });

  group('shopping-list consolidation of packaged ounces', () {
    test('two 12 oz packages combine to 24 oz', () {
      final List<Quantity> combined = IngredientConsolidator.combine(<Quantity>[
        Quantity.of(12, Units.ounce),
        Quantity.of(12, Units.ounce),
      ]);
      expect(combined, hasLength(1));
      expect(QuantityFormat.formatAsAuthored(combined.single), '24 oz');
      expect(QuantityFormat.format(combined.single), '24 oz');
      // The canonical total must be exact regardless of how it displays.
      expect(
        combined.single.canonicalAmount,
        closeTo(24 * Units.ounce.toCanonical, 1e-9),
      );
    });

    test('1 lb + 8 oz combines to 1.5 lb regardless of order', () {
      final Quantity forward = IngredientConsolidator.combine(<Quantity>[
        Quantity.of(1, Units.pound),
        Quantity.of(8, Units.ounce),
      ]).single;
      final Quantity reversed = IngredientConsolidator.combine(<Quantity>[
        Quantity.of(8, Units.ounce),
        Quantity.of(1, Units.pound),
      ]).single;

      expect(QuantityFormat.format(forward), '1.5 lb');
      expect(QuantityFormat.format(reversed), '1.5 lb');
      expect(forward.canonicalAmount, closeTo(reversed.canonicalAmount, 1e-9));
    });
  });

  group('recipe scaling of a canned/packaged ounce ingredient', () {
    Recipe cannedTomatoes() => aRecipe(
      ingredients: <RecipeIngredient>[
        anIngredient('canned tomatoes', amount: 28, unit: Units.ounce),
      ],
    );

    test('two 28 oz cans (2x scale) equal 56 oz and stay in ounces', () {
      final ScaledRecipe scaled = RecipeScaler.byMultiplier(
        cannedTomatoes(),
        2,
      );
      final RecipeIngredient scaledIngredient =
          scaled.recipe.allIngredients.single;

      // The unit a can is sold in should not be renamed just because the
      // shopping quantity crossed one pound.
      expect(scaledIngredient.quantity!.preferredUnit, Units.ounce);
      expect(
        QuantityFormat.formatIn(scaledIngredient.quantity!, Units.ounce),
        '56 oz',
      );
    });

    test('canonical total is exact even though display may be wrong', () {
      final ScaledRecipe scaled = RecipeScaler.byMultiplier(
        cannedTomatoes(),
        2,
      );
      expect(
        scaled.recipe.allIngredients.single.quantity!.canonicalAmount,
        closeTo(56 * Units.ounce.toCanonical, 1e-6),
      );
    });
  });

  group('volume promotion baseline (existing, correct behaviour)', () {
    test('3 tsp still promotes to 1 tbsp', () {
      expect(QuantityFormat.format(Quantity.of(3, Units.tsp)), '1 tbsp');
    });
  });
}
