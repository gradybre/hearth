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
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/shopping/shopping_contribution.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/shopping/shopping_list_builder.dart';
import '../../domain/shopping/shopping_sources.dart';
import '../../domain/units/quantity.dart';
import 'add_to_list_sheet.dart';
import 'shopping_amount_sheet.dart';
import 'shopping_chat_controller.dart';
import 'shopping_export_sheet.dart';

/// The shopping list (spec §5.7).
///
/// Filled by adding recipes and foods to it, and owned from there on by
/// whoever is shopping: everything here is editable, and nothing leaves the
/// app until an export is deliberately tapped (rule 4).
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

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
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
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.lines, required this.gutter});

  final List<ShoppingLine> lines;
  final double gutter;

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
  Widget build(BuildContext context, WidgetRef ref) {
    // Grouped by store, untagged last. Most foods carry no store tag yet, so
    // a long "Anywhere" group at the top would bury the shops that are
    // actually organised.
    final Map<String, List<ShoppingLine>> groups =
        <String, List<ShoppingLine>>{};
    for (final ShoppingLine line in lines) {
      groups.putIfAbsent(line.storeTag ?? '', () => <ShoppingLine>[]).add(line);
    }
    final List<String> stores = groups.keys.toList()
      ..sort((String a, String b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });

    final int inBasket = lines.where((ShoppingLine l) => l.checked).length;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter),
            children: <Widget>[
              // An empty list is a setup task and a full one is not, so the two
              // states are two shapes: an empty list leads with the two ways
              // to fill it, and a list that exists keeps them out of the way
              // of the thing you are holding the phone for (§6.2.5, §7.7).
              // The card first and the words under it, which reads backwards
              // and is right: at three times the text on a phone a paragraph
              // above the buttons put the second of them 986 points down a
              // 844-point screen, where nothing could reach it. Dynamic type
              // is honoured, not capped, so what gives is the explanation's
              // claim to the top (spec §6.3).
              if (lines.isEmpty) ...<Widget>[
                _StartCard(
                  onAdd: () => _add(context, ref),
                  onBuild: () => _manage(context, ref),
                ),
                const SizedBox(height: HearthSpacing.lg),
                const _Empty(),
              ] else ...<Widget>[
                _ListHeader(
                  inBasket: inBasket,
                  total: lines.length,
                  onManage: () => _manage(context, ref),
                ),
                const SizedBox(height: HearthSpacing.lg),
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
                    onReorder: (int from, int to) =>
                        _save(ref, _reordered(store, groups, from, to)),
                    onTick: (ShoppingLine line, bool value) =>
                        _save(ref, _replacing(line.ticked(value))),
                    onEdit: (ShoppingLine line) => _edit(context, ref, line),
                    onRemove: (ShoppingLine line) => _remove(ref, line),
                    onRestore: (ShoppingLine line) => _restore(ref, line),
                  ),
                  const SizedBox(height: HearthSpacing.lg),
                ],
              ],
              // At the end of the list, not in the header and not on the
              // action bar. The header is already one line too tight at twice
              // the text, and the bar is what a thumb lands on while shopping
              // — neither is a place for something that empties the list. Down
              // here it is where you arrive when you are finished with it,
              // which is when it is wanted.
              if (lines.isNotEmpty) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _clear(context, ref),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Clear the list'),
                  ),
                ),
                const SizedBox(height: HearthSpacing.lg),
              ],
              // Last, so a growing conversation never pushes the list about.
              if (ref.watch(shoppingAssistantProvider) != null) ...<Widget>[
                _ChatCard(
                  lines: lines,
                  onApply: (List<ShoppingLine> next) => _save(ref, next),
                ),
                const SizedBox(height: HearthSpacing.lg),
              ],
            ],
          ),
        ),
        // Off the bottom of the scroll and onto a bar. It sat below every
        // line — off screen in all three renders of a sixteen-line list —
        // and it is the one control here that sends anything anywhere, so
        // the words that say so travel with it (rule 4).
        if (lines.isNotEmpty)
          _ActionBar(
            onAdd: () => _add(context, ref),
            onExport: () => showShoppingExportSheet(
              context,
              lines,
              // Passed in, so the sheet and the adapter stay free of
              // Riverpod and of anything that could reach a network.
              foods: <String, Food>{
                for (final Food f
                    in ref.read(foodLibraryProvider).value ?? const <Food>[])
                  f.id: f,
              },
            ),
          ),
      ],
    );
  }

  /// The list with one store's group put back in a new order.
  ///
  /// Only that group's sort orders change; the other stores keep theirs, so
  /// dragging in one shop cannot rearrange another.
  List<ShoppingLine> _reordered(
    String store,
    Map<String, List<ShoppingLine>> groups,
    int from,
    int to,
  ) {
    final List<ShoppingLine> group = <ShoppingLine>[...groups[store]!];
    group.insert(to, group.removeAt(from));

    final Map<String, int> order = <String, int>{
      for (int i = 0; i < group.length; i++) group[i].key: i,
    };
    return <ShoppingLine>[
      for (final ShoppingLine line in lines)
        if (order[line.key] case final int position)
          line.copyWith(sortOrder: position)
        else
          line,
    ];
  }

  /// Takes a line off the list.
  ///
  /// The snackbar and its undo belong to [SwipeToDelete], which every other
  /// list in Hearth uses — one place for how long the window is and for the
  /// fact that tapping Undo dismisses it immediately.
  Future<void> _remove(WidgetRef ref, ShoppingLine line) =>
      _save(ref, <ShoppingLine>[
        for (final ShoppingLine other in lines)
          if (other.key != line.key) other,
      ]);

  /// Puts a removed line back where it was.
  ///
  /// The one line, spliced into the list as it stands when Undo is tapped —
  /// not the list as it stood before the deletion. Whatever happened in
  /// between is somebody's more recent decision and stays (spec §5.7); the
  /// repository owns that, because it is the only thing here that can read
  /// what the list is *now* rather than what this screen last drew.
  Future<void> _restore(WidgetRef ref, ShoppingLine line) async {
    await ref.read(shoppingRepositoryProvider).restoreLine(line);
    ref.invalidate(shoppingListProvider);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ShoppingLine line,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ShoppingLine? changed = await showShoppingAmountSheet(
      context,
      line,
      onRemove: () async {
        await _remove(ref, line);
        showUndoSnackBar(
          messenger,
          message: 'Deleted ${line.name}',
          onUndo: () => _restore(ref, line),
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
/// Clearing it is not here. It was, and having it in two places meant two
/// answers to one act; it lives at the end of the list instead, where you
/// arrive when you are finished with it.
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

/// The list's own header: how much of it is left.
///
/// The range card used to sit here — 244 points of a 605-point viewport on a
/// phone, and 398 of 401 at twice the text, where not one line of the list
/// was on screen. It shrank to a line of dates beside the count, and now it
/// is gone entirely: a list filled by adding recipes to it does not cover a
/// stretch of days, so a date range printed over it was describing the last
/// build rather than the list. The dates moved to the one control they are
/// still true of (review §6.2.5).
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.inBasket,
    required this.total,
    required this.onManage,
  });

  /// How many are already in the basket, and how many there are altogether.
  final int inBasket;
  final int total;

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    // No "Shopping" title. The tab underneath says Shopping and the section
    // bar above says Nutrition; a third of the same word is the "too many
    // headings of similar strength" §6.2.1 asks to be rid of. It also cost
    // the whole viewport: at twice the text on a small phone the title, the
    // button and the line together were taller than the 303 points the list
    // had, so the list built its header and nothing else.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text(
            '$total ${total == 1 ? 'item' : 'items'}'
            '${inBasket == 0 ? '' : ' · $inBasket in the basket'}',
            // One line. At twice the text on a 320pt phone this wrapped to
            // five lines when it still carried the dates, and a confirmatory
            // line that takes a third of the screen is the problem this
            // header replaced. Truncated is the right failure for it.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        ),
        const SizedBox(width: HearthSpacing.sm),
        // Labelled, not an icon: what is behind it is what is on the list,
        // a date range, a switch, a build and a clear, and no glyph says
        // that (spec §6.3).
        TextButton.icon(
          onPressed: onManage,
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Manage list'),
        ),
      ],
    );
  }
}

/// Add and export, always reachable.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onAdd, required this.onExport});

  final VoidCallback onAdd;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(HearthSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Side by side where they fit; stacked where they do not. At
              // twice the text on a 320pt phone two buttons in a row wrap
              // their labels onto three lines each, and the bar then takes
              // the height the list needed (spec §6.3).
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  // Filled, and first where they stack: adding is what fills
                  // a list and exporting is what finishes one, so the one you
                  // press many times a week outranks the one you press at the
                  // door (spec §5.7, as amended).
                  final Widget add = FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add to list'),
                  );
                  final Widget export = OutlinedButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.ios_share, size: 18),
                    // What the destination actually opens. "Take it
                    // shopping" named a feeling rather than an action.
                    label: const Text('Share or export'),
                  );
                  final double scaled = MediaQuery.textScalerOf(context)
                      .scale(14);
                  if (box.maxWidth >= scaled * 22) {
                    return Row(
                      children: <Widget>[
                        Expanded(child: add),
                        const SizedBox(width: HearthSpacing.sm),
                        Expanded(child: export),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      add,
                      const SizedBox(height: HearthSpacing.xs),
                      export,
                    ],
                  );
                },
              ),
              const SizedBox(height: HearthSpacing.xs),
              Text(
                // Named, not "that": the export is no longer the button
                // nearest these words, and a promise about the wrong control
                // is worse than no promise (rule 4).
                'Nothing leaves the app until you tap Share or export.',
                textAlign: TextAlign.center,
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  const _StartCard({required this.onAdd, required this.onBuild});

  final VoidCallback onAdd;

  /// Opens the manage sheet rather than building. A build is over a stretch
  /// of days, and the days are the first thing you would want to see.
  final VoidCallback onBuild;

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
                label: const Text('Add to list'),
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
    required this.onReorder,
    required this.onTick,
    required this.onEdit,
    required this.onRemove,
    required this.onRestore,
  });

  final List<ShoppingLine> lines;

  /// Wired to `onReorderItem`, which hands over the index the item should end
  /// up at — the older `onReorder` reported it as it would be before the item
  /// was taken out, and left every caller to subtract one.
  final void Function(int from, int to) onReorder;
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
    required this.onTick,
    required this.onEdit,
  });

  final ShoppingLine line;
  final ValueChanged<bool> onTick;
  final VoidCallback onEdit;

  /// What the line says to buy, in words.
  String get _amount {
    final Quantity? buy = line.toBuy;
    if (buy != null) return QuantityFormat.format(buy);
    if (line.planned.isEmpty) return '';
    // The recipes could only say it two ways at once, so both are shown
    // rather than one being guessed at (spec §5.7).
    return line.planned.map(QuantityFormat.format).join(' + ');
  }

  /// The arithmetic underneath, when there is any worth showing.
  String? get _detail {
    final List<String> parts = <String>[
      // Said, because a rebuild keeps it and drops the rest — and until now
      // a line somebody typed looked exactly like one the plan produced, so
      // there was no way to tell beforehand what a rebuild would take.
      if (line.isManual) 'added by hand',
      if (line.isEdited && line.planned.isNotEmpty)
        'recipes call for ${line.planned.map(QuantityFormat.format).join(' + ')}',
      if (line.onHand != null) 'have ${QuantityFormat.format(line.onHand!)}',
      if (line.hasUnquantified) 'plus some to taste',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final bool done = line.isChecked;

    return Padding(
      padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
      child: Semantics(
        // Assembled by hand so the whole line is one thing to a screen reader
        // rather than a checkbox, a name and two numbers read separately.
        label:
            '${line.name}${_amount.isEmpty ? '' : ', $_amount'}'
            '${_detail == null ? '' : ', ${_detail!}'}'
            '${done ? '. Already have it.' : ''}',
        excludeSemantics: true,
        // `excludeSemantics` swallows the amount field's own node, so the
        // only way to reach it without sight is here. Removal is not listed:
        // `SwipeToDelete` puts its own "Delete <name>" action on the node
        // above this one, and two ways to say it would read as two controls.
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          const CustomSemanticsAction(label: 'Set amounts'): onEdit,
        },
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: () => onTick(!done),
            // No long press. It starts a reorder drag — which is what
            // `buildDefaultDragHandles` binds it to, and what dragging the
            // list into the order you walk the shop in depends on. Removal
            // moved to a swipe, where it is both discoverable and undoable.
            borderRadius: BorderRadius.circular(HearthRadius.md),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HearthRadius.md),
                border: Border.all(color: colors.outline),
              ),
              padding: const EdgeInsets.all(HearthSpacing.md),
              child: Row(
                children: <Widget>[
                  // Never colour alone (§6.3): a done line carries the tick
                  // itself, not just a faded look.
                  Icon(
                    done ? Icons.check_circle : Icons.circle_outlined,
                    size: 20,
                    color: done ? colors.goodAccent : colors.textMuted,
                  ),
                  const SizedBox(width: HearthSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          line.name,
                          style: text.ingredient.copyWith(
                            color: done ? colors.textMuted : colors.textPrimary,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                        if (_detail case final String detail) ...<Widget>[
                          const SizedBox(height: HearthSpacing.xxs),
                          Text(
                            detail,
                            style: text.metadata.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: HearthSpacing.sm),
                  // Tapping the amount is how you change it, or say how much
                  // of it you already have.
                  InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(HearthRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(HearthSpacing.xs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (line.isEdited)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: HearthSpacing.xxs,
                              ),
                              child: Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: colors.textMuted,
                              ),
                            ),
                          Text(_amount, style: text.ingredient),
                        ],
                      ),
                    ),
                  ),
                ],
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
/// The answer lands straight on the list, with an undo. Safe for the reason
/// the whole screen is: nothing leaves the app until an export is tapped, so
/// the list is its own review surface (rule 4).
class _ChatCard extends ConsumerStatefulWidget {
  const _ChatCard({required this.lines, required this.onApply});

  final List<ShoppingLine> lines;
  final ValueChanged<List<ShoppingLine>> onApply;

  @override
  ConsumerState<_ChatCard> createState() => _ChatCardState();
}

class _ChatCardState extends ConsumerState<_ChatCard> {
  final TextEditingController _said = TextEditingController();

  @override
  void dispose() {
    _said.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _said.text.trim();
    if (text.isEmpty) return;
    _said.clear();

    final List<ShoppingLine>? next = await ref
        .read(shoppingChatProvider.notifier)
        .send(text, widget.lines);
    if (next != null) widget.onApply(next);
  }

  Future<void> _retry() async {
    final List<ShoppingLine>? next = await ref
        .read(shoppingChatProvider.notifier)
        .retry(widget.lines);
    if (next != null) widget.onApply(next);
  }

  Future<void> _undo() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            undone.kept == 1
                ? 'Undone. One line you changed since was left as it is.'
                : 'Undone. ${undone.kept} lines you changed since were left '
                      'as they are.',
          ),
        ),
      );
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
                  child: SizedBox(
                    height: HearthTouch.minTarget,
                    child: FilledButton(
                      onPressed: state.isBusy ? null : _send,
                      child: Text(state.isBusy ? 'Thinking…' : 'Ask'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
