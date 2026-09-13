import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/text/text_normaliser.dart';

/// What somebody asked to put on the shopping list (spec §5.7).
@immutable
sealed class ListAddition {
  const ListAddition();
}

/// A recipe, expanded into its ingredients at [servings].
final class RecipeAddition extends ListAddition {
  const RecipeAddition({required this.recipe, required this.servings});

  final Recipe recipe;
  final double servings;
}

/// A food on its own, in its own serving unit.
final class FoodAddition extends ListAddition {
  const FoodAddition({required this.food, required this.servings});

  final Food food;
  final double servings;
}

/// Something the library has never heard of — coffee, paper towels.
final class PlainAddition extends ListAddition {
  const PlainAddition(this.name);

  final String name;
}

/// Putting something on the shopping list.
///
/// The primary way a list gets filled since spec §5.7 was amended: you open
/// the list and add to it, rather than generating it from a week of the plan
/// and then correcting what comes out.
///
/// One sheet for all three kinds of thing, because from the shopper's side
/// they are one act — "I need the stuff for chilli", "I need yoghurt", "I need
/// coffee" — and splitting them across a search sheet and a name dialog made
/// the app's data model the user's problem.
Future<ListAddition?> showAddToListSheet(
  BuildContext context, {
  required List<Recipe> recipes,
  required List<Food> foods,
}) => showModalBottomSheet<ListAddition>(
  context: context,
  backgroundColor: context.colors.background,
  isScrollControlled: true,
  // Capped like every other sheet here, so a tall one at large text scrolls
  // rather than overflowing, and tapping above still dismisses.
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
  ),
  builder: (BuildContext sheet) =>
      _AddToListSheet(recipes: recipes, foods: foods),
);

class _AddToListSheet extends StatefulWidget {
  const _AddToListSheet({required this.recipes, required this.foods});

  final List<Recipe> recipes;
  final List<Food> foods;

  @override
  State<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends State<_AddToListSheet> {
  final TextEditingController _search = TextEditingController();

  Recipe? _recipe;
  Food? _food;
  double _servings = 1;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => normaliseKey(_search.text);

  List<Recipe> get _matchingRecipes {
    if (_query.isEmpty) {
      // Nothing typed yet: the most recently edited few. The library arrives
      // ordered by `updatedAt` descending, and the thing you are shopping for
      // is usually the thing you were just looking at.
      return widget.recipes.take(6).toList(growable: false);
    }
    return <Recipe>[
      for (final Recipe r in widget.recipes)
        if (normaliseKey(r.title).contains(_query)) r,
    ].take(8).toList(growable: false);
  }

  /// Foods, once there is something to match on.
  ///
  /// No opening suggestions, unlike recipes: a household has far more foods
  /// than recipes and they are the half you can always name, so six arbitrary
  /// ones would bury the recipes without being what anybody came for.
  List<Food> get _matchingFoods {
    if (_query.isEmpty) return const <Food>[];
    return <Food>[
      for (final Food f in widget.foods)
        if (normaliseKey(f.name).contains(_query)) f,
    ].take(8).toList(growable: false);
  }

  /// How much of the chosen thing, in words — and in the same terms the list
  /// will show, so the stepper and what lands on the line agree.
  String _amount(double servings) {
    final String shown = _number(servings);
    if (_recipe != null) {
      return '$shown ${servings == 1 ? 'serving' : 'servings'}';
    }
    final String? label = _food?.defaultServing?.label;
    if (label == null || label.isEmpty) {
      // What `ShoppingListBuilder.portionsOf` falls back to for a food with no
      // serving on it at all.
      return '$shown ${servings == 1 ? 'item' : 'items'}';
    }
    return '$shown × $label';
  }

  /// The same, for a screen reader: "×" is read as a symbol or not at all.
  String _spoken(double servings) {
    final String? label = _food?.defaultServing?.label;
    if (_recipe != null || label == null || label.isEmpty) {
      return _amount(servings);
    }
    return '${_number(servings)} of $label';
  }

  void _choose({Recipe? recipe, Food? food}) {
    setState(() {
      _recipe = recipe;
      _food = food;
      // A recipe is usually wanted at the yield it was written for; a food is
      // usually wanted one at a time. Clamped like every other path that sets
      // this, because a recipe saved with a yield of zero would otherwise seed
      // the stepper with it — and `addRecipe` refuses anything that is not
      // positive, so the Add button became an unhandled error rather than an
      // add.
      _servings = (recipe?.servings ?? 1).clamp(0.5, 99);
    });
  }

  void _step(double next) => setState(() => _servings = next.clamp(0.5, 99));

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String typed = _search.text.trim();
    final bool chosen = _recipe != null || _food != null;
    final List<Recipe> recipes = _matchingRecipes;
    final List<Food> foods = _matchingFoods;

    return SafeArea(
      top: false,
      // One scroll view over the whole sheet, heading and search field
      // included, rather than a fixed header above a scrolling list. At three
      // times the text on a 320-point phone the heading, the explanation and
      // the field are taller than the sheet is allowed to be, and a header
      // that cannot scroll has nowhere to put the overflow (spec §6.3).
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(
          HearthSpacing.lg,
          HearthSpacing.lg,
          HearthSpacing.lg,
          HearthSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: <Widget>[
          // A question rather than "Add to the list", which is what the
          // button at the end of the sheet says. A heading and an action
          // wearing the same words read as the same control to anybody
          // skimming, and as two of it to a screen reader.
          Text('What do you need?', style: context.text.sectionHeader),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            'A recipe puts its ingredients on, added up with whatever is '
            'already there.',
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: HearthSpacing.md),
          TextField(
            controller: _search,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'A recipe, a food, or anything else',
              hintText: 'Chilli, yoghurt, paper towels…',
            ),
          ),
          const SizedBox(height: HearthSpacing.md),
          if (chosen)
            _Chosen(
              name: _recipe?.title ?? _food!.name,
              amount: _amount(_servings),
              spokenAmount: _spoken(_servings),
              spokenMore: _spoken((_servings + 0.5).clamp(0.5, 99)),
              spokenFewer: _servings > 0.5
                  ? _spoken((_servings - 0.5).clamp(0.5, 99))
                  : null,
              // Half a serving is the smallest ask that means anything, and
              // zero would put a whole recipe on the list — the repository
              // refuses it outright.
              onFewer: _servings > 0.5 ? () => _step(_servings - 0.5) : null,
              onMore: () => _step(_servings + 0.5),
              onClear: () => _choose(),
              onAdd: () => Navigator.of(context).pop(
                _recipe != null
                    ? RecipeAddition(recipe: _recipe!, servings: _servings)
                    : FoodAddition(food: _food!, servings: _servings),
              ),
            )
          else ...<Widget>[
            for (final Recipe recipe in recipes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(recipe.title),
                // Said in words, not by the icon alone (spec §6.3): a recipe
                // and a food do very different things to the list.
                subtitle: Text('Recipe · ${_servingsWord(recipe.servings)}'),
                onTap: () => _choose(recipe: recipe),
              ),
            for (final Food food in foods)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.egg_outlined),
                title: Text(food.name),
                subtitle: const Text('Food'),
                onTap: () => _choose(food: food),
              ),
            // Always offered, not only when nothing matched: a shopping list
            // is mostly things no recipe asked for, and "paper towels" would
            // otherwise be unreachable the moment some food happened to
            // contain the word.
            if (typed.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add),
                title: Text('Add "$typed" as an item'),
                subtitle: Text(
                  recipes.isEmpty && foods.isEmpty
                      ? 'Nothing in the library matches'
                      : 'Straight onto the list, with no amount',
                ),
                onTap: () => Navigator.of(context).pop(PlainAddition(typed)),
              ),
          ],
        ],
      ),
    );
  }

  static String _servingsWord(double servings) =>
      '${_number(servings)} ${servings == 1 ? 'serving' : 'servings'}';

  /// Halves read as halves; whole numbers do not grow a `.0`.
  static String _number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

/// The thing you picked, and how much of it.
class _Chosen extends StatelessWidget {
  const _Chosen({
    required this.name,
    required this.amount,
    required this.spokenAmount,
    required this.spokenMore,
    required this.spokenFewer,
    required this.onFewer,
    required this.onMore,
    required this.onClear,
    required this.onAdd,
  });

  final String name;

  /// How much, as the sheet prints it — and as a screen reader should say it,
  /// which is not always the same string.
  final String amount;
  final String spokenAmount;

  /// What the value becomes either way, so the announcement after a press
  /// states the number rather than describing the gesture.
  final String spokenMore;
  final String? spokenFewer;

  final VoidCallback? onFewer;
  final VoidCallback onMore;
  final VoidCallback onClear;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(name, style: context.text.label)),
            TextButton(onPressed: onClear, child: const Text('Change')),
          ],
        ),
        const SizedBox(height: HearthSpacing.sm),
        // Label above the stepper, not beside it: at three times the text a
        // word and two kitchen-sized buttons do not share a line on a small
        // phone (spec §6.3).
        ExcludeSemantics(
          child: Text(
            'How many',
            style: context.text.label.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: HearthSpacing.xs),
        Row(
          children: <Widget>[
            _Step(icon: Icons.remove, label: 'Fewer', onPressed: onFewer),
            Expanded(
              child: Semantics(
                label: 'How many',
                value: spokenAmount,
                increasedValue: spokenMore,
                decreasedValue: spokenFewer ?? spokenAmount,
                onIncrease: onMore,
                onDecrease: onFewer,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HearthSpacing.sm,
                  ),
                  child: Text(
                    amount,
                    textAlign: TextAlign.center,
                    style: context.text.sectionHeader,
                  ),
                ),
              ),
            ),
            _Step(icon: Icons.add, label: 'More', onPressed: onMore),
          ],
        ),
        const SizedBox(height: HearthSpacing.lg),
        // A minimum rather than a fixed height, so the button grows with the
        // type instead of clipping its own label (spec §6.3).
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
          child: FilledButton(
            onPressed: onAdd,
            child: const Text('Add to the list'),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: HearthTouch.kitchenTarget,
    height: HearthTouch.kitchenTarget,
    child: Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: IconButton(icon: Icon(icon), tooltip: label, onPressed: onPressed),
    ),
  );
}
