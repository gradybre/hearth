import 'package:uuid/uuid.dart';

import '../../domain/foods/no_match_rule.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/shopping/shopping_list_builder.dart';
import '../../domain/shopping/shopping_list_merge.dart';
import '../local/hearth_database.dart';
import '../local/pending_write_store.dart';
import '../local/shopping_store.dart';
import '../mappers/shopping_mapper.dart';

/// The shopping list, built from the plan and then owned by the shopper
/// (spec §5.7).
///
/// Everything that decides *what* is on the list lives in
/// [ShoppingListBuilder] and [ShoppingListMerge], which are pure and tested.
/// This is the part that knows where the plan and the library come from, and
/// when to write.
class ShoppingRepository {
  ShoppingRepository({
    required HearthDatabase database,
    required ShoppingStore store,
    required PendingWriteStore queue,
    required String householdId,
    DateTime Function()? now,
    String Function()? idFactory,
  }) : _db = database,
       _store = store,
       _queue = queue,
       _householdId = householdId,
       _now = now ?? DateTime.now,
       _idFactory = idFactory ?? (() => const Uuid().v4());

  static const String listsTable = 'shopping_lists';
  static const String itemsTable = 'shopping_list_items';

  final HearthDatabase _db;
  final ShoppingStore _store;
  final PendingWriteStore _queue;
  final String _householdId;
  final DateTime Function() _now;
  final String Function() _idFactory;

  /// The id of a line, derived from the list and the line's own key.
  ///
  /// Derived rather than invented, and this is load-bearing for sync. Saving
  /// rewrites every line, so a fresh uuid each time would mint a new server
  /// row on every tick and leave the old one standing on the partner's phone.
  /// The same line in the same list is the same row, on both devices, forever.
  /// Same reasoning as [PlanRepository.dayIdFor].
  static String itemIdFor({required String listId, required String itemKey}) =>
      const Uuid().v5(
        Namespace.url.value,
        'hearth:shopping-item:$listId:$itemKey',
      );

  /// How long a list covers when nobody has said otherwise.
  ///
  /// Seven days from today, which from a Friday is the weekend and the week
  /// after — the shape of a real shop rather than of a calendar week.
  static const int defaultDays = 7;

  Future<ShoppingListSnapshot?> current() =>
      _store.current(householdId: _householdId);

  Stream<void> watchChanges() => _store.watchChanges();

  /// The range a list opens on before anyone adjusts it.
  ({DateTime from, DateTime to}) defaultRange() {
    final DateTime from = dayKey(_now());
    return (from: from, to: addDays(from, defaultDays - 1));
  }

  /// Builds the list for a range and merges it over whatever is already there.
  ///
  /// Merging rather than replacing is what makes Rebuild a button you press
  /// freely: ticks, on-hand amounts, edited quantities, the order and manual
  /// items all survive (see [ShoppingListMerge]).
  Future<List<ShoppingLine>> rebuild({
    required DateTime from,
    required DateTime to,
    required Map<DateTime, List<MealPlanEntry>> entriesByDay,
    required Map<String, Recipe> recipes,
    required Map<String, Food> foods,
    NoMatchRules seasonings = NoMatchRules.none,
    bool includeSeasonings = false,
  }) async {
    final ShoppingListSnapshot? existing = await current();

    final List<ShoppingLine> fresh = ShoppingListBuilder.forRange(
      from: from,
      to: to,
      entriesByDay: entriesByDay,
      recipes: recipes,
      foods: foods,
      seasonings: seasonings,
      includeSeasonings: includeSeasonings,
    );

    // A first list inherits the order of the last one that existed, so an
    // arrangement made once is not made again every week.
    final List<ShoppingLine> ordered = ShoppingListMerge.ordered(
      fresh,
      existing?.lines ?? const <ShoppingLine>[],
    );

    final List<ShoppingLine> merged = existing == null
        ? ordered
        : ShoppingListMerge.into(existing.lines, ordered);

    return _write(
      listId: existing?.id ?? _idFactory(),
      from: from,
      to: to,
      lines: merged,
    );
  }

  /// Writes the list back after an edit on the screen.
  Future<List<ShoppingLine>> replace(List<ShoppingLine> lines) async {
    final ShoppingListSnapshot? existing = await current();
    final ({DateTime from, DateTime to}) range = existing == null
        ? defaultRange()
        : (from: existing.from, to: existing.to);

    return _write(
      listId: existing?.id ?? _idFactory(),
      from: range.from,
      to: range.to,
      lines: lines,
    );
  }

  /// Puts one removed line back, on the list as it stands *now* (spec §5.7).
  ///
  /// Undo is one line coming back, never the list as it was. The screen used
  /// to hand back the whole snapshot it had captured before the deletion,
  /// which meant everything done in between went with it: a line ticked in
  /// the next aisle came un-ticked, an item added by hand disappeared, and a
  /// change that had arrived from the other phone was quietly overwritten.
  /// Every one of those is somebody's more recent decision, and undoing a
  /// deletion was never a claim about any of them.
  ///
  /// Position survives because [ShoppingLine.sortOrder] is what the display
  /// order is made of — the line goes back where it was walked to, not to the
  /// bottom of the shop. The order the line is appended in therefore does not
  /// matter, which is worth knowing before somebody "fixes" it.
  ///
  /// One case is deliberately left alone: a rebuild between the deletion and
  /// the Undo. If the plan no longer calls for that line the rebuild drops
  /// it, and this puts it back — arguably against the rebuild, arguably
  /// exactly what the person pressing Undo asked for. It is left as the
  /// second of those because Undo is a direct instruction and a rebuild is
  /// not, and because the next rebuild settles it either way.
  Future<List<ShoppingLine>> restoreLine(ShoppingLine line) async {
    final List<ShoppingLine> now =
        (await current())?.lines ?? const <ShoppingLine>[];

    // The same key is the same item, so a line already standing there is this
    // one, back by another route — Undo tapped twice, the item re-added by
    // hand, or a rebuild that asked for it again. It wins and nothing is
    // written: it is the newer decision, and a second copy would have to be
    // deleted by hand in the shop.
    if (now.any((ShoppingLine other) => other.key == line.key)) {
      return ShoppingListMerge.display(now);
    }

    return replace(<ShoppingLine>[...now, line]);
  }

  Future<List<ShoppingLine>> _write({
    required String listId,
    required DateTime from,
    required DateTime to,
    required List<ShoppingLine> lines,
  }) async {
    final List<ShoppingLine> ordered = ShoppingListMerge.display(lines);
    final DateTime now = _now();

    // One transaction, so a list that reaches the screen has already reached
    // the queue — the rule every other repository follows.
    await _db.transaction(() async {
      final List<String> removed = await _store.save(
        householdId: _householdId,
        listId: listId,
        from: from,
        to: to,
        lines: ordered,
        updatedAt: now,
        idFor: (String key) => itemIdFor(listId: listId, itemKey: key),
      );

      await _queue.enqueue(
        entityTable: listsTable,
        entityId: listId,
        operation: WriteOperation.upsert,
        payload: ShoppingMapper.listToJson(
          ShoppingListRow(
            id: listId,
            householdId: _householdId,
            fromDate: from,
            toDate: to,
            status: 'draft',
            updatedAt: now,
          ),
        ),
        queuedAt: now,
      );

      for (final ShoppingItemRow row in await _store.rowsFor(listId)) {
        await _queue.enqueue(
          entityTable: itemsTable,
          entityId: row.id,
          operation: WriteOperation.upsert,
          payload: ShoppingMapper.itemToJson(row),
          queuedAt: now,
        );
      }

      // A line that went away is a real row removal, not a soft delete: an
      // item carries no history worth keeping, unlike a recipe or a food.
      for (final String id in removed) {
        await _queue.enqueue(
          entityTable: itemsTable,
          entityId: id,
          operation: WriteOperation.delete,
          payload: <String, Object?>{
            'id': id,
            // Stated, not left to the server: the tombstone records the deleting
            // writer's own clock, so an Undo from this same device is always
            // newer than the deletion it undoes (spec §7.1).
            'updated_at': now.toUtc().toIso8601String(),
          },
          queuedAt: now,
        );
      }
    });

    return ordered;
  }
}
