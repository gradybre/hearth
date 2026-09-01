import 'package:hearth/domain/foods/food_query.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

/// Foods that really are zero, against foods whose numbers are missing
/// (spec §5.5).
Food coffee({bool confirmed = false}) => aFood(
  'Black coffee',
  id: 'food-coffee',
  isZeroCalorie: confirmed,
  servingOptions: <ServingOption>[
    aServing(amount: 1, unit: Units.cup, macros: Macros.zero),
  ],
);

void main() {
  group('telling a real zero from a missing one', () {
    test('an unconfirmed all-zero food still asks to be looked at', () {
      // The common case, and the one the warning exists for: a half-filled
      // import that looks like a real entry and contributes nothing.
      expect(coffee().needsAttention, isTrue);
    });

    test('a confirmed one does not', () {
      // Without this the warning could never be cleared, and a warning that
      // cannot be cleared is one that stops being read.
      expect(coffee(confirmed: true).needsAttention, isFalse);
    });

    test('but no serving at all is still a gap, confirmed or not', () {
      // There is nothing to log whatever the macros would have been, so the
      // flag has nothing to vouch for.
      final Food empty = aFood('Nothing', id: 'food-empty').asZeroCalorie();
      expect(empty.servingOptions, isEmpty);
      expect(empty.needsAttention, isTrue);
    });

    test('a food with real numbers is unaffected either way', () {
      final Food yogurt = aFood(
        'Greek yogurt',
        id: 'food-yogurt',
        servingOptions: <ServingOption>[
          aServing(
            amount: 170,
            unit: Units.gram,
            macros: const Macros(kcal: 100, proteinG: 17),
          ),
        ],
      );
      expect(yogurt.needsAttention, isFalse);
      expect(yogurt.asZeroCalorie().needsAttention, isFalse);
    });
  });

  group('the needs-attention filter follows', () {
    test('it lists the unconfirmed one and not the confirmed one', () {
      final List<Food> shown = FoodSearch.apply(<Food>[
        coffee(),
        coffee(confirmed: true).withBrand('Confirmed'),
      ], const FoodFilter(needsAttention: true));

      expect(shown, hasLength(1));
      expect(shown.single.brand, isNull);
    });
  });
}
