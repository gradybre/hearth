import 'package:meta/meta.dart';

import '../foods/no_match_rule.dart';
import '../models/food.dart';
import '../models/recipe.dart';
import '../planning/meal_plan.dart';
import '../recipes/ingredient_consolidator.dart';
import '../text/text_normaliser.dart';
import '../units/density.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import '../units/unit_converter.dart';
import 'shopping_contribution.dart';
import 'shopping_line.dart';

/// Turning a stretch of the plan into a shopping list (spec §5.7).
///
/// The aggregation itself is [IngredientConsolidator]'s, which has done both
/// stages — sections flattened per recipe, then duplicates merged across the
/// week — since long before anything called it. What this adds is everything
/// about *which* of the plan counts:
///
///  * a **date range** rather than a week, because shopping on a Friday covers
///    the weekend and the week after and never lines up with a calendar week;
///  * **not what has already been logged**, because something eaten was
///    already bought — the case of a recipe you cooked on Tuesday and are
///    still eating on Thursday, which would otherwise send you for it twice;
///  * **foods planned on their own**, which the consolidator cannot see
///    because it only knows recipes;
///  * **not seasonings**, by default.
abstract final class ShoppingListBuilder {
  /// The lines a range of the plan calls for, unordered.
  ///
  /// [entriesByDay] is what `PlanRepository.entriesBetween` returns. [from]
  /// and [to] are inclusive day keys, and are applied here rather than trusted
  /// from the query so the rule lives with the rest of the decisions.
  static List<ShoppingLine> forRange({
    required DateTime from,
    required DateTime to,
    required Map<DateTime, List<MealPlanEntry>> entriesByDay,
    required Map<String, Recipe> recipes,
    required Map<String, Food> foods,
    NoMatchRules seasonings = NoMatchRules.none,
    bool includeSeasonings = false,
  }) {
    final List<MealPlanEntry> wanted = <MealPlanEntry>[
      for (final MapEntry<DateTime, List<MealPlanEntry>> day
          in entriesByDay.entries)
        if (!day.key.isBefore(from) && !day.key.isAfter(to))
          for (final MealPlanEntry entry in day.value)
            // Already eaten is already bought.
            if (!entry.isLogged) entry,
    ];

    final List<ShoppingLine> lines = <ShoppingLine>[
      ..._fromRecipes(wanted, recipes, foods),
      ..._fromFoods(wanted, foods),
    ];

    if (includeSeasonings) return lines;
    return <ShoppingLine>[
      for (final ShoppingLine line in lines)
        if (!seasonings.covers(line.name)) line,
    ];
  }

  /// Everything the planned recipes need, aggregated.
  ///
  /// A recipe planned twice contributes twice, and one planned at half its
  /// yield contributes half — which is what `servingsFor` is for, and why the
  /// servings are summed across entries before being handed over.
  ///
  /// [foods] is here for one reason: a line's shop comes from the food behind
  /// it, and until this took the library the recipe path had no way to read
  /// one. Every ingredient matched to a tagged food still landed under
  /// "Anywhere", which is nearly every line on any real list — so the store
  /// grouping the screen is built around had almost nothing to group.
  static List<ShoppingLine> _fromRecipes(
    List<MealPlanEntry> entries,
    Map<String, Recipe> recipes,
    Map<String, Food> foods,
  ) {
    final Map<String, double> servings = <String, double>{};
    for (final MealPlanEntry entry in entries) {
      if (entry.refType != PlanRefType.recipe) continue;
      final Recipe? recipe = recipes[entry.refId];
      if (recipe == null) continue;
      // Nobody shops for a burrito bowl. A restaurant meal is a recipe so
      // that it can be planned, logged and repeated like anything else — but
      // its ingredients live in somebody else's kitchen, and putting "4 oz
      // chicken" on the list because Chipotle is planned for Thursday would
      // send you to the shop for a meal you are not cooking (spec §5.2, §5.7).
      if (recipe.isEatenOut) continue;
      servings[entry.refId] = (servings[entry.refId] ?? 0) + entry.servings;
    }
    if (servings.isEmpty) return const <ShoppingLine>[];

    final List<ConsolidatedIngredient> merged =
        IngredientConsolidator.mergeRecipes(
          <Recipe>[
            for (final String id in servings.keys)
              if (recipes[id] case final Recipe recipe) recipe,
          ],
          servingsFor: servings,
          // Matched food by matched food, so a line's density is its own.
          foods: foods,
          // Source mode: what a recipe asked for is recorded in the measure
          // it was written in. The pack-counted total is derived from those
          // asks by [ShoppingContributions.settle] below — so a package
          // relationship added, changed or removed later recomputes the
          // line rather than leaving a converted number nothing can undo
          // (spec R5, R7, R12).
          sourceMode: true,
        );

    return <ShoppingLine>[
      for (final ConsolidatedIngredient line in merged)
        _planLine(
          ShoppingLine(
            key: line.key,
            name: line.displayName,
            planned: line.quantities,
            foodId: line.foodId,
            storeTag: foods[line.foodId]?.storeTag,
            hasUnquantified: line.hasUnquantified,
            sourceRecipeIds: line.sourceRecipeIds,
          ),
          foods[line.foodId],
        ),
    ];
  }

  /// Foods planned on their own rather than through a recipe.
  ///
  /// A yoghurt planned for Tuesday is still shopping. The consolidator never
  /// sees these because it walks recipes, so they are counted here and keyed
  /// by food id — the same key a recipe line matched to that food would use,
  /// so the two merge rather than sitting on the list twice.
  static List<ShoppingLine> _fromFoods(
    List<MealPlanEntry> entries,
    Map<String, Food> foods,
  ) {
    // Grouped by the serving each entry counts, never by food alone. Two
    // portions counted in 1 cup and two counted in 100 g are not four of
    // anything, and adding them before either is converted invents an amount
    // nobody planned (spec R12).
    final Map<String, Map<String?, double>> servings =
        <String, Map<String?, double>>{};
    // Foods with at least one portion nothing can measure, because the row
    // it counted has been removed. The line still belongs on the list — the
    // plan surface reports that entry as uncostable, and a shopping list
    // that silently dropped the food instead would understate the shop with
    // no signal at all (review F2).
    final Set<String> unmeasurable = <String>{};
    for (final MealPlanEntry entry in entries) {
      if (entry.refType != PlanRefType.food) continue;
      final Food? food = foods[entry.refId];
      if (food == null) continue;
      // A named row that no longer exists is not quietly re-read as the
      // food's first one: there is nothing to convert, so nothing is added
      // — but the food is still wanted, and says so.
      if (entry.servingOptionId != null &&
          _servingById(food, entry.servingOptionId) == null) {
        unmeasurable.add(entry.refId);
        servings.putIfAbsent(entry.refId, () => <String?, double>{});
        continue;
      }
      final Map<String?, double> byServing = servings.putIfAbsent(
        entry.refId,
        () => <String?, double>{},
      );
      byServing[entry.servingOptionId] =
          (byServing[entry.servingOptionId] ?? 0) + entry.servings;
    }

    return <ShoppingLine>[
      for (final MapEntry<String, Map<String?, double>> planned
          in servings.entries)
        if (foods[planned.key] case final Food food)
          _planLine(
            ShoppingLine(
              key: food.id,
              name: food.name,
              // One quantity per serving counted, converted before anything
              // is summed — the consolidation that follows knows how to add
              // measured amounts, which counts of unlike servings are not.
              planned: <Quantity>[
                for (final MapEntry<String?, double> counted
                    in planned.value.entries)
                  portionsOf(
                    food,
                    counted.value,
                    serving: _servingById(food, counted.key),
                  ),
              ],
              foodId: food.id,
              storeTag: food.storeTag,
              // The same signal `_fromRecipes` already carries for an
              // ingredient nothing could measure. No count is invented for
              // the portion that produced it.
              hasUnquantified: unmeasurable.contains(food.id),
            ),
            food,
          ),
    ];
  }

  /// The same line, with what it holds recorded as the plan's ask.
  ///
  /// Everything this class produces is the plan's, by definition — so the
  /// whole of the line is one [ShoppingSourceKind.plan] contribution, and
  /// [ShoppingListMerge.into] can replace exactly that much of a line the
  /// next time somebody rebuilds (spec §5.7).
  static ShoppingLine _planLine(ShoppingLine line, Food? food) =>
      ShoppingContributions.settle(
        line,
        contributions: <ShoppingContribution>[
          ShoppingContribution(
            kind: ShoppingSourceKind.plan,
            quantities: line.planned,
            hasUnquantified: line.hasUnquantified,
          ),
        ],
        // Settled rather than assigned, so the total on the line is the one
        // the matched food produces — the same arithmetic every later
        // rebuild redoes from the same asks (spec R5).
        food: food,
      );

  /// How much of a food a number of its servings comes to.
  ///
  /// In the food's own serving unit where it has one — three 170 g pots is
  /// 510 g — and as a bare count of servings where it does not, which is
  /// still more use at the shop than nothing.
  ///
  /// Public because adding a food straight to the list asks the same question
  /// and must get the same answer — a second implementation would be a second
  /// opinion about what three yoghurts comes to.
  static Quantity portionsOf(
    Food food,
    double servings, {
    // The row the count is in, when the entry named one (spec R12). The
    // food's first when it did not, which is what a bare count means.
    ServingOption? serving,
  }) {
    final ServingOption? option = serving ?? food.defaultServing;
    if (option == null) return Quantity.of(servings, Units.item);
    return option.amount.scaledBy(servings);
  }

  /// One of [food]'s servings by id, or null — including for a null id and
  /// for a row that has since been removed.
  static ServingOption? _servingById(Food food, String? id) {
    if (id == null) return null;
    for (final ServingOption option in food.servingOptions) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// The key a line is recognised by across rebuilds.
  ///
  /// A food id where there is one, the normalised name otherwise — matching
  /// `IngredientConsolidator`, so a line keeps its tick, its order and its
  /// on-hand amount by being the same thing rather than by being in the same
  /// place.
  static String keyFor({String? foodId, required String name}) =>
      foodId ?? normaliseKey(name);
}

/// A shopping line as a screen or an export should read it (spec R5, R7).
///
/// Derived, never stored. [ShoppingLine] keeps what the recipes and the
/// shopper actually said; this answers the separate question of what those
/// amounts come to *for the food the line is matched to* — a cupboard amount
/// measured in cups against a need measured in ounces, and the pack size to
/// count against. Every surface asks through here, so the list, the amount
/// sheet and the export cannot arrive at three different answers.
@immutable
class ResolvedShoppingLine {
  const ResolvedShoppingLine({required this.line, this.pack, this.food});

  /// The line to read from: the original, or a copy whose on-hand amount is
  /// expressed in the need's own kind. Never written back.
  final ShoppingLine line;

  /// How much comes in one of whatever this is sold as, when that is known.
  final Quantity? pack;

  final Food? food;

  Quantity? get toBuy => line.toBuy;
  Quantity? get onHand => line.onHand;
  List<Quantity> get planned => line.planned;
  bool get isChecked => line.isChecked;
}

/// Resolving a line against the food behind it.
abstract final class ShoppingLineResolver {
  /// [line] with a cross-kind on-hand amount converted into the need's kind.
  ///
  /// A cup of something already in the cupboard has to come off a need
  /// measured in ounces, and until the two are in one kind
  /// [ShoppingLine.toBuy] cannot subtract it at all — it ignores an on-hand
  /// amount of a different kind, which quietly sends you for the whole
  /// thing. The food's own density is what makes the subtraction legal
  /// (spec R12); without one, nothing is converted and the line reads as it
  /// always did.
  static ResolvedShoppingLine resolve({
    required ShoppingLine line,
    Food? food,
  }) {
    final Quantity? pack = food?.packSize;
    final ShoppingLine settled = _settled(line, food);
    final Quantity? need = settled.fullAmount;
    final Quantity? onHand = settled.onHand;
    if (need == null || onHand == null || onHand.kind == need.kind) {
      return ResolvedShoppingLine(line: settled, pack: pack, food: food);
    }

    final double? density =
        food?.effectiveGramsPerMillilitre ?? DensityTable.lookup(settled.name);
    if (density == null) {
      return ResolvedShoppingLine(line: settled, pack: pack, food: food);
    }

    final ConversionResult converted = UnitConverter.crossKind(
      onHand,
      need.kind,
      gramsPerMillilitre: density,
    );
    if (!converted.isExact) {
      return ResolvedShoppingLine(line: settled, pack: pack, food: food);
    }
    return ResolvedShoppingLine(
      line: settled.copyWith(
        onHand: converted.quantity.withPreferredUnit(need.preferredUnit),
      ),
      pack: pack,
      food: food,
    );
  }

  /// [line] with its total recomputed from its own asks, against the food it
  /// is matched to *now* (spec R5).
  ///
  /// Derived for reading, never written back. A stored total was derived
  /// against whatever the food said at the time it was written, so a package
  /// relationship added, changed or removed since has to be able to change
  /// what the line reads without anybody re-adding the recipe — and a total
  /// that stayed in ounces after the relationship went would be evidence of
  /// a conversion that is no longer true.
  ///
  /// A row written before contributions existed has only its stored total to
  /// go on. That is read as its authored ask, which is as far back as the
  /// evidence goes; no lost unit is invented for it.
  ///
  /// What somebody decided is untouched throughout: an edited amount and an
  /// on-hand amount are stored facts, and only the derived view of them is
  /// converted — the same value the export reads, through the same call.
  static ShoppingLine _settled(ShoppingLine line, Food? food) {
    // An old unmatched row already records the app's earlier decision to
    // keep amounts separate. No new food evidence justifies changing it.
    if (line.contributions.isEmpty && food == null) return line;
    final List<ShoppingContribution> asks = line.contributions.isEmpty
        ? ShoppingContributions.legacy(line)
        : line.contributions;
    if (asks.isEmpty) return line;
    return ShoppingContributions.settle(line, contributions: asks, food: food);
  }
}
