import 'dart:convert';

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
        'updated_at': list.updatedAt.toIso8601String(),
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
        'updated_at': item.updatedAt.toIso8601String(),
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

  /// The trailing planned amounts as a list for the jsonb column, never as a
  /// string holding JSON.
  static List<Object?> plannedRestToJson(String raw) {
    final Object? decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
    return decoded is List<Object?> ? decoded : const <Object?>[];
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
