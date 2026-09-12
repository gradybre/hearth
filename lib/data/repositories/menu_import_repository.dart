import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/foods/menu_provenance.dart';
import '../../domain/text/text_normaliser.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';

/// Where each restaurant's menu came from (review N08).
///
/// One row per restaurant: the question this answers is "whose numbers are
/// these and how old are they", which the latest import settles. A history of
/// every attempt would answer a question nobody has asked.
class MenuImportRepository {
  MenuImportRepository({
    required HearthDatabase database,
    required PendingWriteStore queue,
    required String householdId,
    DateTime Function()? clock,
  }) : _db = database,
       _queue = queue,
       _householdId = householdId,
       _now = clock ?? DateTime.now;

  static const String entityTable = 'menu_imports';

  final HearthDatabase _db;
  final PendingWriteStore _queue;
  final String _householdId;
  final DateTime Function() _now;

  /// A stable id for one household's record of one restaurant.
  ///
  /// Derived rather than random, for the reason the menu foods' ids are: two
  /// imports of the same menu are one fact about one restaurant, and a fresh
  /// uuid each time would make a second row the unique key then refuses.
  static String idFor({
    required String householdId,
    required String restaurant,
  }) => const Uuid().v5(
    Namespace.url.value,
    'hearth:menu-import:$householdId:${normaliseKey(restaurant)}',
  );

  Stream<List<MenuProvenance>> watchAll() =>
      (_db.select(
            _db.menuImports,
          )..where(($MenuImportsTable t) => t.householdId.equals(_householdId)))
          .watch()
          .map(
            (List<MenuImportRow> rows) => <MenuProvenance>[
              for (final MenuImportRow row in rows) _toDomain(row),
            ],
          );

  Future<MenuProvenance?> forRestaurant(String restaurant) async {
    final MenuImportRow? row =
        await (_db.select(_db.menuImports)..where(
              ($MenuImportsTable t) =>
                  t.householdId.equals(_householdId) &
                  t.restaurantKey.equals(normaliseKey(restaurant)),
            ))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// Records that this household read [restaurant]'s menu just now.
  Future<void> record({
    required String restaurant,
    required int itemCount,
    String? source,
    DateTime? documentDate,
  }) async {
    final DateTime now = _now();
    final String id = idFor(householdId: _householdId, restaurant: restaurant);

    await _db.transaction(() async {
      await _db
          .into(_db.menuImports)
          .insertOnConflictUpdate(
            MenuImportRow(
              id: id,
              householdId: _householdId,
              restaurantKey: normaliseKey(restaurant),
              restaurant: restaurant,
              source: source,
              documentDate: documentDate,
              itemCount: itemCount,
              importedAt: now,
              updatedAt: now,
            ),
          );
      await _queue.enqueue(
        entityTable: entityTable,
        entityId: id,
        operation: WriteOperation.upsert,
        payload: <String, Object?>{
          'id': id,
          'household_id': _householdId,
          'restaurant_key': normaliseKey(restaurant),
          'restaurant': restaurant,
          'source': source,
          // A date, not a moment: what is printed on a nutrition sheet is a
          // day, and sending a timestamp would invent a time it never had.
          'document_date': documentDate == null
              ? null
              : '${documentDate.year.toString().padLeft(4, '0')}-'
                    '${documentDate.month.toString().padLeft(2, '0')}-'
                    '${documentDate.day.toString().padLeft(2, '0')}',
          'item_count': itemCount,
          'imported_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        },
        queuedAt: now,
      );
    });
  }

  static MenuProvenance _toDomain(MenuImportRow row) => MenuProvenance(
    restaurant: row.restaurant,
    source: row.source,
    documentDate: row.documentDate,
    itemCount: row.itemCount,
    importedAt: row.importedAt,
  );
}
