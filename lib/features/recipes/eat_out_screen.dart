import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/foods/restaurant_menu.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../plan/logging_intent.dart';
import 'recipe_draft.dart';
import 'recipe_editor_args.dart';

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
  const EatOutScreen({this.intent, super.key});

  /// The meal this build belongs to, when it started from one (U04).
  ///
  /// Null when the builder was opened from the recipe library, where there is
  /// no meal in progress and an ordinary Save is the right ending.
  final LoggingIntent? intent;

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

  /// Whether anything real is picked for a deduction to come off.
  ///
  /// Real means an ordinary menu row picked in the ordinary direction: not a
  /// modifier, and not another deduction. A deduction has to have something
  /// to come off — on its own it is not a meal, it is 180 calories taken out
  /// of a day that never had them.
  ///
  /// [excluding] asks the question as it will stand *after* a pick changes
  /// direction. Taking the burger out of a meal whose only other line is "no
  /// lettuce" leaves nothing behind but deductions, and the guard has to see
  /// that before it happens rather than sweeping up afterwards.
  bool _hasSomethingToApplyTo(List<Food> menu, {Food? excluding}) => menu.any(
    (Food food) =>
        !food.isModifier &&
        food.id != excluding?.id &&
        (_picks[food.id] ?? 0) > 0,
  );

  void _toggle(Food food, List<Food> menu) => setState(() {
    if (_picks.remove(food.id) != null) {
      // Unpicking the last real thing takes the deductions with it. Left
      // behind, they would be a meal of minus 180 calories, and the rule
      // above would hold only until somebody changed their mind.
      if (!food.isModifier) _sweepStrandedDeductions(menu);
      return;
    }
    if (food.isModifier && !_hasSomethingToApplyTo(menu)) return;
    // A modifier is one or none. You do not lettuce-wrap a burger 3.5 times.
    _picks[food.id] = 1;
  });

  /// Picks [food] the other way round: taken out rather than put in.
  ///
  /// The case is a published figure that already counts something you asked
  /// them to leave off — a cheeseburger with no lettuce. Deliberately not the
  /// modifier mechanism (spec §5.2): this is an ordinary positive row, and
  /// only the direction of the pick is new.
  ///
  /// A modifier is never removable. It is already a deduction, so taking one
  /// out would be an addition the chain never published. Neither is a row the
  /// sheet gave no portion: with no amount for the sign to sit on, the line
  /// comes out as a bare name that deducts nothing and is flagged for having
  /// no quantity — a deduction that silently does not deduct.
  void _remove(Food food, List<Food> menu) {
    if (!RestaurantMenu.canBeTakenOut(food)) return;
    if (!_hasSomethingToApplyTo(menu, excluding: food)) {
      // Reachable only as a race now that the control is not offered until
      // there is something for it to come off: the menu is watched and the
      // picks are not, so a partner deleting the burger between this frame
      // and the tap leaves a button whose reason has just stopped being
      // true. Said out loud rather than silently ignored, because a control
      // that takes a tap and does nothing is worse than one that explains
      // itself (§6.3).
      _say('Pick something for ${food.name} to come out of first.');
      return;
    }
    setState(() => _picks[food.id] = -1);
  }

  /// One sentence, where the tap happened, in words rather than a colour.
  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _setCount(Food food, double count, List<Food> menu) => setState(() {
    if (count != 0) {
      _picks[food.id] = count;
      return;
    }
    // The second place a real pick can leave `_picks`, and the sweep has to
    // live in both or the invariant holds only on the path somebody happened
    // to test.
    _picks.remove(food.id);
    _sweepStrandedDeductions(menu);
  });

  /// Drops anything left with nothing to come off — a modifier, or a
  /// component somebody took out of a meal that is no longer there.
  void _sweepStrandedDeductions(List<Food> menu) {
    if (_hasSomethingToApplyTo(menu)) return;
    for (final Food food in menu) {
      if (food.isModifier || (_picks[food.id] ?? 0) < 0) {
        _picks.remove(food.id);
      }
    }
  }

  List<MenuPick> _picked(List<Food> menu) => <MenuPick>[
    for (final Food food in menu)
      if (_picks[food.id] case final double count)
        MenuPick(food: food, count: count),
  ];

  /// What the picks come to, for the guard below.
  ///
  /// A food with no serving contributes nothing and is not a gap here: it is
  /// an unquantified line, which the editor flags in its own right.
  Macros _total(List<MenuPick> picks) => Macros.sum(<Macros>[
    for (final MenuPick pick in picks)
      if (pick.food.defaultServing case final ServingOption serving)
        MacroCalculator.forServings(serving, pick.count),
  ]);

  void _build(List<Food> menu) {
    final List<MenuPick> picks = _picked(menu);
    if (picks.isEmpty) return;
    // The menu is watched and the picks are not, so a partner deleting the
    // burger while this sheet is open can leave the wrap standing alone —
    // and a greyed row cannot be tapped to unpick it. Refusing here is the
    // last place before a −180 kcal meal becomes a recipe.
    if (!_hasSomethingToApplyTo(menu)) return;
    // And "something real is picked" is not the same question as "this adds
    // up". Three calories of lettuce satisfied the rule above while a burger
    // came out underneath it, and the builder assembled a meal of −377 kcal —
    // which §5.2 says cannot happen, and which the macro calculator, the
    // spec and the tests all said the builder would not do. Same predicate
    // the calculator uses, so the two cannot disagree about one meal.
    if (_total(picks).isBelowNothing) {
      _say(
        'That comes to less than nothing. Take out less, or add what it is '
        'coming out of.',
      );
      return;
    }
    context.pushReplacement(
      '/recipe/new',
      extra: RecipeEditorArgs(
        draft: RecipeDraft.fromMenu(restaurant: _restaurant!, picks: picks),
        intent: widget.intent,
      ),
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
        title: Text(chosen ?? 'Eat out', style: context.text.sectionHeader),
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
                sections: RestaurantMenu.sectionsFor(chosen, library),
                picks: _picks,
                hasSomethingToApplyTo: _hasSomethingToApplyTo(menu),
                canRemove: (Food food) =>
                    _hasSomethingToApplyTo(menu, excluding: food),
                onToggle: (Food food) => _toggle(food, menu),
                onRemove: (Food food) => _remove(food, menu),
                onCount: (Food food, double count) =>
                    _setCount(food, count, menu),
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
              'Paste a menu off a nutrition sheet, or add items one at a time '
              'in the Foods tab with "From a restaurant" turned on.',
              style: context.text.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HearthSpacing.lg),
            FilledButton.icon(
              onPressed: () => context.push('/food/menu-import'),
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste a menu'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(gutter),
      // One past the end: adding the next restaurant belongs with the list of
      // them, not behind a menu you have to open one of the others to find.
      itemCount: restaurants.length + 1,
      separatorBuilder: (BuildContext _, int _) =>
          const SizedBox(height: HearthSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        if (index == restaurants.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: HearthTouch.minTarget,
              child: TextButton.icon(
                onPressed: () => context.push('/food/menu-import'),
                icon: const Icon(Icons.add, size: 18),
                // It has taken PDFs and photographs since #52. Paste is
                // one of three ways in, and naming the least of them sent
                // people looking for a clipboard they did not need.
                label: const Text('Add restaurant'),
              ),
            ),
          );
        }
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

/// A restaurant's menu, with a way through it (review §7.6).
///
/// Search and the section chips are held here rather than on the screen
/// above, because they are about *looking* at a menu and nothing about them
/// outlives it: changing restaurant throws the whole widget away, which is
/// exactly the right lifetime for a query.
///
/// **Section jump is a filter, not a scroll.** Scrolling to a heading means
/// reaching a widget a lazy `ListView` has not built — `ensureVisible` has no
/// context for it — and doing it properly needs a scroll-to-index package the
/// app does not carry. A filter gets you to Toppings exactly, keeps the
/// source order and grouping inside it, and composes with the search instead
/// of fighting it.
class _Menu extends StatefulWidget {
  const _Menu({
    required this.sections,
    required this.picks,
    required this.onToggle,
    required this.onRemove,
    required this.onCount,
    required this.hasSomethingToApplyTo,
    required this.canRemove,
    required this.gutter,
  });

  final List<MenuSection> sections;
  final Map<String, double> picks;

  /// Whether anything a modifier could come off is picked yet.
  final bool hasSomethingToApplyTo;

  /// Whether this row in particular can be taken out — which is the same
  /// question, asked without counting the row itself.
  final bool Function(Food food) canRemove;

  final ValueChanged<Food> onToggle;
  final ValueChanged<Food> onRemove;
  final void Function(Food food, double count) onCount;
  final double gutter;

  @override
  State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> {
  final TextEditingController _query = TextEditingController();

  /// The section shown on its own, or null for all of them.
  String? _only;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// How many rows the whole menu has, which is the fact that tells you the
  /// search is worth using. A bare magnifier over a list you cannot see the
  /// end of says nothing at all.
  int get _total =>
      widget.sections.fold(0, (int n, MenuSection s) => n + s.items.length);

  /// The sections as narrowed by the chip and the query, dropping any left
  /// with nothing in them — a heading over no rows is a worse answer than no
  /// heading.
  List<MenuSection> get _shown {
    final String query = _query.text.trim().toLowerCase();
    final List<MenuSection> narrowed = <MenuSection>[];
    for (final MenuSection section in widget.sections) {
      if (_only != null && section.name != _only) continue;
      final List<Food> items = query.isEmpty
          ? section.items
          : <Food>[
              for (final Food food in section.items)
                if (food.name.toLowerCase().contains(query)) food,
            ];
      if (items.isEmpty) continue;
      narrowed.add(MenuSection(name: section.name, items: items));
    }
    return narrowed;
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double gutter = widget.gutter;
    if (widget.sections.isEmpty) {
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

    final List<MenuSection> sections = _shown;
    final List<String> names = <String>[
      for (final MenuSection section in widget.sections)
        if (section.name case final String name) name,
    ];

    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
          child: TextField(
            controller: _query,
            onChanged: (String _) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              // The count, not a bare "Search": on a 44-row menu the number
              // is the reason to type rather than scroll.
              hintText: 'Search $_total items',
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Clear the search',
                      onPressed: () => setState(_query.clear),
                    ),
            ),
          ),
        ),
        if (names.length > 1)
          // Sized by the chips, not by a number. A fixed box did not overflow
          // at 3x text — it *constrained*, which is quieter and no better:
          // the chip wants 78 points and was given 56, the same 56 it gets at
          // 2x. Dynamic type is honoured, not capped (spec §6.3).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(
              gutter,
              HearthSpacing.sm,
              gutter,
              HearthSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                for (final String name in names)
                  Padding(
                    padding: const EdgeInsets.only(right: HearthSpacing.sm),
                    child: FilterChip(
                      label: Text(name),
                      selected: _only == name,
                      // Choosing the one already chosen puts the whole menu
                      // back, so the rail is never a state you cannot leave.
                      onSelected: (bool _) =>
                          setState(() => _only = _only == name ? null : name),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: sections.isEmpty
              ? _NoMatches(
                  query: _query.text,
                  section: _only,
                  // Widening before clearing: with a section chosen, the
                  // likeliest next thing is the same search over the whole
                  // menu, not starting again.
                  onWiden: _only == null
                      ? null
                      : () => setState(() => _only = null),
                  onClear: () => setState(() {
                    _query.clear();
                    _only = null;
                  }),
                  gutter: gutter,
                )
              : _list(context, sections, gutter),
        ),
      ],
    );
  }

  Widget _list(
    BuildContext context,
    List<MenuSection> sections,
    double gutter,
  ) {
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter * 5),
      children: <Widget>[
        for (final MenuSection section in sections) ...<Widget>[
          // A section with no name is the items the sheet never grouped.
          // Shown without a heading rather than under one Hearth invented.
          if (section.name case final String name) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(
                top: HearthSpacing.sm,
                bottom: HearthSpacing.sm,
              ),
              // Keyed, because the section's name is now on screen twice —
              // as this heading and as its jump chip — and a test reaching
              // for "Beans" should not have to know which order they are in.
              child: Text(
                name,
                key: Key('menu-section-$name'),
                style: context.text.sectionHeader,
              ),
            ),
          ],
          for (final Food food in section.items) ...<Widget>[
            _MenuRow(
              food: food,
              count: widget.picks[food.id],
              canPick: !food.isModifier || widget.hasSomethingToApplyTo,
              canRemove: widget.canRemove(food),
              onToggle: () => widget.onToggle(food),
              onRemove: () => widget.onRemove(food),
              onCount: (double count) => widget.onCount(food, count),
            ),
            const SizedBox(height: HearthSpacing.sm),
          ],
        ],
      ],
    );
  }
}

/// What a search that found nothing says.
///
/// Named rather than folded into the list, because "no rows" and "no menu"
/// are different facts and the empty menu above already has its own sentence.
/// Offers the way out as a control, not as advice: the state it is in is one
/// the screen put you in.
class _NoMatches extends StatelessWidget {
  const _NoMatches({
    required this.query,
    required this.section,
    required this.onWiden,
    required this.onClear,
    required this.gutter,
  });

  final String query;

  /// The section the list is narrowed to, if any. Named in the sentence
  /// because without it the sentence is false: filtered to Dressings, a
  /// search for guacamole said "nothing on this menu matches" — and the menu
  /// has guacamole, one section over.
  final String? section;

  /// Widen to the whole menu, keeping the search. Null when there is no
  /// section to widen out of.
  final VoidCallback? onWiden;

  final VoidCallback onClear;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final String typed = query.trim();
    final String? within = section;
    final String said;
    if (typed.isEmpty) {
      said = 'Nothing is left in ${within ?? 'this menu'}.';
    } else if (within == null) {
      said = 'Nothing on this menu matches "$typed".';
    } else {
      said = 'Nothing in $within matches "$typed".';
    }

    return Padding(
      padding: EdgeInsets.all(gutter * 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.search_off, size: 36, color: colors.textMuted),
          const SizedBox(height: HearthSpacing.md),
          Text(
            said,
            style: context.text.body.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HearthSpacing.md),
          if (onWiden case final VoidCallback widen)
            TextButton(
              onPressed: widen,
              child: const Text('Search the whole menu'),
            ),
          TextButton(onPressed: onClear, child: const Text('Show everything')),
        ],
      ),
    );
  }
}

/// One thing on the menu, with how many of it.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.food,
    required this.count,
    required this.canPick,
    required this.canRemove,
    required this.onToggle,
    required this.onRemove,
    required this.onCount,
  });

  final Food food;

  /// Null when this one is not picked. Negative when it is being taken out of
  /// the meal rather than put in (spec §5.2).
  final double? count;

  /// False for a modifier with nothing yet to apply to. Shown greyed with the
  /// reason rather than hidden: a row that disappears and reappears as you
  /// pick is harder to understand than one that says why it is waiting.
  final bool canPick;

  /// Whether this component can be taken out — which needs something else
  /// real to take it out of, for the same reason a modifier does.
  final bool canRemove;

  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final ValueChanged<double> onCount;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double? picked = count;
    final bool isPicked = picked != null;
    final bool isRemoved = (picked ?? 0) < 0;
    final MenuPick pick = MenuPick(food: food, count: picked ?? 1);
    final ServingOption? serving = food.defaultServing;
    // What you are actually having, not the serving *and* what you are having
    // beside it. A picked half-scoop read "2.0000000088184904 oz · 4 oz · 65
    // kcal", which is two portions and a float for one line of one item.
    final double kcal = serving == null
        ? 0
        : MacroCalculator.forServings(serving, picked ?? 1).kcal;
    // A minus sign in the text, not a colour: a deduction has to read as one
    // to a screen reader and on a monochrome display (§6.3). `−` is the real
    // minus, which is what a number this size deserves next to a portion.
    final String calories = kcal < 0
        ? '−${kcal.abs().round()} kcal'
        : '${kcal.round()} kcal';
    final String portion = serving == null
        ? ''
        : '${isPicked ? pick.portionLabel : serving.label} · $calories';
    // The same sentence for both kinds of deduction, because they read the
    // same way to somebody eating: one is the chain's own row, the other is
    // an ordinary row picked backwards.
    final String? deduction = food.isModifier
        ? (canPick ? 'Takes away' : 'Takes away — pick something first')
        : isRemoved
        ? 'Taking it out'
        : null;

    return Material(
      color: isPicked ? colors.surfaceElevated : colors.surface,
      borderRadius: BorderRadius.circular(HearthRadius.md),
      child: InkWell(
        // Unpicking is always allowed. A modifier can end up picked with
        // nothing left to apply to — the menu is watched and the picks are
        // not, so a partner can delete the burger out from under it — and a
        // row that cannot be tapped would leave no way out of that.
        onTap: canPick || isPicked ? onToggle : null,
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
              Expanded(
                child: Semantics(
                  // One thing to a screen reader: a checkbox, a name and a
                  // portion read separately is three announcements for one
                  // row (§6.3). Only what the row *says*, though — the
                  // controls beside it keep their own labels, or a screen
                  // reader would be told the row is tappable and never told
                  // there is a way to take the component out of it.
                  label:
                      '${food.name}'
                      '${deduction == null ? '' : ', $deduction'}'
                      '${portion.isEmpty ? '' : ', $portion'}',
                  // Only where the row can actually be picked. A modifier
                  // waiting for something to apply to has no tap, and a node
                  // that announces itself as selected-or-not and then cannot
                  // be activated tells a screen-reader user they made the
                  // mistake (§6.3). Unselectable, it is a line of text
                  // saying what it is waiting for, which is the truth.
                  selected: canPick || isPicked ? isPicked : null,
                  excludeSemantics: true,
                  child: Row(
                    children: <Widget>[
                      // Icon as well as colour, never colour alone (§6.3).
                      Icon(
                        isRemoved
                            ? Icons.do_not_disturb_on_outlined
                            : isPicked
                            ? Icons.check_circle
                            : food.isModifier
                            ? Icons.remove_circle_outline
                            : Icons.circle_outlined,
                        size: 20,
                        color: isPicked ? colors.accent : colors.textMuted,
                      ),
                      const SizedBox(width: HearthSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              food.name,
                              style: context.text.ingredient.copyWith(
                                color: canPick ? null : colors.textMuted,
                              ),
                            ),
                            if (portion.isNotEmpty) ...<Widget>[
                              const SizedBox(height: HearthSpacing.xxs),
                              Text(
                                portion,
                                style: context.text.metadata.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                            // In words, so a deduction reads as one without
                            // the colour or the icon (§6.3) — and for a
                            // modifier, why it is waiting, rather than a row
                            // that silently does nothing when tapped.
                            if (deduction case final String said) ...<Widget>[
                              const SizedBox(height: HearthSpacing.xxs),
                              Text(
                                said,
                                style: context.text.metadata.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // "No lettuce": the published burger already counted it, so the
              // ordinary row comes out of the meal instead of going in. Never
              // on a modifier, which is a deduction already, and never on
              // something already picked — unpick it first, which is the one
              // tap that says what it does.
              // And never on a row the sheet gave no portion — see
              // [RestaurantMenu.canBeTakenOut], which is where both rules
              // live so this screen and the domain cannot disagree.
              // "No lettuce" — only once there is something for it to come
              // off, which is the same question `_remove` guards with.
              //
              // This reverses an earlier decision that kept it on every row,
              // greyed, with "pick something first" in its tooltip: the
              // reasoning was that a control which comes and goes is harder
              // to follow than one saying what it waits for. True of the
              // modifier *rows*, which say it in visible words. Not true
              // here — a tooltip is invisible without a screen reader or a
              // hover no phone has, so the waiting state was mute. What it
              // did have was width: at 2x text it took enough to wrap a
              // three-word item name onto three lines (review §7.6).
              if (RestaurantMenu.canBeTakenOut(food) &&
                  !isPicked &&
                  canRemove) ...<Widget>[
                const SizedBox(width: HearthSpacing.sm),
                IconButton(
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  // Named, not "take it out": read on its own by a screen
                  // reader it would be a control with no subject.
                  tooltip: 'Take ${food.name} out',
                  icon: const Icon(Icons.do_not_disturb_on_outlined, size: 20),
                ),
              ],
              // Only where there is something to count. An unpicked row
              // showing a stepper invites setting a number on a thing you
              // have not said you had.
              // And never for a modifier, which is one or none: the
              // deduction is for taking the bun off, and there is only one
              // bun.
              if (isPicked && !food.isModifier) ...<Widget>[
                const SizedBox(width: HearthSpacing.sm),
                _Stepper(
                  count: picked,
                  removing: isRemoved,
                  onChanged: onCount,
                ),
              ],
            ],
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
///
/// A portion being taken out of the meal is counted the same way, on its
/// magnitude: two slices of cheese off a double is −2, and the buttons say
/// "more" and "less" of what is being taken out rather than walking a number
/// up through zero and out the other side.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.count,
    required this.onChanged,
    this.removing = false,
  });

  /// Signed: negative when this component is being taken out.
  final double count;
  final bool removing;
  final ValueChanged<double> onChanged;

  static const double _step = 0.5;
  static const double _max = 4;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final double portions = count.abs();
    final String number = portions == portions.roundToDouble()
        ? '${portions.round()}'
        : '$portions';
    // The real minus again, in the text, so "−1×" cannot be mistaken for "1×"
    // by anybody reading or hearing it (§6.3).
    final String label = removing ? '−$number×' : '$number×';
    void set(double next) => onChanged(removing ? -next : next);

    // A disabled `IconButton` does not take the tap. It falls through to
    // whatever is behind it — here the row's own `InkWell`, which unpicks the
    // item — so "One less" at half a portion deleted the burger from the
    // meal, and "One more" at four did the same. The same mechanism the
    // take-out button beside this one already works around, and the reason it
    // is enabled even when it will refuse.
    //
    // Swallowed rather than worked around, because a stepper at its limit
    // *should* be disabled: Material greys it and a screen reader says so,
    // which is a truer answer than a button that looks live and declines.
    // This stops the tap at the stepper instead, including in the gaps
    // between the buttons.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: portions <= _step ? null : () => set(portions - _step),
            visualDensity: VisualDensity.compact,
            tooltip: removing ? 'Take out less' : 'One less',
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
          SizedBox(
            width: 34,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: context.text.ingredient.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: portions >= _max ? null : () => set(portions + _step),
            visualDensity: VisualDensity.compact,
            tooltip: removing ? 'Take out more' : 'One more',
            icon: const Icon(Icons.add_circle_outline, size: 20),
          ),
        ],
      ),
    );
  }
}
