import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/foods/restaurant_menu.dart';
import '../../domain/models/food.dart';
import '../../domain/recipes/macro_calculator.dart';
import 'recipe_draft.dart';

/// Building a meal from a restaurant's menu (spec §5.2).
///
/// Two stages in one screen: which restaurant, then what you had. A stage is
/// whether a restaurant has been chosen, not a separate flag — there is no
/// state a flag could disagree with about it.
///
/// The output is an ordinary recipe, unsaved, opened in the editor for a name
/// and a look. Nothing is written here (CLAUDE.md rule 4), which is also what
/// makes an accidental tap free.
class EatOutScreen extends ConsumerStatefulWidget {
  const EatOutScreen({super.key});

  @override
  ConsumerState<EatOutScreen> createState() => _EatOutScreenState();
}

class _EatOutScreenState extends ConsumerState<EatOutScreen> {
  String? _restaurant;

  /// What has been picked, by food id, with how many servings of each.
  ///
  /// Kept across a change of restaurant deliberately *not*: picking from two
  /// menus at once is not a meal, it is a mistake, and clearing says so
  /// before a bowl arrives with somebody else's rice in it.
  final Map<String, double> _picks = <String, double>{};

  void _choose(String restaurant) => setState(() {
    _restaurant = restaurant;
    _picks.clear();
  });

  void _toggle(Food food) => setState(() {
    if (_picks.remove(food.id) == null) _picks[food.id] = 1;
  });

  void _setCount(Food food, double count) => setState(() {
    if (count <= 0) {
      _picks.remove(food.id);
    } else {
      _picks[food.id] = count;
    }
  });

  List<MenuPick> _picked(List<Food> menu) => <MenuPick>[
    for (final Food food in menu)
      if (_picks[food.id] case final double count)
        MenuPick(food: food, count: count),
  ];

  void _build(List<Food> menu) {
    final List<MenuPick> picks = _picked(menu);
    if (picks.isEmpty) return;
    context.pushReplacement(
      '/recipe/new',
      extra: RecipeDraft.fromMenu(restaurant: _restaurant!, picks: picks),
    );
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final List<Food> library =
        ref.watch(foodLibraryProvider).value ?? const <Food>[];
    final List<String> restaurants = RestaurantMenu.restaurantsIn(library);
    final String? chosen = _restaurant;
    final List<Food> menu = chosen == null
        ? const <Food>[]
        : RestaurantMenu.itemsFor(chosen, library);
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(chosen ?? 'Ate out', style: context.text.sectionHeader),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Back to the restaurants first, then out. Two stages in one screen
          // means the system back gesture would otherwise skip the first.
          tooltip: chosen == null ? 'Close' : 'Back to restaurants',
          onPressed: () => chosen == null
              ? Navigator.of(context).pop()
              : setState(() {
                  _restaurant = null;
                  _picks.clear();
                }),
        ),
      ),
      floatingActionButton: _picks.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _build(menu),
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              icon: const Icon(Icons.check),
              label: Text(
                'Build (${_picks.length})',
                style: context.text.label,
              ),
            ),
      body: SafeArea(
        child: chosen == null
            ? _Restaurants(
                restaurants: restaurants,
                onPick: _choose,
                gutter: gutter,
              )
            : _Menu(
                menu: menu,
                picks: _picks,
                onToggle: _toggle,
                onCount: _setCount,
                gutter: gutter,
              ),
      ),
    );
  }
}

class _Restaurants extends StatelessWidget {
  const _Restaurants({
    required this.restaurants,
    required this.onPick,
    required this.gutter,
  });

  final List<String> restaurants;
  final ValueChanged<String> onPick;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    if (restaurants.isEmpty) {
      // Says how to fix it rather than just that there is nothing, because
      // "no restaurants" is a first-run state, not an error.
      return Padding(
        padding: EdgeInsets.all(gutter * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.storefront, size: 40, color: colors.textMuted),
            const SizedBox(height: HearthSpacing.md),
            Text(
              'No restaurants yet',
              style: context.text.sectionHeader,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HearthSpacing.sm),
            Text(
              'Add a food in the Foods tab, turn on "From a restaurant", and '
              'name the place. Everything you add under that name lands here.',
              style: context.text.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(gutter),
      itemCount: restaurants.length,
      separatorBuilder: (BuildContext _, int _) =>
          const SizedBox(height: HearthSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        final String name = restaurants[index];
        return Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: () => onPick(name),
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(color: colors.outline),
              ),
              padding: const EdgeInsets.all(HearthSpacing.lg),
              child: Row(
                children: <Widget>[
                  Icon(Icons.storefront, size: 20, color: colors.textMuted),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(child: Text(name, style: context.text.ingredient)),
                  Icon(Icons.chevron_right, color: colors.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.menu,
    required this.picks,
    required this.onToggle,
    required this.onCount,
    required this.gutter,
  });

  final List<Food> menu;
  final Map<String, double> picks;
  final ValueChanged<Food> onToggle;
  final void Function(Food food, double count) onCount;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    if (menu.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(gutter * 2),
        child: Center(
          child: Text(
            'Nothing on this menu yet.',
            style: context.text.body.copyWith(color: colors.textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter * 5),
      itemCount: menu.length,
      separatorBuilder: (BuildContext _, int _) =>
          const SizedBox(height: HearthSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        final Food food = menu[index];
        return _MenuRow(
          food: food,
          count: picks[food.id],
          onToggle: () => onToggle(food),
          onCount: (double count) => onCount(food, count),
        );
      },
    );
  }
}

/// One thing on the menu, with how many of it.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.food,
    required this.count,
    required this.onToggle,
    required this.onCount,
  });

  final Food food;

  /// Null when this one is not picked.
  final double? count;

  final VoidCallback onToggle;
  final ValueChanged<double> onCount;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double? picked = count;
    final bool isPicked = picked != null;
    final MenuPick pick = MenuPick(food: food, count: picked ?? 1);
    final ServingOption? serving = food.defaultServing;
    final String portion = serving == null
        ? ''
        : '${serving.label} · '
              '${MacroCalculator.forServings(serving, picked ?? 1).kcal.round()} kcal';

    return Semantics(
      // One thing to a screen reader: a checkbox, a name and a portion read
      // separately is three announcements for one row (§6.3).
      label: '${food.name}${portion.isEmpty ? '' : ', $portion'}',
      selected: isPicked,
      excludeSemantics: true,
      child: Material(
        color: isPicked ? colors.surfaceElevated : colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(
                color: isPicked ? colors.accent : colors.outline,
              ),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              children: <Widget>[
                // Icon as well as colour, never colour alone (§6.3).
                Icon(
                  isPicked ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: isPicked ? colors.accent : colors.textMuted,
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(food.name, style: context.text.ingredient),
                      if (portion.isNotEmpty) ...<Widget>[
                        const SizedBox(height: HearthSpacing.xxs),
                        Text(
                          isPicked && picked != 1
                              ? '${pick.line.split(' ').take(2).join(' ')}'
                                    ' · $portion'
                              : portion,
                          style: context.text.metadata.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Only where there is something to count. An unpicked row
                // showing a stepper invites setting a number on a thing you
                // have not said you had.
                if (isPicked) ...<Widget>[
                  const SizedBox(width: HearthSpacing.sm),
                  _Stepper(count: picked, onChanged: onCount),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Half, one, one and a half, two — how much of a served portion you had.
///
/// Quarters would be false precision against a scoop, and anything above a
/// few is not a portion but a second meal.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.count, required this.onChanged});

  final double count;
  final ValueChanged<double> onChanged;

  static const double _step = 0.5;
  static const double _max = 4;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String label = count == count.roundToDouble()
        ? '${count.round()}×'
        : '$count×';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          onPressed: count <= _step ? null : () => onChanged(count - _step),
          visualDensity: VisualDensity.compact,
          tooltip: 'One less',
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        SizedBox(
          width: 34,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: context.text.ingredient.copyWith(color: colors.textPrimary),
          ),
        ),
        IconButton(
          onPressed: count >= _max ? null : () => onChanged(count + _step),
          visualDensity: VisualDensity.compact,
          tooltip: 'One more',
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
      ],
    );
  }
}
