import 'package:drift/drift.dart';

import '../../domain/models/food.dart';
import '../../domain/text/text_normaliser.dart';
import '../mappers/food_mapper.dart';
import 'hearth_database.dart';

/// Local reads and writes for the food library.
///
/// Like recipes, a food moves as a whole: its serving options are replaced
/// outright on save, because a partially-updated food would report macros for
/// a portion that no longer exists.
class FoodStore {
  FoodStore(this._db);

  final HearthDatabase _db;

  Future<Food?> byId(String id) async {
    final FoodRow? row = await (_db.select(
      _db.foods,
    )..where(($FoodsTable f) => f.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final List<Food> assembled = await _assemble(<FoodRow>[row]);
    return assembled.single;
  }

  /// The household's foods, plus the global catalogue.
  ///
  /// Global foods have a null household and are readable by everyone
  /// (spec §8.2); they arrive from the server and are never written here.
  Future<List<Food>> all({
    required String householdId,
    bool includeDeleted = false,
    bool includeGlobal = true,
  }) async {
    final List<FoodRow> rows =
        await (_db.select(_db.foods)
              ..where(($FoodsTable f) {
                final Expression<bool> mine = f.householdId.equals(householdId);
                final Expression<bool> scope = includeGlobal
                    ? mine | f.householdId.isNull()
                    : mine;
                return includeDeleted
                    ? scope
                    : scope & f.isDeleted.equals(false);
              })
              ..orderBy(<OrderClauseGenerator<$FoodsTable>>[
                ($FoodsTable f) => OrderingTerm.asc(f.name),
              ]))
            .get();
    return _assemble(rows);
  }

  Stream<List<Food>> watchAll({
    required String householdId,
    bool includeDeleted = false,
  }) => _db
      .select(_db.foods)
      .watch()
      .asyncMap(
        (_) => all(householdId: householdId, includeDeleted: includeDeleted),
      );

  /// Foods whose name or brand contains [query], for the food picker.
  ///
  /// Logging speed is the success bar, so this is a plain contains match on a
  /// normalised string rather than anything cleverer — it has to feel instant
  /// on a library of a few thousand.
  Future<List<Food>> search(
    String query, {
    required String householdId,
    int limit = 50,
  }) async {
    final String needle = normaliseKey(query);
    if (needle.isEmpty) {
      final List<Food> everything = await all(householdId: householdId);
      return everything.take(limit).toList(growable: false);
    }

    final List<Food> candidates = await all(householdId: householdId);
    return candidates
        .where(
          (Food food) =>
              normaliseKey(food.name).contains(needle) ||
              normaliseKey(food.brand ?? '').contains(needle),
        )
        .take(limit)
        .toList(growable: false);
  }

  /// Foods that look like duplicates of [food].
  ///
  /// Matched on barcode first, then on an identical normalised name. Spec §5.5
  /// wants a soft warning with a merge option, never a block — two things
  /// genuinely can share a name.
  Future<List<Food>> likelyDuplicatesOf(
    Food food, {
    required String householdId,
  }) async {
    final List<Food> library = await all(householdId: householdId);
    final String name = normaliseKey(food.name);
    final String? barcode = food.barcode;

    return library
        .where((Food other) => other.id != food.id)
        .where(
          (Food other) =>
              (barcode != null &&
                  barcode.isNotEmpty &&
                  other.barcode == barcode) ||
              normaliseKey(other.name) == name,
        )
        .toList(growable: false);
  }

  Future<void> upsert(Food food, {required DateTime updatedAt}) =>
      _db.transaction(() async {
        await _db
            .into(_db.foods)
            .insertOnConflictUpdate(FoodMapper.toCompanion(food, updatedAt));

        await (_db.delete(_db.foodServingOptions)
              ..where(($FoodServingOptionsTable t) => t.foodId.equals(food.id)))
            .go();

        await _db.batch((Batch batch) {
          batch.insertAll(
            _db.foodServingOptions,
            FoodMapper.servingCompanions(food),
          );
        });
      });

  /// Hides a food without removing it, so historical logs keep resolving
  /// (spec §4).
  Future<void> softDelete(String id, {required DateTime updatedAt}) async {
    await (_db.update(
      _db.foods,
    )..where(($FoodsTable f) => f.id.equals(id))).write(
      FoodsCompanion(
        isDeleted: const Value<bool>(true),
        updatedAt: Value<DateTime>(updatedAt),
      ),
    );
  }

  Future<List<Food>> _assemble(List<FoodRow> rows) async {
    if (rows.isEmpty) return const <Food>[];
    final List<String> ids = rows.map((FoodRow r) => r.id).toList();

    final List<FoodServingOptionRow> servings =
        await (_db.select(_db.foodServingOptions)
              ..where(($FoodServingOptionsTable t) => t.foodId.isIn(ids))
              ..orderBy(<OrderClauseGenerator<$FoodServingOptionsTable>>[
                ($FoodServingOptionsTable t) => OrderingTerm.asc(t.sortOrder),
              ]))
            .get();

    return <Food>[
      for (final FoodRow row in rows)
        FoodMapper.toDomain(
          food: row,
          servings: servings
              .where((FoodServingOptionRow s) => s.foodId == row.id)
              .toList(growable: false),
        ),
    ];
  }
}
