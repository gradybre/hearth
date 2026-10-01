import 'package:meta/meta.dart';

import '../units/quantity.dart';
import 'shopping_contribution.dart';
import 'shopping_line.dart';
import 'shopping_list_builder.dart';

/// A plain shopping item reviewed by the person adding it.
@immutable
class ManualListItem {
  const ManualListItem({required this.name, this.quantity});

  final String name;
  final Quantity? quantity;
}

enum ManualAdditionSkipReason { alreadyOnList, duplicateInBatch }

/// An unchanged request that was skipped, at its original input position.
@immutable
class ManualAdditionSkip {
  const ManualAdditionSkip({
    required this.index,
    required this.item,
    required this.reason,
  });

  final int index;
  final ManualListItem item;
  final ManualAdditionSkipReason reason;
}

/// The complete list and the outcome of each reviewed request.
@immutable
class ManualAdditionResult {
  ManualAdditionResult({
    required List<ShoppingLine> lines,
    required List<ManualListItem> added,
    required List<ManualAdditionSkip> skipped,
  }) : lines = List<ShoppingLine>.unmodifiable(lines),
       added = List<ManualListItem>.unmodifiable(added),
       skipped = List<ManualAdditionSkip>.unmodifiable(skipped);

  final List<ShoppingLine> lines;
  final List<ManualListItem> added;
  final List<ManualAdditionSkip> skipped;
}

/// Literal text intake and duplicate-safe additions (spec §5.7).
abstract final class ManualAdditions {
  /// One trimmed nonempty line per item; wording and amounts are not inferred.
  static List<ManualListItem> fromText(String text) => <ManualListItem>[
    for (final String line in text.split(RegExp(r'\r\n|\r|\n')))
      if (line.trim().isNotEmpty) ManualListItem(name: line.trim()),
  ];

  /// Validates the whole batch before appending anything to [current].
  ///
  /// Existing rows win without changing their quantities or decisions. Names
  /// use the same normalization as shopping keys, including the visible name
  /// of a food-backed row whose own key is a food id. No word matching is used.
  /// Existing duplicates are always reported as [ManualAdditionSkipReason.alreadyOnList];
  /// repeats of a newly added item are [ManualAdditionSkipReason.duplicateInBatch].
  static ManualAdditionResult apply(
    List<ShoppingLine> current,
    List<ManualListItem> items,
  ) {
    for (final ManualListItem item in items) {
      if (item.name.trim().isEmpty) {
        throw ArgumentError.value(item.name, 'name', 'must not be blank');
      }
      final double? amount = item.quantity?.canonicalAmount;
      if (amount != null && (!amount.isFinite || amount <= 0)) {
        throw ArgumentError.value(
          amount,
          'quantity',
          'must be finite and greater than zero',
        );
      }
    }

    final Set<String> existing = <String>{
      for (final ShoppingLine line in current) ...<String>[
        line.key,
        ShoppingListBuilder.keyFor(name: line.name),
      ],
    };
    final Set<String> addedKeys = <String>{};
    final List<ShoppingLine> lines = <ShoppingLine>[...current];
    final List<ManualListItem> added = <ManualListItem>[];
    final List<ManualAdditionSkip> skipped = <ManualAdditionSkip>[];
    int next = current.isEmpty
        ? -1
        : current
              .map((ShoppingLine line) => line.sortOrder)
              .reduce((int a, int b) => a > b ? a : b);

    for (int index = 0; index < items.length; index++) {
      final ManualListItem item = items[index];
      final String name = item.name.trim();
      final String key = ShoppingListBuilder.keyFor(name: name);
      final ManualAdditionSkipReason? reason = existing.contains(key)
          ? ManualAdditionSkipReason.alreadyOnList
          : addedKeys.contains(key)
          ? ManualAdditionSkipReason.duplicateInBatch
          : null;
      if (reason != null) {
        skipped.add(
          ManualAdditionSkip(index: index, item: item, reason: reason),
        );
        continue;
      }

      final List<Quantity> quantities = <Quantity>[
        if (item.quantity case final Quantity quantity) quantity,
      ];
      lines.add(
        ShoppingContributions.settle(
          ShoppingLine.manual(key: key, name: name, sortOrder: ++next),
          contributions: <ShoppingContribution>[
            ShoppingContribution(
              kind: ShoppingSourceKind.manual,
              quantities: quantities,
              hasUnquantified: item.quantity == null,
            ),
          ],
        ),
      );
      addedKeys.add(key);
      added.add(item);
    }

    return ManualAdditionResult(lines: lines, added: added, skipped: skipped);
  }
}
