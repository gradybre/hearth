import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/reading_column.dart';
import '../../app/widgets/swipe_to_delete.dart';
import '../../app/widgets/undo_snackbar.dart';
import '../../data/local/shopping_store.dart';
import '../../data/repositories/shopping_repository.dart';
import '../../domain/foods/no_match_rule.dart';
import '../../domain/format/food_quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/shopping/pack_display.dart';
import '../../domain/shopping/shopping_contribution.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/shopping/shopping_list_builder.dart';
import '../../domain/shopping/shopping_sources.dart';
import '../../domain/units/quantity.dart';
import 'add_to_list_sheet.dart';
import 'grocery_clarity_view.dart';
import 'shopping_amount_sheet.dart';
import 'shopping_chat_controller.dart';
import 'shopping_export_sheet.dart';

/// The shopping list (spec §5.7).
///
/// Filled by adding recipes and foods to it, and owned from there on by
/// whoever is shopping. External shopping handoffs open the export review
/// before the user chooses where to send the list (rule 4).
///
/// Building the whole thing from a stretch of the plan is still here, and it
/// is still the fastest way to shop for a planned week — but it is one way to
/// fill the list rather than what the list *is*, which is why it lives behind
/// `Manage list` with the dates it covers. The list itself is no longer
/// pinned to a range: a recipe somebody adds on Saturday belongs to no week.
class ShoppingScreen extends ConsumerWidget {
  const ShoppingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final AsyncValue<ShoppingListSnapshot?> list = ref.watch(
      shoppingListProvider,
    );
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    return ScaffoldMessenger(
      child: ColoredBox(
        color: colors.background,
        child: SafeArea(
          child: ReadingColumn(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace s) =>
                  Center(child: Text('The list could not be read.\n$e')),
              data: (ShoppingListSnapshot? snapshot) => _Body(
                lines: snapshot?.lines ?? const <ShoppingLine>[],
                gutter: gutter,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.lines, required this.gutter});

  final List<ShoppingLine> lines;
  final double gutter;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  List<ShoppingLine> get lines => widget.lines;
  double get gutter => widget.gutter;
  bool _showAll = false;
  final Set<int> _pointers = <int>{};
  List<ShoppingLine>? _heldLines;
  Map<String, Food>? _heldFoods;
  List<String>? _dragKeys;
  int? _dragFrom;
  final Map<String, ShoppingLine> _removedLines = <String, ShoppingLine>{};

  /// Holding a row freezes its presentation, never the fact an action edits.
  ShoppingLine? _currentLine(String key) {
    for (final ShoppingLine line in lines) {
      if (line.key == key) return line;
    }
    return null;
  }

  Food? _currentFood(ShoppingLine line) {
    for (final Food food
        in ref.read(foodLibraryProvider).value ?? const <Food>[]) {
      if (food.id == line.foodId) return food;
    }
    return null;
  }

  void _hold() {
    _heldLines ??= lines;
    _heldFoods ??= <String, Food>{
      for (final Food food
          in ref.read(foodLibraryProvider).value ?? const <Food>[])
        food.id: food,
    };
  }

  void _release() {
    // Pointer-up precedes the tap callback. Reconcile after that event so
    // neither a partner update nor our own tick moves a row under a finger.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pointers.isNotEmpty || _dragKeys != null) return;
      setState(() {
        _heldLines = null;
        _heldFoods = null;
      });
    });
  }

  /// Rebuilds from the plan, merging over what is already here.
  Future<void> _rebuild(BuildContext context, WidgetRef ref) async {
    final ({DateTime from, DateTime to}) range = ref.read(
      shoppingRangeProvider,
    );
    final Map<DateTime, List<MealPlanEntry>> plan =
        await ref.read(shoppingPlanProvider.future) ??
        const <DateTime, List<MealPlanEntry>>{};

    await ref
        .read(shoppingRepositoryProvider)
        .rebuild(
          from: range.from,
          to: range.to,
          entriesByDay: plan,
          recipes: <String, Recipe>{
            for (final Recipe r
                in ref.read(recipeLibraryProvider).value ?? const <Recipe>[])
              r.id: r,
          },
          foods: <String, Food>{
            for (final Food f
                in ref.read(foodLibraryProvider).value ?? const <Food>[])
              f.id: f,
          },
          seasonings: ref.read(noMatchRulesProvider).value ?? NoMatchRules.none,
          includeSeasonings: ref.read(shoppingSeasoningsProvider),
        );
    ref.invalidate(shoppingListProvider);
  }

  Future<void> _save(WidgetRef ref, List<ShoppingLine> next) async {
    await ref.read(shoppingRepositoryProvider).replace(next);
    ref.invalidate(shoppingListProvider);
  }

  List<ShoppingLine> _replacing(ShoppingLine line) => <ShoppingLine>[
    for (final ShoppingLine other in lines)
      if (other.key == line.key) line else other,
  ];

  @override
  Widget build(BuildContext context) {
    // The assistant used to remain mounted below the list. Keep its session
    // alive while this screen is open so dismissing the new sheet during a
    // request neither discards the answer nor disposes the controller's ref.
    if (ref.watch(shoppingAssistantProvider) != null) {
      ref.watch(shoppingChatProvider);
    }
    final Map<String, Food> currentFoods = <String, Food>{
      for (final Food food
          in ref.watch(foodLibraryProvider).value ?? const <Food>[])
        food.id: food,
    };
    final Map<String, Food> foods = _heldFoods ?? currentFoods;
    final List<ShoppingLine> displayed = _heldLines ?? lines;
    final Map<GroceryLineState, int> counts = <GroceryLineState, int>{
      for (final GroceryLineState state in GroceryLineState.values) state: 0,
    };
    final Map<String, List<ShoppingLine>> groups =
        <String, List<ShoppingLine>>{};
    for (final ShoppingLine line in displayed) {
      final GroceryLineState state = groceryLineState(
        line,
        food: foods[line.foodId],
      );
      counts[state] = counts[state]! + 1;
      if (_showAll || state == GroceryLineState.remaining) {
        groups
            .putIfAbsent(line.storeTag ?? '', () => <ShoppingLine>[])
            .add(line);
      }
    }
    final List<String> stores = groups.keys.toList()
      ..sort((String a, String b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });

    final Widget actions = _ActionBar(
      onAdd: () => _add(context, ref),
      onMore: () => _more(context),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // Keep actual groceries in the initial viewport. At larger text or
        // short heights the same actions flow with the list and can grow.
        final bool inlineActions =
            MediaQuery.textScalerOf(context).scale(14) > 21 ||
            box.maxHeight < 360;
        return Listener(
          onPointerDown: (PointerDownEvent event) {
            _pointers.add(event.pointer);
            _hold();
          },
          onPointerUp: (PointerUpEvent event) {
            _pointers.remove(event.pointer);
            _release();
          },
          onPointerCancel: (PointerCancelEvent event) {
            _pointers.remove(event.pointer);
            _dragKeys = null;
            _release();
          },
          child: Scaffold(
            backgroundColor: context.colors.background,
            body: ListView(
              key: const ValueKey<String>('grocery-list-scroll'),
              padding: EdgeInsets.all(gutter),
              children: <Widget>[
                if (displayed.isEmpty) ...<Widget>[
                  _StartCard(
                    onAdd: () => _add(context, ref),
                    onBuild: () => _manage(context, ref),
                    onMore: () => _more(context),
                  ),
                  const SizedBox(height: HearthSpacing.lg),
                  const _Empty(),
                ] else ...<Widget>[
                  _ListHeader(
                    showAll: _showAll,
                    remaining: counts[GroceryLineState.remaining]!,
                    total: displayed.length,
                    onChanged: (bool value) => setState(() => _showAll = value),
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                  if (stores.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: HearthSpacing.lg,
                      ),
                      child: Text(
                        'Nothing left to buy.',
                        style: context.text.sectionHeader,
                      ),
                    ),
                  for (final String store in stores) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
                      child: Text(
                        store.isEmpty ? 'Anywhere' : store,
                        style: context.text.sectionHeader,
                      ),
                    ),
                    _StoreGroup(
                      lines: groups[store]!,
                      foods: foods,
                      onReorderStart: (int from) {
                        _hold();
                        _dragFrom = from;
                        _dragKeys = groups[store]!
                            .map((ShoppingLine line) => line.key)
                            .toList();
                      },
                      onReorderEnd: (int to) {
                        if (to == _dragFrom || to == (_dragFrom ?? -2) + 1) {
                          _dragKeys = null;
                          _release();
                        }
                      },
                      onReorder: (int from, int to) =>
                          _reorder(store, groups[store]!, from, to),
                      onTick: (ShoppingLine line, bool value) =>
                          _tick(line.key, value),
                      onEdit: (ShoppingLine line) =>
                          _edit(context, ref, line.key),
                      onRemove: (ShoppingLine line) => _remove(ref, line.key),
                      onRestore: (ShoppingLine line) => _restore(ref, line.key),
                    ),
                    const SizedBox(height: HearthSpacing.md),
                  ],
                  _ResolvedCounts(counts: counts),
                  if (inlineActions) ...<Widget>[
                    const SizedBox(height: HearthSpacing.md),
                    actions,
                  ],
                ],
              ],
            ),
            bottomNavigationBar: displayed.isNotEmpty && !inlineActions
                ? actions
                : null,
          ),
        );
      },
    );
  }

  Future<void> _tick(String key, bool value) async {
    final ShoppingLine? line = _currentLine(key);
    if (line == null) return;
    final Food? food = _currentFood(line);
    // The resolver may have established coverage through a known package
    // relationship. Unticking that row must clear the stored cupboard fact,
    // too, even when its stored unit differs from the needed unit.
    final ShoppingLine changed =
        !value &&
            groceryLineState(line.copyWith(checked: false), food: food) ==
                GroceryLineState.atHome
        ? line.copyWith(checked: false, clearOnHand: true)
        : line.ticked(value);
    await _save(ref, _replacing(changed));
  }

  Future<void> _reorder(
    String store,
    List<ShoppingLine> visible,
    int from,
    int to,
  ) async {
    final List<String> order = <String>[
      ...?_dragKeys,
      if (_dragKeys == null) ...visible.map((ShoppingLine line) => line.key),
    ];
    order.insert(to, order.removeAt(from));
    final ShoppingRepository repository = ref.read(shoppingRepositoryProvider);
    final List<ShoppingLine> now =
        (await repository.current())?.lines ?? const <ShoppingLine>[];
    await _save(
      ref,
      reorderGroceryLines(lines: now, store: store, visibleOrder: order),
    );
    _dragKeys = null;
    _release();
  }

  Future<void> _more(BuildContext context) async {
    final _MoreAction? action = await showModalBottomSheet<_MoreAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (BuildContext sheet) => _MoreSheet(
        hasItems: lines.isNotEmpty,
        hasAssistant: ref.read(shoppingAssistantProvider) != null,
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case _MoreAction.export:
        await showShoppingExportSheet(
          context,
          lines,
          foods: <String, Food>{
            for (final Food food
                in ref.read(foodLibraryProvider).value ?? const <Food>[])
              food.id: food,
          },
        );
      case _MoreAction.manage:
        await _manage(context, ref);
      case _MoreAction.clear:
        await _clear(context, ref);
      case _MoreAction.assistant:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: context.colors.background,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          builder: (BuildContext sheet) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheet).bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(HearthSpacing.lg),
                child: Consumer(
                  builder:
                      (
                        BuildContext context,
                        WidgetRef sheetRef,
                        Widget? child,
                      ) => _ChatCard(
                        lines:
                            sheetRef.watch(shoppingListProvider).value?.lines ??
                            const <ShoppingLine>[],
                        onApply: (List<ShoppingLine> next) => _save(ref, next),
                      ),
                ),
              ),
            ),
          ),
        );
      case null:
        break;
    }
  }

  /// Takes a line off the list.
  ///
  /// The snackbar and its undo belong to [SwipeToDelete], which every other
  /// list in Hearth uses — one place for how long the window is and for the
  /// fact that tapping Undo dismisses it immediately.
  Future<void> _remove(WidgetRef ref, String key) async {
    final ShoppingLine? removed = _currentLine(key);
    _removedLines.remove(key);
    if (removed == null) return;
    await _save(ref, <ShoppingLine>[
      for (final ShoppingLine other in lines)
        if (other.key != key) other,
    ]);
    // SwipeToDelete retains the row it drew for its Undo callback. Remember
    // what this action actually removed so a held display cannot restore an
    // older amount over a partner's update received before deletion.
    _removedLines[key] = removed;
  }

  /// Puts a removed line back where it was.
  ///
  /// The one line, spliced into the list as it stands when Undo is tapped —
  /// not the list as it stood before the deletion. Whatever happened in
  /// between is somebody's more recent decision and stays (spec §5.7); the
  /// repository owns that, because it is the only thing here that can read
  /// what the list is *now* rather than what this screen last drew.
  Future<void> _restore(WidgetRef ref, String key) async {
    final ShoppingLine? removed = _removedLines.remove(key);
    if (removed == null) return;
    await ref.read(shoppingRepositoryProvider).restoreLine(removed);
    ref.invalidate(shoppingListProvider);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, String key) async {
    final ShoppingLine? line = _currentLine(key);
    if (line == null) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ShoppingLine? changed = await showShoppingAmountSheet(
      context,
      line,
      food: _currentFood(line),
      onRemove: () async {
        await _remove(ref, key);
        final ShoppingLine? removed = _removedLines[key];
        if (removed == null) return;
        showUndoSnackBar(
          messenger,
          message: 'Deleted ${removed.name}',
          onUndo: () => _restore(ref, key),
        );
      },
    );
    if (changed != null) await _save(ref, _replacing(changed));
  }

  /// Everything you do to the list as a whole, on a sheet you open when you
  /// are preparing rather than shopping (review §6.2.5).
  ///
  /// What is on it, where it came from, and the build from the plan with the
  /// days it covers. None of that belongs on the screen you stand in a shop
  /// holding.
  Future<void> _manage(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.background,
      isScrollControlled: true,
      // Capped like every other sheet here, so a tall one at large text
      // scrolls rather than overflowing, and tapping above still dismisses.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (BuildContext sheet) => _ManageSheet(
        onRebuild: () {
          Navigator.of(sheet).pop();
          _rebuild(context, ref);
        },
        onRemoveSource: (String key) => _removeSource(ref, key),
      ),
    );
  }

  /// Puts a recipe, a food or a typed-in item on the list (spec §5.7).
  ///
  /// The primary action, and the one that replaced a name-only dialog: a list
  /// is filled by saying what you are going to cook, not by transcribing its
  /// ingredients yourself.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final List<Food> foods =
        ref.read(foodLibraryProvider).value ?? const <Food>[];
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final ListAddition? addition = await showAddToListSheet(
      context,
      recipes: ref.read(recipeLibraryProvider).value ?? const <Recipe>[],
      foods: foods,
    );
    if (addition == null) return;

    final ShoppingRepository repository = ref.read(shoppingRepositoryProvider);
    switch (addition) {
      case RecipeAddition(:final Recipe recipe, :final double servings):
        await repository.addRecipe(
          recipe: recipe,
          servings: servings,
          // Read for one thing: which shop each line belongs to.
          foods: <String, Food>{for (final Food f in foods) f.id: f},
        );
      case FoodAddition(:final Food food, :final double servings):
        await repository.addFood(food: food, servings: servings);
      case PlainAddition(:final String name):
        // Re-read rather than added to what this screen last drew. The other
        // two cases go through the repository, which reads the list itself;
        // this one writes the whole list back, and the snapshot it was
        // holding was taken before a sheet somebody spent seconds in. An item
        // added by hand meanwhile, or a change arrived from the other phone,
        // would be written out of existence — the same reason `restoreLine`
        // and the cleared-list undo both re-read.
        final List<ShoppingLine> now =
            (await repository.current())?.lines ?? const <ShoppingLine>[];
        final String key = ShoppingListBuilder.keyFor(name: name);
        // Already there is not a failure, but it is invisible — the list
        // simply does not change, which looks exactly like a button that did
        // nothing. Said, rather than left to be guessed at.
        if (now.any((ShoppingLine l) => l.key == key)) {
          messenger.showSnackBar(
            SnackBar(content: Text('$name is already on the list.')),
          );
          return;
        }
        await repository.replace(<ShoppingLine>[
          ...now,
          ShoppingLine.manual(key: key, name: name, sortOrder: now.length),
        ]);
    }
    ref.invalidate(shoppingListProvider);
  }

  /// Takes one recipe, food or plan build back off the list.
  ///
  /// No undo, unlike a deleted line: what puts it back is adding it again,
  /// which is the same two taps that put it there in the first place — and
  /// anything ticked or edited survives the removal anyway, so there is less
  /// to lose than the word "remove" suggests (see `removeSource`).
  Future<void> _removeSource(WidgetRef ref, String sourceKey) async {
    await ref.read(shoppingRepositoryProvider).removeSource(sourceKey);
    ref.invalidate(shoppingListProvider);
  }

  /// Empties the list, having asked first (spec §5.7).
  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final List<ShoppingLine> was = lines;

    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialog) => AlertDialog(
            // Scrollable, which is what keeps a dialog usable at three times
            // the text rather than clipping its own buttons (§6.3).
            scrollable: true,
            title: const Text('Clear the list?'),
            content: Text(
              was.length == 1
                  ? 'The one item on it goes.'
                  : 'All ${was.length} items go, including the ones you have '
                        'already ticked off.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: const Text('Keep it'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: const Text('Clear it'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await _save(ref, const <ShoppingLine>[]);
    showUndoSnackBar(
      messenger,
      message: was.length == 1 ? 'List cleared' : 'Cleared ${was.length} items',
      onUndo: () => _restoreCleared(ref, was),
    );
  }

  /// Puts a cleared list back, onto the list as it stands *now*.
  ///
  /// [ShoppingRepository.restoreLine] is the shipped undo and it restores one
  /// line; a cleared list is every line, and calling it once each would
  /// rewrite and re-queue the whole list once per line — quadratic, on the
  /// one path where the list is at its longest. So the same rule is applied
  /// in a single write: anything standing on the list when Undo is tapped is
  /// somebody's newer decision and wins by key, and only what is still
  /// missing goes back. Position survives because `sortOrder` is what the
  /// display order is made of, so the lines return to where they were walked
  /// to rather than to the bottom of the shop.
  ///
  /// The list is re-read here rather than taken from what this screen last
  /// drew, for the reason `restoreLine` gives: between the clear and the Undo
  /// an item can be added by hand, and a change can arrive from the other
  /// phone.
  Future<void> _restoreCleared(
    WidgetRef ref,
    List<ShoppingLine> cleared,
  ) async {
    final ShoppingRepository repository = ref.read(shoppingRepositoryProvider);
    final List<ShoppingLine> now =
        (await repository.current())?.lines ?? const <ShoppingLine>[];
    final Set<String> standing = <String>{
      for (final ShoppingLine line in now) line.key,
    };

    await repository.replace(<ShoppingLine>[
      ...now,
      for (final ShoppingLine line in cleared)
        if (!standing.contains(line.key)) line,
    ]);
    ref.invalidate(shoppingListProvider);
  }
}

/// The list as a whole: what put it there, and how to build it from the plan.
///
/// Clearing lives under More, separate from these source and build controls.
class _ManageSheet extends ConsumerWidget {
  const _ManageSheet({required this.onRebuild, required this.onRemoveSource});

  final VoidCallback onRebuild;
  final ValueChanged<String> onRemoveSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final ({DateTime from, DateTime to}) range = ref.watch(
      shoppingRangeProvider,
    );
    final bool seasonings = ref.watch(shoppingSeasoningsProvider);

    // Watched rather than handed in: taking two recipes off in a row is one
    // visit to this sheet, and a list passed down at build time would go on
    // offering the first one after it was gone.
    final List<ShoppingLine> lines =
        ref.watch(shoppingListProvider).value?.lines ?? const <ShoppingLine>[];
    final List<ShoppingSource> sources = ShoppingSources.of(lines);

    return SafeArea(
      // A scroll view over a column, not a lazy list: every control on this
      // sheet is one an accessibility sweep has to be able to find, and a
      // lazy list does not build what is off the bottom — a destructive
      // button nothing can reach is a destructive button nothing has
      // checked. There are a handful of sources at most, so nothing is paid
      // for building them all.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Manage list', style: context.text.sectionHeader),
            if (sources.isNotEmpty) ...<Widget>[
              const SizedBox(height: HearthSpacing.lg),
              Text('What is on it', style: context.text.label),
              const SizedBox(height: HearthSpacing.xs),
              for (final ShoppingSource source in sources)
                _SourceRow(
                  source: source,
                  onRemove: () => onRemoveSource(source.key),
                ),
            ],
            const SizedBox(height: HearthSpacing.lg),
            // The dates belong to the build, not to the list. A list is a list
            // of things to buy; only *this* control has anything to say about
            // which days are being shopped for, so the range lives beside it
            // rather than in a header over lines it no longer describes.
            Text('From the meal plan', style: context.text.label),
            const SizedBox(height: HearthSpacing.xs),
            MergeSemantics(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${shortDate(range.from)} – ${shortDate(range.to)}',
                      style: context.text.body,
                    ),
                  ),
                  // "Change", not "Change the days": at three times the text
                  // on a 320-point phone the longer label and the dates
                  // beside it overflow the row by 37 points, and the heading
                  // above already says what these dates are.
                  TextButton(
                    onPressed: () => _pickRange(context, ref, range),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HearthSpacing.sm),
            // Merged, so a screen reader says "Include seasonings, switch,
            // off" rather than reading a label and a control separately.
            MergeSemantics(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Include seasonings', style: context.text.body),
                  ),
                  Switch(
                    value: seasonings,
                    onChanged: (bool _) =>
                        ref.read(shoppingSeasoningsProvider.notifier).toggle(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HearthSpacing.md),
            FilledButton(
              onPressed: onRebuild,
              child: const Text('Build from the plan'),
            ),
            const SizedBox(height: HearthSpacing.sm),
            Text(
              'Replaces what the plan put here. Anything you added or ticked '
              'by hand stays.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange(
    BuildContext context,
    WidgetRef ref,
    ({DateTime from, DateTime to}) range,
  ) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: range.from, end: range.to),
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
      helpText: 'What are you shopping for?',
    );
    if (picked == null) return;
    ref
        .read(shoppingRangeProvider.notifier)
        .set(from: picked.start, to: picked.end);
  }
}

/// One recipe, food or plan build, and the button that takes it back off.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.onRemove});

  final ShoppingSource source;
  final VoidCallback onRemove;

  /// What it is asking for, in words.
  String get _detail {
    final List<String> parts = <String>[
      if (source.servings case final double servings)
        '${_number(servings)} ${servings == 1 ? 'serving' : 'servings'}',
      '${source.lines} ${source.lines == 1 ? 'line' : 'lines'}',
    ];
    return parts.join(' · ');
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Semantics(
      // Assembled by hand so a screen reader hears one thing with one action
      // on it, rather than a name, a count and a button in three parts.
      label: '${source.label}, $_detail',
      excludeSemantics: true,
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: 'Take ${source.label} off the list'):
            onRemove,
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
        child: Row(
          children: <Widget>[
            Icon(
              switch (source.kind) {
                ShoppingSourceKind.plan => Icons.calendar_today_outlined,
                ShoppingSourceKind.food => Icons.egg_outlined,
                _ => Icons.menu_book_outlined,
              },
              size: 18,
              color: colors.textMuted,
            ),
            const SizedBox(width: HearthSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(source.label, style: context.text.body),
                  Text(
                    _detail,
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: HearthSpacing.sm),
            TextButton(onPressed: onRemove, child: const Text('Take off')),
          ],
        ),
      ),
    );
  }
}

/// Only the active view and its count precede the groceries.
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.showAll,
    required this.remaining,
    required this.total,
    required this.onChanged,
  });
  final bool showAll;
  final int remaining;
  final int total;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Wrap(
        spacing: HearthSpacing.sm,
        runSpacing: HearthSpacing.xs,
        children: <Widget>[
          for (final bool all in <bool>[false, true])
            Semantics(
              selected: showAll == all,
              child: TextButton(
                onPressed: () => onChanged(all),
                style: TextButton.styleFrom(
                  foregroundColor: showAll == all
                      ? context.colors.textPrimary
                      : null,
                  backgroundColor: showAll == all
                      ? context.colors.surfaceSunken
                      : null,
                  side: showAll == all
                      ? BorderSide(color: context.colors.accent)
                      : null,
                ),
                child: Text(all ? 'All' : 'Remaining'),
              ),
            ),
        ],
      ),
      Text(
        showAll
            ? '$total ${total == 1 ? 'item' : 'items'}'
            : '$remaining left to buy',
        style: context.text.metadata.copyWith(color: context.colors.textMuted),
      ),
    ],
  );
}

class _ResolvedCounts extends StatelessWidget {
  const _ResolvedCounts({required this.counts});
  final Map<GroceryLineState, int> counts;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: HearthSpacing.lg,
    runSpacing: HearthSpacing.xs,
    children: <Widget>[
      Text(
        'Bought ${counts[GroceryLineState.bought]}',
        style: context.text.metadata,
      ),
      Text(
        'At home ${counts[GroceryLineState.atHome]}',
        style: context.text.metadata,
      ),
      if (counts[GroceryLineState.notNeeded]! > 0)
        Text(
          'Not needed ${counts[GroceryLineState.notNeeded]}',
          style: context.text.metadata,
        ),
    ],
  );
}

/// The frequent action stays at thumb height when there is room.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onAdd, required this.onMore});
  final VoidCallback onAdd;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surfaceElevated,
      border: Border(top: BorderSide(color: context.colors.outline)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(HearthSpacing.sm),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final Widget add = FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add item'),
          );
          final Widget more = OutlinedButton(
            onPressed: onMore,
            style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
            child: const Text('More'),
          );
          if (box.maxWidth < MediaQuery.textScalerOf(context).scale(14) * 16) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                add,
                const SizedBox(height: HearthSpacing.xs),
                more,
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: add),
              const SizedBox(width: HearthSpacing.sm),
              more,
            ],
          );
        },
      ),
    ),
  );
}

enum _MoreAction { export, manage, assistant, clear }

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.hasItems, required this.hasAssistant});
  final bool hasItems;
  final bool hasAssistant;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(HearthSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('More', style: context.text.sectionHeader),
          const SizedBox(height: HearthSpacing.sm),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(_MoreAction.export),
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Share or export'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(_MoreAction.manage),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Manage list'),
          ),
          if (hasAssistant)
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(_MoreAction.assistant),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Ask for a change'),
            ),
          ExpansionTile(
            title: const Text('List help'),
            tilePadding: EdgeInsets.zero,
            children: <Widget>[
              Text(
                'Tap an item when bought. Tap its amount to set total needed or what you have at home. '
                'Hold and drag to change the order; swipe to reveal Delete. '
                'All shows bought, at-home and not-needed items. Share or export opens a review before anything leaves Hearth.',
                style: context.text.body,
              ),
            ],
          ),
          if (hasItems) ...<Widget>[
            const SizedBox(height: HearthSpacing.lg),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(_MoreAction.clear),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear the list'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The two ways to fill an empty list.
///
/// This was the range card: a date picker set in a title face, a seasonings
/// switch, a Build button, and adding by hand demoted to a bare `+`. All of
/// that was setup for one way of filling a list, sitting above the list on
/// every visit. The range and the switch went with the build they belong to
/// (see [_ManageSheet]); what is left is the choice itself, which is the only
/// thing an empty list actually asks.
class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.onAdd,
    required this.onBuild,
    required this.onMore,
  });

  final VoidCallback onAdd;

  /// Opens the manage sheet rather than building. A build is over a stretch
  /// of days, and the days are the first thing you would want to see.
  final VoidCallback onBuild;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // A minimum rather than a fixed height, so the label grows with
            // the type instead of being clipped by it (spec §6.3).
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: HearthTouch.minTarget,
              ),
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add item'),
              ),
            ),
            const SizedBox(height: HearthSpacing.xs),
            // Short on purpose. Every line of explanation here is a line
            // between the two buttons, and at three times the text that is
            // what decides whether the second one is on the screen at all.
            Text(
              'A recipe, a food, or anything else.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: HearthSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: HearthTouch.minTarget,
              ),
              child: OutlinedButton.icon(
                onPressed: onBuild,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: const Text('Build from the plan'),
              ),
            ),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'Everything planned over a stretch of days.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: HearthSpacing.sm),
            TextButton(onPressed: onMore, child: const Text('More')),
          ],
        ),
      ),
    );
  }
}

/// One store's lines, in the order you walk them.
class _StoreGroup extends StatelessWidget {
  const _StoreGroup({
    required this.lines,
    required this.foods,
    required this.onReorder,
    required this.onReorderStart,
    required this.onReorderEnd,
    required this.onTick,
    required this.onEdit,
    required this.onRemove,
    required this.onRestore,
  });

  final List<ShoppingLine> lines;

  /// The library by food id, for the lines that are matched to one.
  final Map<String, Food> foods;

  /// Wired to `onReorderItem`, which hands over the index the item should end
  /// up at — the older `onReorder` reported it as it would be before the item
  /// was taken out, and left every caller to subtract one.
  final void Function(int from, int to) onReorder;
  final ValueChanged<int> onReorderStart;
  final ValueChanged<int> onReorderEnd;
  final void Function(ShoppingLine line, bool value) onTick;
  final ValueChanged<ShoppingLine> onEdit;
  final Future<void> Function(ShoppingLine line) onRemove;

  /// Puts back what [onRemove] took, at the position it was in.
  final Future<void> Function(ShoppingLine line) onRestore;

  @override
  Widget build(BuildContext context) {
    // A drag here, where the recipe editor's sections deliberately use move
    // buttons instead. Its objections were that long-press-to-drag fights text
    // selection in a list of text fields, and that a drag cannot be reached by
    // a screen reader. Neither holds: no text fields, and ReorderableListView
    // attaches its own "Move up / Move down / Move to start" semantics
    // actions.
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      itemCount: lines.length,
      onReorderItem: onReorder,
      onReorderStart: onReorderStart,
      onReorderEnd: onReorderEnd,
      itemBuilder: (BuildContext context, int index) {
        final ShoppingLine line = lines[index];
        // The key belongs to the outermost widget, which the reorder needs
        // to identify the item and the swipe needs to keep its open state
        // with the right row when the list shifts.
        //
        // `SwipeToDelete` rather than a bespoke Dismissible: it is the
        // gesture every other list in Hearth uses, and its two-step shape —
        // swipe uncovers a Delete button, the button has to be pressed — is
        // the point. One flick removing a line while you scroll a list
        // one-handed in a shop is exactly the accident it exists to prevent.
        //
        // The undo is a real restore here as it is elsewhere: the one line
        // goes back into the list as it stands, at the position it was
        // dragged into rather than at the bottom of the shop.
        return SwipeToDelete(
          key: ValueKey<String>(line.key),
          name: line.name,
          onDelete: () => onRemove(line),
          onRestore: () => onRestore(line),
          child: _LineTile(
            line: line,
            food: foods[line.foodId],
            onTick: (bool value) => onTick(line, value),
            onEdit: () => onEdit(line),
          ),
        );
      },
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.food,
    required this.onTick,
    required this.onEdit,
  });

  final ShoppingLine line;

  /// The food this line is matched to, when it is matched to one.
  ///
  /// Null for every food Hearth has not been told about — in which case the
  /// line goes on saying what it always said (spec §5.7, R5).
  final Food? food;
  final ValueChanged<bool> onTick;
  final VoidCallback onEdit;

  /// The line as it should be read, rather than as it is stored: a cupboard
  /// amount in another kind already taken off, and the pack to count against
  /// (spec R5, R7).
  ResolvedShoppingLine get _resolved =>
      ShoppingLineResolver.resolve(line: line, food: food);

  /// What the line says to buy, in words.
  String get _amount {
    final ResolvedShoppingLine resolved = _resolved;
    // Packs first, where the thing comes in them. "4 lb" of a sauce sold in
    // 24-ounce jars is arithmetically perfect and useless at the shelf.
    final String? packed = PackDisplay.forLine(
      line: resolved.line,
      pack: resolved.pack,
    );
    if (packed != null) return packed;

    final Quantity? buy = resolved.toBuy;
    if (buy != null) return FoodQuantityFormat.format(buy, food: food);
    if (line.planned.isEmpty) return '';
    // The recipes could only say it two ways at once, so both are shown
    // rather than one being guessed at (spec §5.7).
    return line.planned
        .map((Quantity q) => FoodQuantityFormat.format(q, food: food))
        .join(' + ');
  }

  /// The arithmetic underneath, when there is any worth showing.
  String? get _detail {
    final ResolvedShoppingLine resolved = _resolved;
    final List<String> parts = <String>[
      // Said, because a rebuild keeps it and drops the rest — and until now
      // a line somebody typed looked exactly like one the plan produced, so
      // there was no way to tell beforehand what a rebuild would take.
      if (line.isManual) 'added by hand',
      if (line.isEdited && line.planned.isNotEmpty)
        'recipes call for '
            '${line.planned.map((Quantity q) => FoodQuantityFormat.format(q, food: food)).join(' + ')}',
      // Three jars is seventy-two ounces and the ragu wants sixty-four. The
      // eight over are the whole reason to show both: a line that only says
      // "3 × 24 oz" has rounded up, and a rounding nobody can see is a
      // rounding nobody can judge.
      ?PackDisplay.shortfall(line: resolved.line, pack: resolved.pack),
      if (line.onHand != null)
        'have ${FoodQuantityFormat.format(line.onHand!, food: food)}',
      if (line.hasUnquantified) 'plus some to taste',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final GroceryLineState state = groceryLineState(line, food: food);
    final bool done =
        state == GroceryLineState.bought || state == GroceryLineState.atHome;
    final String? status = switch (state) {
      GroceryLineState.bought => 'Bought',
      GroceryLineState.atHome => 'At home',
      GroceryLineState.notNeeded => 'Not needed',
      GroceryLineState.remaining => null,
    };
    final String detail = <String>[?status, ?_detail].join(' · ');
    final Widget amount = InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(HearthRadius.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: HearthTouch.androidTarget,
          minHeight: HearthTouch.androidTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.xs),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: HearthSpacing.xxs,
            children: <Widget>[
              if (line.isEdited)
                Icon(Icons.edit_outlined, size: 14, color: colors.textMuted),
              Text(
                _amount.isEmpty ? 'Set amount' : _amount,
                style: text.ingredient,
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        label:
            '${line.name}${_amount.isEmpty ? '' : ', $_amount'}${detail.isEmpty ? '' : ', $detail'}',
        excludeSemantics: true,
        checked: done,
        onTap: () => onTick(!done),
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          const CustomSemanticsAction(label: 'Set amounts'): onEdit,
        },
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: () => onTick(!done),
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(color: colors.outline),
              ),
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final bool stacked =
                      box.maxWidth <
                      MediaQuery.textScalerOf(context).scale(16) * 17;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: HearthSpacing.xs),
                        child: Icon(
                          switch (state) {
                            GroceryLineState.bought => Icons.check_circle,
                            GroceryLineState.atHome => Icons.home_outlined,
                            GroceryLineState.notNeeded =>
                              Icons.remove_circle_outline,
                            GroceryLineState.remaining => Icons.circle_outlined,
                          },
                          size: 20,
                          color: done ? colors.goodAccent : colors.textMuted,
                        ),
                      ),
                      const SizedBox(width: HearthSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              line.name,
                              style: text.ingredient.copyWith(
                                color: done
                                    ? colors.textMuted
                                    : colors.textPrimary,
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                            if (detail.isNotEmpty) ...<Widget>[
                              const SizedBox(height: HearthSpacing.xxs),
                              Text(
                                detail,
                                style: text.metadata.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                            if (stacked) amount,
                          ],
                        ),
                      ),
                      if (!stacked) ...<Widget>[
                        const SizedBox(width: HearthSpacing.sm),
                        Flexible(child: amount),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xl),
      child: Column(
        children: <Widget>[
          Icon(Icons.shopping_basket_outlined, color: colors.textMuted),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            'Nothing on the list yet.',
            style: context.text.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HearthSpacing.xs),
          Text(
            'Say what you are going to cook, or what you need, and Hearth '
            'works out what to buy.',
            style: context.text.metadata.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Changing the list by asking (spec §5.7).
///
/// The existing assistant applies its answer with targeted Undo. A structured
/// proposal review is tracked separately as UX-063; moving this entry behind
/// More does not change that protocol. Requests use the configured assistant.
class _ChatCard extends ConsumerStatefulWidget {
  const _ChatCard({required this.lines, required this.onApply});

  final List<ShoppingLine> lines;
  final ValueChanged<List<ShoppingLine>> onApply;

  @override
  ConsumerState<_ChatCard> createState() => _ChatCardState();
}

class _ChatCardState extends ConsumerState<_ChatCard> {
  final TextEditingController _said = TextEditingController();
  final GlobalKey _undoNoticeKey = GlobalKey();
  String? _undoNotice;

  @override
  void dispose() {
    _said.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _said.text.trim();
    if (text.isEmpty) return;
    setState(() => _undoNotice = null);
    _said.clear();

    final List<ShoppingLine>? next = await ref
        .read(shoppingChatProvider.notifier)
        .send(text, widget.lines);
    if (next != null) widget.onApply(next);
  }

  Future<void> _retry() async {
    setState(() => _undoNotice = null);
    final List<ShoppingLine>? next = await ref
        .read(shoppingChatProvider.notifier)
        .retry(widget.lines);
    if (next != null) widget.onApply(next);
  }

  Future<void> _undo() async {
    final ShoppingUndo? undone = await ref
        .read(shoppingChatProvider.notifier)
        .undo();
    // Null means there was nothing to undo, or the list is no longer the one
    // the answer changed — the controller says so itself in that second case,
    // by way of the panel, so there is nothing to add here.
    if (undone == null) return;

    widget.onApply(undone.lines);

    // Said rather than silently done. Undo took back the answer; anything
    // changed since is somebody's own more recent decision, and leaving it
    // without a word would look like undo had missed.
    if (undone.kept > 0 && mounted) {
      setState(() {
        _undoNotice = undone.kept == 1
            ? 'Undone. One line you changed since was left as it is.'
            : 'Undone. ${undone.kept} lines you changed since were left as they are.';
      });
      // A root snackbar sits behind this modal. Keep the result in the
      // active sheet and bring it into view even after large-text scrolling.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_undoNoticeKey.currentContext case final BuildContext notice) {
          Scrollable.ensureVisible(notice);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final ShoppingChatState state = ref.watch(shoppingChatProvider);
    final ShoppingChatController controller = ref.read(
      shoppingChatProvider.notifier,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Ask for a change', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'Add coffee and paper towels. I have a pound of the beef '
              'already. Take the kale off.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            for (final ShoppingMessage message in state.messages) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    message.fromUser
                        ? Icons.person_outline
                        : Icons.auto_awesome,
                    size: 16,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  Expanded(
                    child: Text(
                      message.text,
                      style: context.text.body.copyWith(
                        color: message.fromUser
                            ? colors.textSecondary
                            : colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (state case final ShoppingChatFailed failed) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.error_outline, size: 18, color: colors.error),
                  const SizedBox(width: HearthSpacing.sm),
                  Expanded(
                    child: Text(
                      failed.message,
                      style: context.text.metadata.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  if (failed.canRetry)
                    TextButton(
                      onPressed: _retry,
                      child: const Text('Try again'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: HearthSpacing.md),
            TextField(
              controller: _said,
              enabled: !state.isBusy,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: context.text.body,
              decoration: InputDecoration(
                hintText: 'What should change?',
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(HearthRadius.md),
                  borderSide: BorderSide(color: colors.outline),
                ),
              ),
            ),
            const SizedBox(height: HearthSpacing.md),
            Row(
              children: <Widget>[
                if (controller.canUndo) ...<Widget>[
                  TextButton.icon(
                    onPressed: state.isBusy ? null : _undo,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Undo'),
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                ],
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: HearthTouch.minTarget,
                    ),
                    child: FilledButton(
                      onPressed: state.isBusy ? null : _send,
                      child: Text(state.isBusy ? 'Thinking…' : 'Ask'),
                    ),
                  ),
                ),
              ],
            ),
            if (_undoNotice case final String notice) ...<Widget>[
              const SizedBox(height: HearthSpacing.md),
              Semantics(
                key: _undoNoticeKey,
                liveRegion: true,
                child: Text(notice, style: context.text.body),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
