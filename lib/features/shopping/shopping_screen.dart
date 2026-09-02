import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../data/local/shopping_store.dart';
import '../../domain/foods/no_match_rule.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/shopping/shopping_list_builder.dart';
import '../../domain/units/quantity.dart';
import 'shopping_amount_sheet.dart';

/// The shopping list (spec §5.7).
///
/// Built from a stretch of the plan and then owned by whoever is shopping:
/// everything here is editable, and nothing leaves the app until an export is
/// deliberately tapped (rule 4).
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
    final HearthColors colors = context.colors;
    final ({DateTime from, DateTime to}) range = ref.watch(
      shoppingRangeProvider,
    );

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

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter * 3),
      children: <Widget>[
        _RangeCard(
          range: range,
          onRebuild: () => _rebuild(context, ref),
          onAdd: () => _addManual(context, ref),
        ),
        const SizedBox(height: HearthSpacing.lg),
        if (lines.isEmpty)
          _Empty(range: range)
        else
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
              onRemove: (ShoppingLine line) => _save(ref, <ShoppingLine>[
                for (final ShoppingLine other in lines)
                  if (other.key != line.key) other,
              ]),
            ),
            const SizedBox(height: HearthSpacing.lg),
          ],
        if (lines.isNotEmpty)
          Center(
            child: Text(
              'Nothing is sent anywhere until you export it.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
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

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ShoppingLine line,
  ) async {
    final ShoppingLine? changed = await showShoppingAmountSheet(context, line);
    if (changed != null) await _save(ref, _replacing(changed));
  }

  Future<void> _addManual(BuildContext context, WidgetRef ref) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _AddItemDialog(),
    );
    if (name == null || name.trim().isEmpty) return;

    final String key = ShoppingListBuilder.keyFor(name: name);
    if (lines.any((ShoppingLine l) => l.key == key)) return;

    await _save(ref, <ShoppingLine>[
      ...lines,
      ShoppingLine.manual(key: key, name: name.trim(), sortOrder: lines.length),
    ]);
  }
}

/// What the list covers, and the two things you do to the whole of it.
class _RangeCard extends ConsumerWidget {
  const _RangeCard({
    required this.range,
    required this.onRebuild,
    required this.onAdd,
  });

  final ({DateTime from, DateTime to}) range;
  final VoidCallback onRebuild;
  final VoidCallback onAdd;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final bool seasonings = ref.watch(shoppingSeasoningsProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.lg),
        border: Border.all(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HearthSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Shopping for', style: context.text.label),
                ),
                IconButton(
                  onPressed: onAdd,
                  tooltip: 'Add an item by hand',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.xs),
            // The range, not a week — the shop happens on a Friday for a
            // stretch that covers the weekend and the week after.
            InkWell(
              onTap: () => _pick(context, ref),
              borderRadius: BorderRadius.circular(HearthRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xs),
                child: Row(
                  children: <Widget>[
                    Text(
                      '${shortDate(range.from)} – ${shortDate(range.to)}',
                      style: context.text.recipeTitle,
                    ),
                    const SizedBox(width: HearthSpacing.sm),
                    Icon(
                      Icons.edit_calendar_outlined,
                      size: 18,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: HearthSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Include seasonings',
                    style: context.text.metadata.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Switch(
                  value: seasonings,
                  onChanged: (_) =>
                      ref.read(shoppingSeasoningsProvider.notifier).toggle(),
                ),
              ],
            ),
            const SizedBox(height: HearthSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRebuild,
                child: const Text('Build from the plan'),
              ),
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
  });

  final List<ShoppingLine> lines;

  /// Wired to `onReorderItem`, which hands over the index the item should end
  /// up at — the older `onReorder` reported it as it would be before the item
  /// was taken out, and left every caller to subtract one.
  final void Function(int from, int to) onReorder;
  final void Function(ShoppingLine line, bool value) onTick;
  final ValueChanged<ShoppingLine> onEdit;
  final ValueChanged<ShoppingLine> onRemove;

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
        return _LineTile(
          key: ValueKey<String>(line.key),
          line: line,
          onTick: (bool value) => onTick(line, value),
          onEdit: () => onEdit(line),
          onRemove: () => onRemove(line),
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
    required this.onRemove,
    super.key,
  });

  final ShoppingLine line;
  final ValueChanged<bool> onTick;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

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
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: InkWell(
            onTap: () => onTick(!done),
            onLongPress: onRemove,
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
  const _Empty({required this.range});

  final ({DateTime from, DateTime to}) range;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HearthSpacing.xxl),
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
            'Build it from what you have planned between '
            '${shortDate(range.from)} and ${shortDate(range.to)}, or add '
            'items by hand.',
            style: context.text.metadata.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog();

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add an item'),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(hintText: 'Coffee, paper towels…'),
      onSubmitted: (String value) => Navigator.of(context).pop(value),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_name.text),
        child: const Text('Add'),
      ),
    ],
  );
}
