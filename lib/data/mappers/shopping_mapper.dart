import 'dart:convert';

import '../../domain/shopping/shopping_contribution.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import '../local/hearth_database.dart';

/// The shopping list on the wire (spec §5.7, §7.2).
///
/// A mapper of its own rather than a reuse of an existing one, because three
/// names genuinely differ between the two sides: the local `listId` is
/// `shopping_list_id`, the local `name` is `raw_name`, and `sourceRecipeIds`
/// is a joined string locally against a `uuid[]` on the server.
abstract final class ShoppingMapper {
  static Map<String, Object?> listToJson(ShoppingListRow list) =>
      <String, Object?>{
        'id': list.id,
        'household_id': list.householdId,
        'from_date': _dateOnly(list.fromDate),
        'to_date': _dateOnly(list.toDate),
        'status': list.status,
        'updated_at': list.updatedAt.toUtc().toIso8601String(),
      };

  static Map<String, Object?> itemToJson(ShoppingItemRow item) =>
      <String, Object?>{
        'id': item.id,
        'shopping_list_id': item.listId,
        'item_key': item.itemKey,
        'food_id': item.foodId,
        'raw_name': item.name,
        'planned_canonical': item.plannedCanonical,
        'planned_kind': item.plannedKind,
        'planned_unit': item.plannedUnit,
        'wanted_canonical': item.wantedCanonical,
        'wanted_kind': item.wantedKind,
        'wanted_unit': item.wantedUnit,
        'on_hand_canonical': item.onHandCanonical,
        'on_hand_kind': item.onHandKind,
        'on_hand_unit': item.onHandUnit,
        'checked': item.checked,
        'is_manual': item.isManual,
        'has_unquantified': item.hasUnquantified,
        'store_tag': item.storeTag,
        'sort_order': item.sortOrder,
        'source_recipe_ids': sourceIdsToList(item.sourceRecipeIds),
        'planned_rest': plannedRestToJson(item.plannedRest),
        'contributions': jsonListFrom(item.contributions),
        // A line taken off the list and put back — Undo, or the same name
        // added again — has to come back rather than stay a tombstone
        // (spec §7.1).
        'is_deleted': false,
        'updated_at': item.updatedAt.toUtc().toIso8601String(),
      };

  /// The joined local string as the `uuid[]` the server column expects.
  ///
  /// Empty entries are dropped rather than sent: Postgres rejects `''` as a
  /// uuid, so one stray separator would fail the whole write.
  static List<String> sourceIdsToList(String joined) => <String>[
    for (final String id in joined.split(','))
      if (id.trim().isNotEmpty) id.trim(),
  ];

  /// And back again, tolerant of either shape.
  ///
  /// The server sends a list; an older row or a hand-written fixture might
  /// send the joined string. Reading both costs a line and saves a class of
  /// pull failure that would look like an empty list rather than an error.
  static String sourceIdsFromJson(Object? value) => switch (value) {
    final List<Object?> list => <String>[
      for (final Object? id in list)
        if ('${id ?? ''}'.trim().isNotEmpty) '$id'.trim(),
    ].join(','),
    final String joined => sourceIdsToList(joined).join(','),
    _ => '',
  };

  /// The trailing planned amounts as a list for the jsonb column.
  static List<Object?> plannedRestToJson(String raw) => jsonListFrom(raw);

  /// The trailing planned amounts, or the contributions, as a list for a
  /// jsonb column — never as a string holding JSON.
  static List<Object?> jsonListFrom(String raw) {
    final Object? decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
    return decoded is List<Object?> ? decoded : const <Object?>[];
  }

  /// What each source asked for, as the jsonb column holds it (spec §5.7).
  ///
  /// A shape of its own rather than the line's own fields, because it has to
  /// survive a round trip through Postgres and back into a phone running an
  /// older build — which reads the column it does not know about as nothing,
  /// and falls back to treating the total as the plan's. That is the right
  /// answer for that build, and this one is the right answer for this.
  static List<Object?> contributionsToJson(
    List<ShoppingContribution> contributions,
  ) => <Object?>[
    for (final ShoppingContribution c in contributions)
      <String, Object?>{
        'kind': c.kind.name,
        if (c.refId != null) 'ref_id': c.refId,
        if (c.label != null) 'label': c.label,
        if (c.servings != null) 'servings': c.servings,
        if (c.hasUnquantified) 'has_unquantified': true,
        'quantities': <Object?>[
          for (final Quantity q in c.quantities) quantityToJson(q),
        ],
      },
  ];

  /// And back, tolerant of anything it does not recognise.
  ///
  /// An unreadable entry is dropped rather than throwing: a line with one
  /// contribution missing is wrong by that much, and a list that will not
  /// load at all is wrong by the whole list. A `kind` this build has never
  /// heard of is exactly that case — a newer build wrote it.
  static List<ShoppingContribution> contributionsFromJson(Object? value) {
    final Object? decoded = switch (value) {
      final String raw => raw.trim().isEmpty ? null : jsonDecode(raw),
      final List<Object?> list => list,
      _ => null,
    };
    if (decoded is! List<Object?>) return const <ShoppingContribution>[];

    return <ShoppingContribution>[
      for (final Object? entry in decoded)
        if (entry is Map<String, Object?>)
          if (_kind(entry['kind']) case final ShoppingSourceKind kind)
            ShoppingContribution(
              kind: kind,
              refId: entry['ref_id'] as String?,
              label: entry['label'] as String?,
              servings: switch (entry['servings']) {
                final num n => n.toDouble(),
                _ => null,
              },
              hasUnquantified: entry['has_unquantified'] == true,
              quantities: <Quantity>[
                if (entry['quantities'] case final List<Object?> list)
                  for (final Object? q in list)
                    if (quantityFromJson(q) case final Quantity parsed) parsed,
              ],
            ),
    ];
  }

  static ShoppingSourceKind? _kind(Object? value) {
    for (final ShoppingSourceKind kind in ShoppingSourceKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }

  static Map<String, Object?> quantityToJson(Quantity quantity) =>
      <String, Object?>{
        'canonical': quantity.canonicalAmount,
        'kind': quantity.kind.name,
        'unit': quantity.preferredUnit?.id,
      };

  static Quantity? quantityFromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final double? canonical = switch (value['canonical']) {
      final num n => n.toDouble(),
      _ => null,
    };
    final UnitKind? kind = switch (value['kind']) {
      'volume' => UnitKind.volume,
      'mass' => UnitKind.mass,
      'count' => UnitKind.count,
      _ => null,
    };
    if (canonical == null || kind == null) return null;
    final Object? unit = value['unit'];
    return Quantity.canonical(
      canonicalAmount: canonical,
      kind: kind,
      preferredUnit: unit is String ? Units.byId(unit) : null,
    );
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
