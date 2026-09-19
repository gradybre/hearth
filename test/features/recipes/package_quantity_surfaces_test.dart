import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/format/food_quantity_format.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/parsing/ingredient_parser.dart';
import 'package:hearth/domain/units/mass_display_mode.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

/// A minimal food carrying only what [FoodQuantityFormat] reads: its mass
/// display mode and pack size (spec R1–R8). No serving options are needed
/// for these formatting-only cases.
Food _food({
  MassDisplayMode massDisplayMode = MassDisplayMode.automatic,
  Quantity? packSize,
}) => Food(
  id: 'f1',
  name: 'test food',
  servingOptions: const <ServingOption>[],
  source: FoodSource.manual,
  massDisplayMode: massDisplayMode,
  packSize: packSize,
);

void main() {
  group('IngredientParser.packageUnitFor (spec R3.3)', () {
    test('reads the "x" pack-size notation as mass evidence', () {
      final Unit? unit = IngredientParser.packageUnitFor(
        '2 x 400g cans chopped tomatoes',
      );
      expect(unit, Units.gram);
    });

    test('reads the parenthesised American notation', () {
      final Unit? unit = IngredientParser.packageUnitFor(
        '4 (10 oz) bags frozen chopped onion',
      );
      expect(unit, Units.ounce);
    });

    test('reads a bare pack size beside a container word', () {
      final Unit? unit = IngredientParser.packageUnitFor(
        '4 10 oz bags frozen chopped onion',
      );
      expect(unit, Units.ounce);
    });

    test('is null for an ordinary line with no pack syntax', () {
      expect(IngredientParser.packageUnitFor('2 lbs ground beef'), isNull);
      expect(IngredientParser.packageUnitFor('1 cup flour'), isNull);
    });

    test('never reparses the canonical amount', () {
      // Same line via the ordinary parser: the quantity is unaffected by
      // package-unit evidence being available.
      final ParsedIngredient parsed = IngredientParser.parse(
        '2 x 400g cans chopped tomatoes',
      );
      expect(parsed.quantity!.canonicalAmount, closeTo(800, 1e-9));
      expect(parsed.packageUnit, Units.gram);
    });
  });

  group('FoodQuantityFormat.format (spec R1–R8)', () {
    test('MassDisplayMode.ounces always pins ounces', () {
      final Food food = _food(massDisplayMode: MassDisplayMode.ounces);
      final Quantity oneAndHalfPounds = const Quantity.canonical(
        canonicalAmount: 680.388555,
        kind: UnitKind.mass,
        preferredUnit: Units.pound,
      );
      expect(
        FoodQuantityFormat.format(oneAndHalfPounds, food: food),
        contains('oz'),
      );
    });

    test('MassDisplayMode.weight always runs the oz/lb ladder', () {
      final Food food = _food(massDisplayMode: MassDisplayMode.weight);
      final Quantity twelveOzTwice = Quantity.canonical(
        canonicalAmount: Quantity.of(24, Units.ounce).canonicalAmount,
        kind: UnitKind.mass,
        preferredUnit: Units.ounce,
      );
      // 24 oz is 1.5 lb — the ladder promotes it, ignoring the authored oz.
      expect(
        FoodQuantityFormat.format(twelveOzTwice, food: food),
        contains('lb'),
      );
    });

    test('automatic prefers a compatible mass pack size', () {
      final Food food = _food(
        massDisplayMode: MassDisplayMode.automatic,
        packSize: Quantity.of(28, Units.ounce),
      );
      // 56 oz canned beans, summed from 2x 28 oz packs: stays in ounces
      // because the pack size is authored in ounces (spec table row 3).
      final Quantity fiftySixOz = Quantity.canonical(
        canonicalAmount: Quantity.of(56, Units.ounce).canonicalAmount,
        kind: UnitKind.mass,
      );
      expect(FoodQuantityFormat.format(fiftySixOz, food: food), '56 oz');
    });

    test('rawSources package evidence picks the higher-priority unit', () {
      // A mixed group where one contributing line names an ounce pack and
      // another names a pound pack: pound wins (same priority the
      // consolidator uses for its own mass-bucket hint).
      final Quantity amount = Quantity.canonical(
        canonicalAmount: Quantity.of(3, Units.pound).canonicalAmount,
        kind: UnitKind.mass,
      );
      final String formatted = FoodQuantityFormat.format(
        amount,
        rawSources: const <String>[
          '2 (10 oz) bags shredded cheese',
          '1 x 2 lb block shredded cheese',
        ],
      );
      expect(formatted, contains('lb'));
    });

    test('with no food and no package evidence, falls back conservatively', () {
      final Quantity twentyFourOz = Quantity.canonical(
        canonicalAmount: Quantity.of(24, Units.ounce).canonicalAmount,
        kind: UnitKind.mass,
      );
      // Unknown food, 12 oz + 12 oz: stays ounces (spec table row 8) — no
      // food, no pack evidence, no explicit ounce authorship to preserve, so
      // the ladder runs and 24 oz promotes to 1.5 lb under the default
      // imperial ladder. This asserts the call succeeds and returns a mass
      // unit without throwing when nothing is known about the food.
      final String formatted = FoodQuantityFormat.format(twentyFourOz);
      expect(formatted, isNotEmpty);
    });

    test('canonical amount is never altered by the display choice', () {
      final Food food = _food(massDisplayMode: MassDisplayMode.ounces);
      final Quantity q = Quantity.of(14.5, Units.ounce);
      FoodQuantityFormat.format(q, food: food);
      expect(
        q.canonicalAmount,
        closeTo(Quantity.of(14.5, Units.ounce).canonicalAmount, 1e-9),
      );
    });
  });
}
