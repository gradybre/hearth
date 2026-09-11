import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/centred_message.dart';
import '../../app/widgets/reading_column.dart';
import '../../app/widgets/swipe_to_delete.dart';
import '../../app/widgets/undo_snackbar.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import 'add_food_sheet.dart';
import 'external_food_results.dart';
import 'food_filter_bar.dart';
import 'food_scope.dart';
import 'food_search_controller.dart';

/// The household food library (spec §5.5).
///
/// Search filters the already-loaded list rather than round-tripping the
/// database, because finding a food is on the daily logging path and every
/// extra tap or wait is paid three times a day. Open Food Facts and USDA are
/// searched too, but underneath and on their own schedule — the local list
/// must never wait on a network call to appear.
///
/// Two things the review asked for live here (§6.2.6, §7.5): one labelled way
/// in rather than a stack of icon-only floating buttons, and a scope over
/// whose foods the list is showing — the household's own, or a restaurant's
/// menus — because a seeded chain is hundreds of rows and this is the screen
/// people open to log from.
class FoodLibraryScreen extends ConsumerStatefulWidget {
  const FoodLibraryScreen({super.key});

  @override
  ConsumerState<FoodLibraryScreen> createState() => _FoodLibraryScreenState();
}

class _FoodLibraryScreenState extends ConsumerState<FoodLibraryScreen> {
  final TextEditingController _search = TextEditingController();

  /// Which foods are picked for a batch delete. Empty means normal browsing;
  /// selection mode is however many of these there are, not a separate flag —
  /// there is no state a flag could disagree with the set about.
  final Set<String> _selected = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Long-press starts selecting; a tap while selecting adds to or removes
  /// from it. Both are this one toggle — long-pressing an empty selection is
  /// indistinguishable from starting one.
  void _toggle(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });

  /// Deletes everything selected, with one undo that restores all of them.
  ///
  /// No confirmation dialog: long-press, then a tap per item, then a deliberate
  /// tap on Delete is already three distinct gestures — more than the swipe
  /// and tap that a single delete asks for without one. The safety net is the
  /// same as a single delete's: a real soft-delete restore, not a re-creation.
  /// Shows the half of the library a newly saved food actually landed in.
  ///
  /// Every way in can cross the divide: entering one by hand while the menus
  /// are showing writes a food of your own, and the editor's "From a
  /// restaurant" switch writes a menu row while your own foods are showing —
  /// that one without the scope being touched at all. Either way the save
  /// succeeds and the list does not change, which reads as a save that failed.
  /// The switch moving is what says where it went.
  Future<void> _reveal(String id) async {
    final Food? food = await ref.read(foodRepositoryProvider).byId(id);
    if (food == null || !mounted) return;
    final FoodScope scope = FoodScope.of(food);
    if (ref.read(currentFoodScopeProvider) == scope) return;
    await _chooseScope(scope);
  }

  /// Opens the blank editor, and shows where what it saved landed.
  ///
  /// The same door as the sheet's "Enter it by hand" row, so it answers the
  /// same way: a food saved out of the scope you are standing in moves the
  /// switch rather than disappearing.
  Future<void> _addByHand() async {
    final String? saved = await context.push<String>('/food/new');
    if (saved != null) await _reveal(saved);
  }

  /// Switches scope, and lets a failed write go quiet.
  ///
  /// The notifier puts the state back when the row will not store, so the
  /// chip returning to where it was is already the whole report — and the tap
  /// was to look at a list, not to save anything. What must not happen is the
  /// rethrow escaping a callback nobody awaits, which is an unhandled error
  /// for a preference.
  Future<void> _chooseScope(FoodScope scope) async {
    try {
      await ref.read(foodScopeProvider.notifier).choose(scope);
    } on Object {
      // Deliberately swallowed; see above.
    }
  }

  Future<void> _deleteSelected() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final List<String> ids = _selected.toList(growable: false);
    final int count = ids.length;

    await Future.wait(
      ids.map((String id) => ref.read(foodRepositoryProvider).delete(id)),
    );
    if (!mounted) return;

    setState(() => _selected.clear());
    showUndoSnackBar(
      messenger,
      message: count == 1 ? 'Deleted 1 food' : 'Deleted $count foods',
      onUndo: () {
        for (final String id in ids) {
          ref.read(foodRepositoryProvider).restore(id);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final AsyncValue<List<Food>> library = ref.watch(scopedFoodsProvider);
    final FoodScope scope = ref.watch(currentFoodScopeProvider);
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      // One labelled control, matching Recipes' Add recipe (review §6.2.6).
      //
      // This corner used to hold three floating buttons, and four once a
      // build could read labels: a bare +, an unlabelled seasoning icon, and
      // Scan. Two of them said what they did only in a tooltip, which is a
      // hover on a device with no pointer — and the stack grew by one every
      // time another way in was built. The ways in are behind this now, and
      // the maintenance is in the labelled menu at the top of the list.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'food-add',
        onPressed: () => showAddFoodSheet(context, onSaved: _reveal),
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        icon: const Icon(Icons.add),
        label: Text('Add food', style: context.text.label),
      ),
      body: SafeArea(
        child: ReadingColumn(
          child: library.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stack) => Center(
              child: Text('The food library could not be read.\n$error'),
            ),
            data: (List<Food> visible) {
              // The unfiltered library *in this scope*, for the "nothing here
              // yet" branch: no foods at all and no foods matching are
              // different states and want different words — and so are no
              // foods of your own and no restaurant menus.
              final List<Food> foods =
                  ref.watch(scopedLibraryProvider).value ?? const <Food>[];

              // And the library in *either* scope, which is a different
              // question again: whether there is anything to be on one side
              // of the switch is what decides whether to draw the switch.
              final List<Food> anywhere =
                  ref.watch(foodLibraryProvider).value ?? const <Food>[];

              // Slivers rather than a Column with an Expanded list, for the
              // reason the recipe library records: the title, the scope, the
              // search field and the filter bar are fixed chrome, and on a
              // 320x568 phone at three times the text they are taller than
              // the screen on their own — which hands the list a negative
              // height. As slivers the chrome scrolls away with the content
              // (spec §6.3).
              return CustomScrollView(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                      child: _selected.isEmpty
                          ? Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    'Foods',
                                    style: context.text.recipeTitle,
                                  ),
                                ),
                                const _MaintenanceMenu(),
                              ],
                            )
                          : Row(
                              children: <Widget>[
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Cancel selecting',
                                  onPressed: () =>
                                      setState(() => _selected.clear()),
                                ),
                                Expanded(
                                  child: Text(
                                    '${_selected.length} selected',
                                    style: context.text.recipeTitle,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip:
                                      'Delete ${_selected.length} selected '
                                      'foods',
                                  color: colors.error,
                                  onPressed: _deleteSelected,
                                ),
                              ],
                            ),
                    ),
                  ),
                  // Hidden in front of somebody who has yet to add their first
                  // food, for the same reason the filter chips are: a switch
                  // between two empty halves is clutter, not orientation. It
                  // comes back the moment there is anything to be on one side
                  // of — and it is never hidden while the restaurant side is
                  // the one showing, which would be a scope with no way out.
                  if (anywhere.isNotEmpty ||
                      scope != FoodScope.yours) ...<Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          HearthSpacing.md,
                          gutter,
                          0,
                        ),
                        child: _ScopeSwitch(
                          scope: scope,
                          onChosen: _chooseScope,
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(gutter),
                      child: TextField(
                        controller: _search,
                        // The library filters as you type; the wider search waits
                        // for a pause and lands underneath when it arrives.
                        onChanged: (String value) {
                          ref.read(foodFilterProvider.notifier).search(value);
                          ref.read(foodSearchProvider.notifier).search(value);
                          setState(() {});
                        },
                        style: context.text.body,
                        decoration: InputDecoration(
                          hintText: 'Search foods',
                          prefixIcon: Icon(
                            Icons.search,
                            color: colors.textMuted,
                          ),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _search.clear();
                                    ref
                                        .read(foodFilterProvider.notifier)
                                        .search('');
                                    ref
                                        .read(foodSearchProvider.notifier)
                                        .clear();
                                    setState(() {});
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                  // Hidden while this scope is genuinely empty: chips that can
                  // only ever filter nothing down to nothing are just clutter in
                  // front of someone who has yet to add their first food.
                  if (foods.isNotEmpty) ...<Widget>[
                    SliverToBoxAdapter(child: FoodFilterBar(gutter: gutter)),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: HearthSpacing.md),
                    ),
                  ],
                  // One list for both: what the household has, then what the
                  // wider sources turned up. An empty library is not a dead
                  // end — the search still reaches outward, in either scope.
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      0,
                      gutter,
                      gutter + 72,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(<Widget>[
                        if (foods.isEmpty && _search.text.isEmpty)
                          _EmptyFoods(gutter: gutter, scope: scope)
                        else if (visible.isEmpty)
                          _NoMatches(
                            query: _search.text,
                            gutter: gutter,
                            scope: scope,
                            onAddByHand: _addByHand,
                          )
                        else
                          for (final Food food in visible) ...<Widget>[
                            _DeletableFood(
                              // Keyed by food, not by position: an unkeyed row
                              // hands its swiped-open state to whatever moves up
                              // when the list shifts.
                              key: ValueKey<String>(food.id),
                              food: food,
                              selecting: _selected.isNotEmpty,
                              selected: _selected.contains(food.id),
                              onToggle: _toggle,
                            ),
                            const SizedBox(height: HearthSpacing.sm),
                          ],
                        ExternalFoodResults(query: _search.text, onSaved: null),
                      ]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The library's maintenance, in a labelled menu (review §7.5).
///
/// Seasoning rules used to be a small floating button wearing a sprig of
/// grass, with what it did in a tooltip. It is a list you visit when
/// something is wrong rather than daily, so it belongs behind the
/// conventional overflow — where every row says in words what it opens,
/// instead of asking for a hover the phone cannot give.
class _MaintenanceMenu extends StatelessWidget {
  const _MaintenanceMenu();

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'More',
    onSelected: (String path) => context.push(path),
    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: '/food/seasonings',
        child: Text('Seasonings that need no match', style: context.text.body),
      ),
    ],
  );
}

/// Whose foods the list is showing (review §7.5).
///
/// Both halves are on screen at once and either is one tap away: this is a
/// scope, not a filter. §7.5 is explicit that a seeded catalogue must not be
/// hidden — a chain that disappears reads as a chain that was lost, and the
/// next thing anybody does about that is import it again.
///
/// A [Wrap] rather than a Row: at three times the text two labelled chips are
/// wider than a small phone, and honouring dynamic type means the layout
/// gives way rather than the words (§6.3).
class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({required this.scope, required this.onChosen});

  final FoodScope scope;
  final ValueChanged<FoodScope> onChosen;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: HearthSpacing.sm,
    runSpacing: HearthSpacing.sm,
    children: <Widget>[
      for (final FoodScope option in FoodScope.values)
        _ScopeChip(
          label: option.label,
          icon: option == FoodScope.yours
              ? Icons.home_outlined
              : Icons.storefront_outlined,
          selected: option == scope,
          onTap: () => onChosen(option),
        ),
    ],
  );
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      // Exactly one of these is on at any time, which is what tells a screen
      // reader this is a choice between them rather than two toggles.
      inMutuallyExclusiveGroup: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.accent : colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(
                color: selected ? colors.accent : colors.outline,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: HearthSpacing.md,
              vertical: HearthSpacing.sm,
            ),
            // A floor, never a ceiling: 48 points is the tap target both
            // platform guidelines ask for, and at larger text the chip grows
            // past it rather than clipping the words inside it (§6.3).
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // A lit chip swaps to a filled check, so which scope you are
                // in never rests on the fill colour alone (spec §6.3).
                Icon(
                  selected ? Icons.check : icon,
                  size: 16,
                  color: selected ? colors.onAccent : colors.textSecondary,
                ),
                const SizedBox(width: HearthSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    style: context.text.label.copyWith(
                      color: selected ? colors.onAccent : colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeletableFood extends ConsumerWidget {
  const _DeletableFood({
    required this.food,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final Food food;
  final bool selecting;
  final bool selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Long-press still starts a selection while one is already running: it is
    // just a toggle on an item that happens to be unselected.
    if (selecting) {
      return FoodCard(
        food: food,
        selecting: true,
        selected: selected,
        onTap: () => onToggle(food.id),
        onLongPress: () => onToggle(food.id),
      );
    }
    return SwipeToDelete(
      name: food.name,
      onDelete: () => ref.read(foodRepositoryProvider).delete(food.id),
      onRestore: () => ref.read(foodRepositoryProvider).restore(food.id),
      child: FoodCard(food: food, onLongPress: () => onToggle(food.id)),
    );
  }
}

/// One food in the library list.
class FoodCard extends StatelessWidget {
  const FoodCard({
    required this.food,
    this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    super.key,
  });

  final Food food;

  /// Overrides the default tap-to-open, for a screen that has long-pressed
  /// its way into picking foods instead of reading one.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether a batch of these is being picked right now, and whether this one
  /// is in it. [selecting] is a property of the *screen*; every card on it
  /// gets it, not just the one that was long-pressed.
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final ServingOption? serving = food.defaultServing;
    final bool highlighted = selecting && selected;
    final VoidCallback open = onTap ?? () => context.push('/food/${food.id}');

    return Semantics(
      button: true,
      selected: selecting ? selected : null,
      label: selecting
          ? '${food.name}. ${selected ? 'Selected' : 'Not selected'}.'
          : '${food.name}. ${_summary(food)}',
      onTap: open,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: Material(
        color: highlighted ? colors.surfaceSunken : colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: open,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(
                color: highlighted ? colors.outlineStrong : colors.outline,
              ),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              children: <Widget>[
                if (selecting) ...<Widget>[
                  // Never colour alone (§6.3): the icon itself, not just the
                  // row's tint, carries whether this one is picked.
                  Icon(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: selected ? colors.accent : colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          // Icon and word together, never colour alone
                          // (§6.3) — and in front of the name, because
                          // "which of these did I choose" is what the eye is
                          // scanning this column for.
                          if (food.isDefault) ...<Widget>[
                            Icon(
                              Icons.push_pin,
                              size: 14,
                              color: colors.accent,
                            ),
                            const SizedBox(width: HearthSpacing.xxs),
                          ],
                          Flexible(
                            child: Text(
                              food.brand == null
                                  ? food.name
                                  : '${food.name}  ·  ${food.brand}',
                              style: text.ingredient,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: HearthSpacing.xxs),
                      Text(
                        _summary(food),
                        style: text.metadata.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (serving != null)
                  Text(
                    '${serving.macros.kcal.round()} kcal',
                    style: text.ingredient.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _summary(Food food) {
    final ServingOption? serving = food.defaultServing;
    if (serving == null) {
      return food.isDefault
          ? 'Default  ·  no serving size yet'
          : 'No serving size yet';
    }
    final String portion = QuantityFormat.formatAsAuthored(serving.amount);
    return '${food.isDefault ? 'Default  ·  ' : ''}per $portion  ·  '
        'P ${serving.macros.proteinG.round()}  '
        'C ${serving.macros.carbG.round()}  '
        'F ${serving.macros.fatG.round()}';
  }
}

class _EmptyFoods extends StatelessWidget {
  const _EmptyFoods({required this.gutter, required this.scope});

  final double gutter;
  final FoodScope scope;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool yours = scope == FoodScope.yours;
    return CentredMessage(
      gutter: gutter,
      children: <Widget>[
        Text(
          yours ? 'No foods yet' : 'No restaurant menus yet',
          style: context.text.sectionHeader,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          // The empty half of a scope has to say why it is empty, or it
          // reads as the list having lost something.
          yours
              ? 'Scan a packet, or add the things you eat often by hand.'
              : 'A menu arrives with a restaurant, from Eat out in Recipes.',
          style: context.text.body.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({
    required this.query,
    required this.gutter,
    required this.scope,
    required this.onAddByHand,
  });

  final String query;
  final double gutter;
  final FoodScope scope;
  final VoidCallback onAddByHand;

  @override
  Widget build(BuildContext context) {
    final bool yours = scope == FoodScope.yours;
    return CentredMessage(
      gutter: gutter,
      children: <Widget>[
        // "Nothing matches" while five results sit underneath reads as a
        // broken screen. This message is only ever about the half of the
        // library you are looking at, so it says which half.
        Text(
          yours
              ? 'None of your foods match "$query"'
              : 'Nothing on the restaurant menus matches "$query"',
          style: context.text.body,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: HearthSpacing.sm),
        // Offered in either scope. A food typed in from the menus is one of
        // your own, so the switch moves to meet it — the same answer the
        // floating button gives, rather than a second rule for the same door.
        TextButton(
          onPressed: onAddByHand,
          child: const Text('Add it as a new food'),
        ),
      ],
    );
  }
}
