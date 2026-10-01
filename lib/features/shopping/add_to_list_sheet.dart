import 'package:flutter/material.dart';

import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/recipes/ingredient_consolidator.dart';
import '../../domain/shopping/manual_addition.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/text/text_normaliser.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import 'paste_items_sheet.dart';

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
  const PlainAddition(this.name, {this.quantity});

  final String name;
  final Quantity? quantity;
}

/// Several plain items, explicitly reviewed before saving.
final class PlainBatchAddition extends ListAddition {
  const PlainBatchAddition(this.items);

  final List<ManualListItem> items;
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
///
/// [onCommit] keeps a draft open until saving succeeds. Without it, the sheet
/// returns the selection as before, including the seeded recipe review.
/// [unavailableReason] prevents a held draft from crossing account boundaries.
/// [currentLines] is only a duplicate preview; saving rechecks the live list.
Future<ListAddition?> showAddToListSheet(
  BuildContext context, {
  required List<Recipe> recipes,
  required List<Food> foods,
  Recipe? recipe,
  double? servings,
  List<ShoppingLine> currentLines = const <ShoppingLine>[],
  Future<void> Function(ListAddition addition)? onCommit,
  String? Function()? unavailableReason,
}) => showModalBottomSheet<ListAddition>(
  context: context,
  backgroundColor: context.colors.background,
  isScrollControlled: true,
  // Capped like every other sheet here, so a tall one at large text scrolls
  // rather than overflowing, and tapping above still dismisses.
  constraints: BoxConstraints(
    maxWidth: 560,
    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
  ),
  builder: (BuildContext sheet) => _AddToListSheet(
    recipes: recipes,
    foods: foods,
    recipe: recipe,
    servings: servings,
    currentLines: currentLines,
    onCommit: onCommit,
    unavailableReason: unavailableReason,
  ),
);

/// Explains why a review cannot produce a shopping contribution. Uses the
/// repository's source builder so eligibility never guesses at conversions.
String? recipeShoppingIssue(Recipe recipe, {required double servings}) {
  if (recipe.isEatenOut) {
    return 'Meals eaten out do not add ingredients to the shopping list.';
  }
  if (!recipe.servings.isFinite || recipe.servings <= 0) {
    return 'Set a positive recipe yield before adding its ingredients.';
  }
  if (!servings.isFinite || servings <= 0) {
    return 'Choose a positive number of servings to add.';
  }
  if (IngredientConsolidator.mergeRecipes(
    <Recipe>[recipe],
    servingsFor: <String, double>{recipe.id: servings},
    sourceMode: true,
  ).isEmpty) {
    return 'This recipe has no ingredients to add to the shopping list. '
        'Optional ingredients are left out.';
  }
  return null;
}

class _AddToListSheet extends StatefulWidget {
  const _AddToListSheet({
    required this.recipes,
    required this.foods,
    this.recipe,
    this.servings,
    required this.currentLines,
    this.onCommit,
    this.unavailableReason,
  });

  final List<Recipe> recipes;
  final List<Food> foods;
  final Recipe? recipe;
  final double? servings;
  final List<ShoppingLine> currentLines;
  final Future<void> Function(ListAddition addition)? onCommit;
  final String? Function()? unavailableReason;

  @override
  State<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends State<_AddToListSheet> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _manualAmount = TextEditingController();
  Unit _manualUnit = Units.item;
  bool _showAmount = false;
  bool _saving = false;
  bool _openingPaste = false;
  bool _expired = false;
  String? _error;

  Recipe? _recipe;
  Food? _food;
  double _servings = 1;

  bool get _seeded => widget.recipe != null;
  double? get _seedServings => widget.servings ?? widget.recipe?.servings;
  double get _maximum =>
      _seedServings != null && _seedServings!.isFinite && _seedServings! > 99
      ? _seedServings!
      : 99;

  double get _minimum =>
      _seedServings != null &&
          _seedServings!.isFinite &&
          _seedServings! > 0 &&
          _seedServings! < 0.5
      ? _seedServings!
      : 0.5;

  @override
  void initState() {
    super.initState();
    _search.addListener(_changed);
    _manualAmount.addListener(_changed);
    _recipe = widget.recipe;
    final double initial = widget.servings ?? widget.recipe?.servings ?? 1;
    _servings = initial.isFinite && initial > 0
        ? initial.clamp(_minimum, _maximum)
        : 1;
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _search.dispose();
    _manualAmount.dispose();
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
    if (_saving || _expired) return;
    setState(() {
      _recipe = recipe;
      _food = food;
      _error = null;
      // A recipe is usually wanted at the yield it was written for; a food is
      // usually wanted one at a time. Clamped like every other path that sets
      // this, because a recipe saved with a yield of zero would otherwise seed
      // the stepper with it — and `addRecipe` refuses anything that is not
      // positive, so the Add button became an unhandled error rather than an
      // add.
      _servings = (recipe?.servings ?? 1).clamp(0.5, 99);
    });
  }

  void _step(double next) =>
      setState(() => _servings = next.clamp(_minimum, _maximum));

  Future<void> _submit(ListAddition addition) async {
    if (_saving || _expired) return;
    final String? unavailable = widget.unavailableReason?.call();
    if (unavailable != null) {
      setState(() {
        _error = unavailable;
        _expired = true;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onCommit?.call(addition);
      if (!mounted) return;
      if (widget.unavailableReason?.call() != null) {
        throw const ShoppingAdditionExpired();
      }
      Navigator.of(context).pop(addition);
    } on ShoppingAdditionExpired {
      if (!mounted) return;
      setState(() {
        _expired = true;
        _error = ShoppingAdditionExpired.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Could not add this item. Your choices are kept. Try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPlain() async {
    final String name = _search.text.trim();
    if (name.isEmpty ||
        manualItemAmountError(_manualAmount.text, _manualUnit) != null) {
      return;
    }
    await _submit(
      PlainAddition(
        name,
        quantity: _manualAmount.text.trim().isEmpty
            ? null
            : Quantity.of(parseAmount(_manualAmount.text)!, _manualUnit),
      ),
    );
  }

  Future<void> _paste() async {
    if (_saving || _openingPaste || _expired) return;
    _openingPaste = true;
    FocusScope.of(context).unfocus();
    try {
      final List<ManualListItem>? items = await showPasteItemsSheet(
        context,
        currentLines: widget.currentLines,
        unavailableReason: widget.unavailableReason,
        onCommit: widget.onCommit == null
            ? null
            : (List<ManualListItem> items) =>
                  widget.onCommit!(PlainBatchAddition(items)),
      );
      if (!mounted || items == null) return;
      Navigator.of(context).pop(PlainBatchAddition(items));
    } finally {
      _openingPaste = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String typed = _search.text.trim();
    final bool chosen = _recipe != null || _food != null;
    final List<Recipe> recipes = _matchingRecipes;
    final List<Food> foods = _matchingFoods;
    final String? issue = _recipe == null
        ? null
        : recipeShoppingIssue(_recipe!, servings: _servings);

    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          // One scroll view over the whole sheet, heading and search field
          // included, rather than a fixed header above a scrolling list. At three
          // times the text on a 320-point phone the heading, the explanation and
          // the field are taller than the sheet is allowed to be, and a header
          // that cannot scroll has nowhere to put the overflow (spec §6.3).
          child: ListView(
            key: const ValueKey<String>('add-to-list-scroll'),
            shrinkWrap: true,
            padding: const EdgeInsets.all(HearthSpacing.lg),
            children: <Widget>[
              // A question rather than "Add to the list", which is what the
              // button at the end of the sheet says. A heading and an action
              // wearing the same words read as the same control to anybody
              // skimming, and as two of it to a screen reader.
              Text(
                _seeded ? 'Add ingredients' : 'What do you need?',
                style: context.text.sectionHeader,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                _seeded
                    ? 'For our household shopping list. Ingredients are added '
                          'to whatever is already there.'
                    : 'Add anything you need. Recipes add their ingredients to '
                          'whatever is already there.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: HearthSpacing.md),
              if (!_seeded) ...<Widget>[
                TextField(
                  key: const ValueKey<String>('manual-item-name'),
                  controller: _search,
                  enabled: !_saving && !_expired,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'A recipe, a food, or anything else',
                    hintText: 'Chilli, yoghurt, paper towels…',
                  ),
                ),
                const SizedBox(height: HearthSpacing.md),
              ],
              if (chosen)
                _Chosen(
                  name: _recipe?.title ?? _food!.name,
                  amount: _amount(_servings),
                  spokenAmount: _spoken(_servings),
                  spokenMore: _spoken(
                    (_servings + 0.5).clamp(_minimum, _maximum),
                  ),
                  spokenFewer: _servings > _minimum
                      ? _spoken((_servings - 0.5).clamp(_minimum, _maximum))
                      : null,
                  // Half a serving is the smallest ask that means anything, and
                  // zero would put a whole recipe on the list — the repository
                  // refuses it outright.
                  onFewer: !_saving && !_expired && _servings > _minimum
                      ? () => _step(_servings - 0.5)
                      : null,
                  onMore: _saving || _expired
                      ? null
                      : () => _step(_servings + 0.5),
                  onClear: _seeded || _saving || _expired
                      ? null
                      : () => _choose(),
                  issue: issue,
                  onAdd: issue != null || _saving || _expired
                      ? null
                      : () => _submit(
                          _recipe != null
                              ? RecipeAddition(
                                  recipe: _recipe!,
                                  servings: _servings,
                                )
                              : FoodAddition(food: _food!, servings: _servings),
                        ),
                  addLabel: _saving
                      ? 'Adding…'
                      : _error != null && !_expired
                      ? 'Retry'
                      : 'Add to the list',
                )
              else ...<Widget>[
                for (final Recipe recipe in recipes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(recipe.title),
                    // Said in words, not by the icon alone (spec §6.3): a recipe
                    // and a food do very different things to the list.
                    subtitle: Text(
                      'Recipe · ${_servingsWord(recipe.servings)}',
                    ),
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
                // A name-only item is still one tap. An amount is optional here,
                // before saving, so adding coffee need not visit a second editor.
                if (typed.isNotEmpty) ...<Widget>[
                  if (_showAmount) ...<Widget>[
                    ManualItemAmountFields(
                      controller: _manualAmount,
                      unit: _manualUnit,
                      keyPrefix: 'manual-item',
                      enabled: !_saving && !_expired,
                      onUnitChanged: (Unit unit) =>
                          setState(() => _manualUnit = unit),
                    ),
                    const SizedBox(height: HearthSpacing.sm),
                  ],
                  ListTile(
                    key: const ValueKey<String>('manual-item-add'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add),
                    title: Text(
                      _saving
                          ? 'Adding…'
                          : _error != null && !_expired
                          ? 'Retry'
                          : 'Add "$typed" as an item',
                    ),
                    subtitle: Text(
                      _manualAmount.text.trim().isEmpty
                          ? 'No amount needed'
                          : 'With the amount above',
                    ),
                    onTap:
                        _saving ||
                            _expired ||
                            manualItemAmountError(
                                  _manualAmount.text,
                                  _manualUnit,
                                ) !=
                                null
                        ? null
                        : _addPlain,
                  ),
                  if (!_showAmount)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey<String>('manual-item-add-amount'),
                        onPressed: _saving || _expired
                            ? null
                            : () => setState(() => _showAmount = true),
                        icon: const Icon(Icons.straighten),
                        label: const Text('Add amount'),
                      ),
                    ),
                ],
                const SizedBox(height: HearthSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey<String>('paste-items-open'),
                  onPressed: _saving || _expired ? null : _paste,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Paste items'),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: context.text.body),
                ),
              ],
              if (_seeded || _error != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.sm),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _servingsWord(double servings) =>
      '${_number(servings)} ${servings == 1 ? 'serving' : 'servings'}';

  /// Halves read as halves; whole numbers do not grow a `.0`.
  static String _number(double value) => QuantityFormat.count(value);
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
    this.issue,
    this.addLabel = 'Add to the list',
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
  final VoidCallback? onMore;
  final VoidCallback? onClear;
  final VoidCallback? onAdd;
  final String? issue;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final Widget fewer = _Step(
      icon: Icons.remove,
      label: 'Fewer',
      onPressed: onFewer,
    );
    final Widget more = _Step(
      icon: Icons.add,
      label: 'More',
      onPressed: onMore,
    );
    final Widget quantity = Semantics(
      label: 'How many',
      value: spokenAmount,
      increasedValue: spokenMore,
      decreasedValue: spokenFewer ?? spokenAmount,
      onIncrease: onMore,
      onDecrease: onFewer,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HearthSpacing.sm),
        child: Text(
          amount,
          textAlign: TextAlign.center,
          style: context.text.sectionHeader,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(name, style: context.text.label)),
            if (onClear != null)
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
        if (MediaQuery.textScalerOf(context).scale(14) > 21) ...<Widget>[
          quantity,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[fewer, more],
          ),
        ] else
          Row(
            children: <Widget>[
              fewer,
              Expanded(child: quantity),
              more,
            ],
          ),
        const SizedBox(height: HearthSpacing.lg),
        if (issue != null) ...<Widget>[
          Text(issue!, style: context.text.body),
          const SizedBox(height: HearthSpacing.md),
        ],
        // A minimum rather than a fixed height, so the button grows with the
        // type instead of clipping its own label (spec §6.3).
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: HearthTouch.minTarget),
          child: FilledButton(onPressed: onAdd, child: Text(addLabel)),
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
