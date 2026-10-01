import 'dart:convert';

import '../models/food.dart';
import '../units/quantity.dart';
import 'shopping_contribution.dart';
import 'shopping_line.dart';

/// Several household foods can name the same retailer product. Their counts
/// travel together, so the cap applies to their combined product count.
abstract final class CartReviewCounts {
  static Map<String, int> combine(
    Iterable<({String productId, int count})> counts,
  ) {
    final Map<String, int> totals = <String, int>{};
    for (final ({String productId, int count}) value in counts) {
      totals.update(
        value.productId,
        (int count) => count + value.count,
        ifAbsent: () => value.count,
      );
    }
    return Map<String, int>.unmodifiable(totals);
  }
}

/// Content evidence that a trip-only purchase choice still describes its
/// shopping line and saved product. This is neither a persisted revision nor
/// a hash used for security. Volatile timestamps and unrelated food nutrition
/// edits are deliberately absent; an effective density change is relevant.
abstract final class CartReviewEvidence {
  static String capture(List<ShoppingLine> lines, Map<String, Food> foods) =>
      jsonEncode(<Object?>[
        for (final ShoppingLine line in lines)
          <Object?>[
            line.key,
            line.name,
            line.foodId,
            line.storeTag,
            line.checked,
            line.hasUnquantified,
            <Object?>[for (final Quantity q in line.planned) _quantity(q)],
            _quantity(line.wanted),
            _quantity(line.onHand),
            <Object?>[
              for (final ShoppingContribution c in line.contributions)
                <Object?>[
                  c.sourceKey,
                  c.hasUnquantified,
                  <Object?>[
                    for (final Quantity q in c.quantities) _quantity(q),
                  ],
                ],
            ],
            _food(line.foodId == null ? null : foods[line.foodId]),
          ],
      ]);

  static Object? _food(Food? food) => food == null
      ? null
      : <Object?>[
          food.id,
          food.householdId,
          food.name,
          food.brand,
          food.isDeleted,
          food.walmartItemId,
          _quantity(food.packSize),
          food.massDisplayMode.name,
          _number(food.effectiveGramsPerMillilitre),
        ];

  static Object? _quantity(Quantity? q) => q == null
      ? null
      : <Object?>[
          q.kind.name,
          _number(q.canonicalAmount),
          q.preferredUnit?.id,
          q.preferredUnit?.label,
          _number(q.preferredUnit?.toCanonical),
        ];

  static Object? _number(double? value) =>
      value == null || value.isFinite ? value : value.toString();
}
