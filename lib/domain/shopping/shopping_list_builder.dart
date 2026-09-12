import '../foods/no_match_rule.dart';
import '../models/food.dart';
import '../models/recipe.dart';
import '../planning/meal_plan.dart';
import '../recipes/ingredient_consolidator.dart';
import '../text/text_normaliser.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
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
        IngredientConsolidator.mergeRecipes(<Recipe>[
          for (final String id in servings.keys)
            if (recipes[id] case final Recipe recipe) recipe,
        ], servingsFor: servings);

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
    final Map<String, double> servings = <String, double>{};
    for (final MealPlanEntry entry in entries) {
      if (entry.refType != PlanRefType.food) continue;
      if (!foods.containsKey(entry.refId)) continue;
      servings[entry.refId] = (servings[entry.refId] ?? 0) + entry.servings;
    }

    return <ShoppingLine>[
      for (final MapEntry<String, double> planned in servings.entries)
        if (foods[planned.key] case final Food food)
          _planLine(
            ShoppingLine(
              key: food.id,
              name: food.name,
              planned: <Quantity>[portionsOf(food, planned.value)],
              foodId: food.id,
              storeTag: food.storeTag,
            ),
          ),
    ];
  }

  /// The same line, with what it holds recorded as the plan's ask.
  ///
  /// Everything this class produces is the plan's, by definition — so the
  /// whole of the line is one [ShoppingSourceKind.plan] contribution, and
  /// [ShoppingListMerge.into] can replace exactly that much of a line the
  /// next time somebody rebuilds (spec §5.7).
  static ShoppingLine _planLine(ShoppingLine line) => line.copyWith(
    contributions: <ShoppingContribution>[
      ShoppingContribution(
        kind: ShoppingSourceKind.plan,
        quantities: line.planned,
        hasUnquantified: line.hasUnquantified,
      ),
    ],
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
  static Quantity portionsOf(Food food, double servings) {
    final ServingOption? option = food.defaultServing;
    if (option == null) return Quantity.of(servings, Units.item);
    return option.amount.scaledBy(servings);
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
