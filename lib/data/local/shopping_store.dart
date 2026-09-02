import 'package:drift/drift.dart';

import '../../domain/shopping/shopping_line.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import 'hearth_database.dart';

/// A shopping list as the app holds it: the range, and its lines.
class ShoppingListSnapshot {
  const ShoppingListSnapshot({
    required this.id,
    required this.from,
    required this.to,
    required this.lines,
  });

  final String id;
  final DateTime from;
  final DateTime to;
  final List<ShoppingLine> lines;
}

/// Local reads and writes for the shopping list (spec §5.7).
///
/// Household-scoped, like recipes and collections: the list is a shared
/// artefact even though the plans it is built from are private (§8.2).
class ShoppingStore {
  ShoppingStore(this._db);

  final HearthDatabase _db;

  /// The most recent list for a household, whatever its range.
  ///
  /// "Most recent" rather than "for this range": the range is adjustable, so
  /// asking for an exact match would make every nudge of a date start a new
  /// list and throw away the ticks on the old one.
  Future<ShoppingListSnapshot?> current({required String householdId}) async {
    final ShoppingListRow? row =
        await (_db.select(_db.shoppingLists)
              ..where(
                ($ShoppingListsTable l) => l.householdId.equals(householdId),
              )
              ..orderBy(<OrderClauseGenerator<$ShoppingListsTable>>[
                ($ShoppingListsTable l) => OrderingTerm(
                  expression: l.updatedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;

    return ShoppingListSnapshot(
      id: row.id,
      from: row.fromDate,
      to: row.toDate,
      lines: await linesFor(row.id),
    );
  }

  Stream<void> watchChanges() =>
      _db.select(_db.shoppingListItems).watch().map((_) {});

  Future<List<ShoppingLine>> linesFor(String listId) async {
    final List<ShoppingItemRow> rows =
        await (_db.select(_db.shoppingListItems)
              ..where(($ShoppingListItemsTable i) => i.listId.equals(listId))
              ..orderBy(<OrderClauseGenerator<$ShoppingListItemsTable>>[
                ($ShoppingListItemsTable i) =>
                    OrderingTerm(expression: i.sortOrder),
              ]))
            .get();
    return <ShoppingLine>[for (final ShoppingItemRow row in rows) _toLine(row)];
  }

  /// Replaces a list's lines with [lines], in one transaction.
  ///
  /// Written whole rather than diffed: a list is small, and a partial write
  /// that left the order half-applied would be worse than a rewrite that
  /// cannot.
  Future<String> save({
    required String householdId,
    required String listId,
    required DateTime from,
    required DateTime to,
    required List<ShoppingLine> lines,
    required DateTime updatedAt,
    required String Function() idFactory,
  }) => _db.transaction(() async {
    await _db
        .into(_db.shoppingLists)
        .insertOnConflictUpdate(
          ShoppingListRow(
            id: listId,
            householdId: householdId,
            fromDate: from,
            toDate: to,
            status: 'draft',
            updatedAt: updatedAt,
          ),
        );

    await (_db.delete(
      _db.shoppingListItems,
    )..where(($ShoppingListItemsTable i) => i.listId.equals(listId))).go();

    for (final ShoppingLine line in lines) {
      await _db
          .into(_db.shoppingListItems)
          .insert(_toRow(line, listId, idFactory(), updatedAt));
    }
    return listId;
  });

  ShoppingItemRow _toRow(
    ShoppingLine line,
    String listId,
    String id,
    DateTime updatedAt,
  ) {
    // Only the first planned quantity is stored. A line the recipes could
    // express only two ways at once keeps the first and is marked unmeasurable
    // by having no single amount to show, which is the same thing the screen
    // does with it.
    final Quantity? planned = line.planned.isEmpty ? null : line.planned.first;

    return ShoppingItemRow(
      id: id,
      listId: listId,
      itemKey: line.key,
      foodId: line.foodId,
      name: line.name,
      plannedCanonical: planned?.canonicalAmount,
      plannedKind: planned?.kind.name,
      plannedUnit: planned?.preferredUnit?.id,
      wantedCanonical: line.wanted?.canonicalAmount,
      wantedKind: line.wanted?.kind.name,
      wantedUnit: line.wanted?.preferredUnit?.id,
      onHandCanonical: line.onHand?.canonicalAmount,
      onHandKind: line.onHand?.kind.name,
      onHandUnit: line.onHand?.preferredUnit?.id,
      checked: line.checked,
      isManual: line.isManual,
      hasUnquantified: line.hasUnquantified,
      storeTag: line.storeTag,
      sortOrder: line.sortOrder,
      sourceRecipeIds: line.sourceRecipeIds.join(','),
      updatedAt: updatedAt,
    );
  }

  ShoppingLine _toLine(ShoppingItemRow row) => ShoppingLine(
    key: row.itemKey,
    name: row.name,
    planned: <Quantity>[
      if (_quantity(row.plannedCanonical, row.plannedKind, row.plannedUnit)
          case final Quantity q)
        q,
    ],
    wanted: _quantity(row.wantedCanonical, row.wantedKind, row.wantedUnit),
    onHand: _quantity(row.onHandCanonical, row.onHandKind, row.onHandUnit),
    checked: row.checked,
    foodId: row.foodId,
    storeTag: row.storeTag,
    isManual: row.isManual,
    hasUnquantified: row.hasUnquantified,
    sortOrder: row.sortOrder,
    sourceRecipeIds: row.sourceRecipeIds.isEmpty
        ? const <String>[]
        : row.sourceRecipeIds.split(','),
  );

  static Quantity? _quantity(double? canonical, String? kind, String? unit) {
    if (canonical == null || kind == null) return null;
    final UnitKind? parsed = switch (kind) {
      'volume' => UnitKind.volume,
      'mass' => UnitKind.mass,
      'count' => UnitKind.count,
      _ => null,
    };
    if (parsed == null) return null;
    return Quantity.canonical(
      canonicalAmount: canonical,
      kind: parsed,
      preferredUnit: unit == null ? null : Units.byId(unit),
    );
  }
}
