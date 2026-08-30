import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/swipe_to_delete.dart';
import '../../app/widgets/undo_snackbar.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/text/text_normaliser.dart';
import 'external_food_results.dart';
import 'food_search_controller.dart';

/// The household food library (spec §5.5).
///
/// Search filters the already-loaded list rather than round-tripping the
/// database, because finding a food is on the daily logging path and every
/// extra tap or wait is paid three times a day. Open Food Facts and USDA are
/// searched too, but underneath and on their own schedule — the local list
/// must never wait on a network call to appear.
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

  List<Food> _filter(List<Food> foods) {
    final String needle = normaliseKey(_search.text);
    if (needle.isEmpty) return foods;
    return foods
        .where(
          (Food food) =>
              normaliseKey(food.name).contains(needle) ||
              normaliseKey(food.brand ?? '').contains(needle),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final AsyncValue<List<Food>> library = ref.watch(foodLibraryProvider);
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return Scaffold(
      backgroundColor: colors.background,
      // Scanning leads because it is the faster path for anything with a
      // packet, and typing a food in by hand is what §5.5 falls back to — not
      // the other way round. Both stay one tap.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.small(
            heroTag: 'food-new',
            onPressed: () => context.push('/food/new'),
            backgroundColor: colors.surfaceElevated,
            foregroundColor: colors.textPrimary,
            tooltip: 'Add a food by hand',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: HearthSpacing.sm),
          FloatingActionButton.extended(
            heroTag: 'food-scan',
            onPressed: () => context.push('/food/scan'),
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text('Scan', style: context.text.label),
          ),
        ],
      ),
      body: SafeArea(
        child: library.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stack) => Center(
            child: Text('The food library could not be read.\n$error'),
          ),
          data: (List<Food> foods) {
            final List<Food> visible = _filter(foods);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                  child: _selected.isEmpty
                      ? Text('Foods', style: context.text.recipeTitle)
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
                                  'Delete ${_selected.length} selected foods',
                              color: colors.error,
                              onPressed: _deleteSelected,
                            ),
                          ],
                        ),
                ),
                Padding(
                  padding: EdgeInsets.all(gutter),
                  child: TextField(
                    controller: _search,
                    // The library filters as you type; the wider search waits
                    // for a pause and lands underneath when it arrives.
                    onChanged: (String value) {
                      ref.read(foodSearchProvider.notifier).search(value);
                      setState(() {});
                    },
                    style: context.text.body,
                    decoration: InputDecoration(
                      hintText: 'Search foods',
                      prefixIcon: Icon(Icons.search, color: colors.textMuted),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear search',
                              onPressed: () {
                                _search.clear();
                                ref.read(foodSearchProvider.notifier).clear();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  // One scroll view for both: what the household has, then
                  // what the wider sources turned up. An empty library is no
                  // longer a dead end — the search still reaches outward.
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      0,
                      gutter,
                      gutter + 72,
                    ),
                    children: <Widget>[
                      if (foods.isEmpty && _search.text.isEmpty)
                        _EmptyFoods(gutter: gutter)
                      else if (visible.isEmpty)
                        _NoMatches(query: _search.text, gutter: gutter)
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
                    ],
                  ),
                ),
              ],
            );
          },
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
                      Text(
                        food.brand == null
                            ? food.name
                            : '${food.name}  ·  ${food.brand}',
                        style: text.ingredient,
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
    if (serving == null) return 'No serving size yet';
    final String portion = QuantityFormat.formatAsAuthored(serving.amount);
    return 'per $portion  ·  '
        'P ${serving.macros.proteinG.round()}  '
        'C ${serving.macros.carbG.round()}  '
        'F ${serving.macros.fatG.round()}';
  }
}

class _EmptyFoods extends StatelessWidget {
  const _EmptyFoods({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: EdgeInsets.all(gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'No foods yet',
                style: context.text.sectionHeader,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                'Scan a packet, or add the things you eat often by hand.',
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.gutter});

  final String query;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // "Nothing matches" while five results sit underneath reads as a
            // broken screen. This message is only ever about the household's
            // own foods, so it says so.
            Text(
              'None of your foods match "$query"',
              style: context.text.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HearthSpacing.sm),
            TextButton(
              onPressed: () => context.push('/food/new'),
              child: const Text('Add it as a new food'),
            ),
          ],
        ),
      ),
    );
  }
}
