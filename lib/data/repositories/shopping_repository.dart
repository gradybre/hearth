import 'package:uuid/uuid.dart';

import '../../domain/foods/no_match_rule.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/planning/week.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/shopping/shopping_list_builder.dart';
import '../../domain/shopping/shopping_list_merge.dart';
import '../local/shopping_store.dart';

/// The shopping list, built from the plan and then owned by the shopper
/// (spec §5.7).
///
/// Everything that decides *what* is on the list lives in
/// [ShoppingListBuilder] and [ShoppingListMerge], which are pure and tested.
/// This is the part that knows where the plan and the library come from, and
/// when to write.
class ShoppingRepository {
  ShoppingRepository({
    required ShoppingStore store,
    required String householdId,
    DateTime Function()? now,
    String Function()? idFactory,
  }) : _store = store,
       _householdId = householdId,
       _now = now ?? DateTime.now,
       _idFactory = idFactory ?? (() => const Uuid().v4());

  final ShoppingStore _store;
  final String _householdId;
  final DateTime Function() _now;
  final String Function() _idFactory;

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
    return (from: from, to: from.add(const Duration(days: defaultDays - 1)));
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

  Future<List<ShoppingLine>> _write({
    required String listId,
    required DateTime from,
    required DateTime to,
    required List<ShoppingLine> lines,
  }) async {
    final List<ShoppingLine> ordered = ShoppingListMerge.display(lines);
    await _store.save(
      householdId: _householdId,
      listId: listId,
      from: from,
      to: to,
      lines: ordered,
      updatedAt: _now(),
      idFactory: _idFactory,
    );
    return ordered;
  }
}
