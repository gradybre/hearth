import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/text/text_normaliser.dart';
import 'external_food_results.dart';
import 'food_search_controller.dart';

/// Picks a food for an ingredient line (spec §5.3's match review, in its
/// Phase 1 manual form).
///
/// Opens pre-filtered by the ingredient's own name, because the common case is
/// that the food is already in the library under roughly that word — and the
/// fastest match is the one you don't have to search for.
Future<String?> showFoodPicker(
  BuildContext context, {
  required String ingredientName,
  String? currentFoodId,
  List<Food> defaults = const <Food>[],
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) => _FoodPickerSheet(
    ingredientName: ingredientName,
    currentFoodId: currentFoodId,
    defaults: defaults,
  ),
);

/// Returned by the sheet to mean "detach the food from this line".
const String clearFoodSentinel = '__clear__';

/// Returned by the sheet to mean "this line was never going to have a food".
const String noMatchNeededSentinel = '__no_match__';

class _FoodPickerSheet extends ConsumerStatefulWidget {
  const _FoodPickerSheet({
    required this.ingredientName,
    this.currentFoodId,
    this.defaults = const <Food>[],
  });

  final String ingredientName;
  final String? currentFoodId;

  /// The household's defaults that answer this line, when more than one does.
  ///
  /// A recipe asking for "milk" against a fridge holding whole, 2% and
  /// non-fat has genuinely not said which, so the answer is these three at
  /// the top of the list rather than a guess — and everything else on this
  /// sheet is still here for adding a different one as usual (spec §5.3).
  final List<Food> defaults;

  @override
  ConsumerState<_FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends ConsumerState<_FoodPickerSheet> {
  late final TextEditingController _search = TextEditingController(
    text: widget.ingredientName,
  );

  @override
  void initState() {
    super.initState();
    // The sheet opens pre-filled with the ingredient's own name, so the
    // outward search should run on it too — the common reason a food is
    // missing locally is that nobody has added it yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(foodSearchProvider.notifier).search(widget.ingredientName);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Hands a food — scanned or searched for — straight back as this line's
  /// match.
  void _useScanned(String foodId) {
    if (!mounted) return;
    Navigator.of(context).pop(foodId);
  }

  /// Opens the food's own editor without leaving this sheet.
  ///
  /// The sheet only ever offered a way to pick a *different* food for the
  /// line — reasonable when nothing existed yet, wrong once something does:
  /// a matched food with the wrong serving or a macro worth correcting had no
  /// way to be fixed without abandoning the match, going to the Foods tab,
  /// finding it there, and coming back. This edits it in place instead. The
  /// match itself is untouched — editing changes what the food *is*, not
  /// which food the line points at, so there is nothing to hand back here.
  Future<void> _editFood(String foodId) async {
    await context.push<void>('/food/$foodId');
  }

  /// The library, filtered and ranked by how well each food answers the
  /// search box — not left in whatever order the database happens to return,
  /// which buried real matches anywhere in a long list and made them
  /// indistinguishable from not being there at all.
  ///
  /// Word overlap rather than substring: an ingredient's own wording and a
  /// saved food's name often share every meaningful word without one
  /// containing the other ("lean ground beef" vs. a food named "96/4 Ground
  /// Beef"), and a `contains` check in either direction missed that entirely.
  List<Food> _rank(List<Food> foods) {
    final String query = _search.text;
    if (normaliseKey(query).isEmpty) return _withCurrentFirst(foods, foods);

    final List<(Food, double)> scored = <(Food, double)>[
      for (final Food food in foods)
        (food, wordCoverage(query, '${food.name} ${food.brand ?? ''}')),
    ];
    final List<(Food, double)> matched = <(Food, double)>[
      for (final (Food, double) entry in scored)
        if (entry.$2 > 0) entry,
    ]..sort(((Food, double) a, (Food, double) b) => b.$2.compareTo(a.$2));

    return _withCurrentFirst(<Food>[
      for (final (Food, double) entry in matched) entry.$1,
    ], foods);
  }

  /// Whatever is already matched — an actual pick, or a strong suggestion
  /// like a previously-used or remembered food — leads the list, so it is
  /// never left to compete with an arbitrary sort order for the top spot.
  ///
  /// And is *in* the list at all. It used only to reorder, so a search that
  /// did not happen to find the matched food dropped it: a line reading
  /// "apples" matched to "Honeycrisp Apple" opened on "None of your foods
  /// match" while the header offered to Unmatch it. Which is exactly the case
  /// remembered matches exist for — the wording and the food's name differing
  /// is the whole point of remembering.
  List<Food> _withCurrentFirst(List<Food> foods, List<Food> all) {
    final String? currentId = widget.currentFoodId;
    if (currentId == null) return foods;

    final int index = foods.indexWhere((Food f) => f.id == currentId);
    if (index < 0) {
      final int inLibrary = all.indexWhere((Food f) => f.id == currentId);
      return inLibrary < 0 ? foods : <Food>[all[inLibrary], ...foods];
    }
    if (index == 0) return foods;

    return <Food>[
      foods[index],
      for (int i = 0; i < foods.length; i++)
        if (i != index) foods[i],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final AsyncValue<List<Food>> library = ref.watch(foodLibraryProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController controller) =>
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(HearthRadius.xl),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(HearthSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Match "${widget.ingredientName}"',
                                style: context.text.sectionHeader,
                              ),
                            ),
                            if (widget.currentFoodId != null)
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pop(clearFoodSentinel),
                                child: const Text('Unmatch'),
                              ),
                          ],
                        ),
                        const SizedBox(height: HearthSpacing.xxs),
                        // Makes an existing mechanic visible rather than
                        // adding a new one: picking a food here already
                        // writes to `ingredient_match` and auto-applies next
                        // time this exact wording turns up (spec §5.3) — the
                        // one thing missing was saying so.
                        Text(
                          'Picking a food remembers it as the default for '
                          "this ingredient's wording next time.",
                          style: context.text.metadata.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: HearthSpacing.sm),
                        // Salt has nothing to match and never will. Offered
                        // here because here is where the line is nagging, and
                        // it is remembered, so the next recipe starts quiet.
                        // An offer, and it has to look like one. Styled as an
                        // accent text button it was the same grass icon in the
                        // same colour as the badge a *marked* line wears, so
                        // opening the sheet on an apple read as Hearth
                        // claiming the apple was a seasoning.
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                Navigator.of(context)
                                    .pop(noMatchNeededSentinel),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.textSecondary,
                              side: BorderSide(color: colors.outline),
                            ),
                            icon: const Icon(Icons.grass_outlined, size: 18),
                            label: const Text('Mark as a seasoning instead'),
                          ),
                        ),
                        const SizedBox(height: HearthSpacing.sm),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: _search,
                                autofocus: false,
                                onChanged: (String value) {
                                  ref
                                      .read(foodSearchProvider.notifier)
                                      .search(value);
                                  setState(() {});
                                },
                                style: context.text.body,
                                decoration: InputDecoration(
                                  hintText: 'Search your foods',
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: colors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: HearthSpacing.sm),
                            // In-recipe capture (spec §5.5): the packet is
                            // usually in your hand while you write the recipe,
                            // and scanning it beats leaving for the Foods tab,
                            // adding it there, and coming back to match it.
                            _ScanButton(onScanned: _useScanned),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: library.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (Object e, StackTrace s) =>
                          Center(child: Text('Could not read foods.\n$e')),
                      data: (List<Food> foods) {
                        final List<Food> visible = _rank(foods);
                        if (visible.isEmpty) {
                          return ListView(
                            controller: controller,
                            padding: const EdgeInsets.symmetric(
                              horizontal: HearthSpacing.lg,
                            ),
                            children: <Widget>[
                              _NoFoods(
                                hasAny: foods.isNotEmpty,
                                ingredientName: widget.ingredientName,
                                onScanned: _useScanned,
                              ),
                              ExternalFoodResults(
                                query: _search.text,
                                onSaved: _useScanned,
                              ),
                            ],
                          );
                        }
                        final Set<String> defaultIds = <String>{
                          for (final Food food in widget.defaults) food.id,
                        };
                        return ListView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(
                            HearthSpacing.lg,
                            0,
                            HearthSpacing.lg,
                            HearthSpacing.xl,
                          ),
                          children: <Widget>[
                            if (widget.defaults.isNotEmpty) ...<Widget>[
                              _GroupLabel(
                                text:
                                    'Your defaults for '
                                    '"${widget.ingredientName}"',
                              ),
                              for (final Food food
                                  in widget.defaults) ...<Widget>[
                                _FoodOption(
                                  food: food,
                                  selected: food.id == widget.currentFoodId,
                                  onEdit: food.id == widget.currentFoodId
                                      ? () => _editFood(food.id)
                                      : null,
                                ),
                                const SizedBox(height: HearthSpacing.sm),
                              ],
                              const _GroupLabel(text: 'Everything else'),
                            ],
                            for (final Food food in visible)
                              if (!defaultIds.contains(food.id)) ...<Widget>[
                                _FoodOption(
                                  food: food,
                                  selected: food.id == widget.currentFoodId,
                                  onEdit: food.id == widget.currentFoodId
                                      ? () => _editFood(food.id)
                                      : null,
                                ),
                                const SizedBox(height: HearthSpacing.sm),
                              ],
                            // A food found out there is saved first, then used
                            // as this line's match — same review as any other
                            // route into the library (CLAUDE.md rule 4).
                            ExternalFoodResults(
                              query: _search.text,
                              onSaved: _useScanned,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

/// A heading above a run of options.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
    child: Text(
      text,
      style: context.text.metadata.copyWith(color: context.colors.textMuted),
    ),
  );
}

class _FoodOption extends StatelessWidget {
  const _FoodOption({required this.food, required this.selected, this.onEdit});

  final Food food;
  final bool selected;

  /// Set only on the currently-matched option: editing makes sense for the
  /// food already attached to this line, not for every alternative on offer.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final ServingOption? serving = food.defaultServing;

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${food.name}. '
          '${serving == null ? 'No serving size' : '${serving.macros.kcal.round()} calories per ${QuantityFormat.formatAsAuthored(serving.amount)}'}'
          '${selected ? '. Currently matched.' : ''}',
      onTap: () => Navigator.of(context).pop(food.id),
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.surfaceSunken : colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        child: InkWell(
          onTap: () => Navigator.of(context).pop(food.id),
          borderRadius: BorderRadius.circular(HearthRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HearthRadius.md),
              border: Border.all(
                color: selected ? colors.outlineStrong : colors.outline,
              ),
            ),
            padding: const EdgeInsets.all(HearthSpacing.md),
            child: Row(
              children: <Widget>[
                if (selected) ...<Widget>[
                  Icon(Icons.check, size: 18, color: colors.accent),
                  const SizedBox(width: HearthSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        food.brand == null
                            ? food.name
                            : '${food.name}  ·  ${food.brand}',
                        style: context.text.ingredient,
                      ),
                      if (serving != null) ...<Widget>[
                        const SizedBox(height: HearthSpacing.xxs),
                        Text(
                          '${serving.macros.kcal.round()} kcal per '
                          '${QuantityFormat.formatAsAuthored(serving.amount)}',
                          style: context.text.metadata.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onEdit != null)
                  Semantics(
                    button: true,
                    label: "Edit ${food.name}'s details",
                    onTap: onEdit,
                    excludeSemantics: true,
                    child: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit this food',
                      color: colors.textSecondary,
                      onPressed: onEdit,
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

/// The button that opens the scanner and reports what it settled on.
class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onScanned});

  final ValueChanged<String> onScanned;

  Future<void> _scan(BuildContext context) async {
    final String? foodId = await context.push<String>('/food/scan?pick=1');
    if (foodId != null) onScanned(foodId);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Scan a barcode to match this ingredient',
    onTap: () => _scan(context),
    excludeSemantics: true,
    child: IconButton.filledTonal(
      icon: const Icon(Icons.qr_code_scanner),
      tooltip: 'Scan a barcode',
      onPressed: () => _scan(context),
    ),
  );
}

class _NoFoods extends StatelessWidget {
  const _NoFoods({
    required this.hasAny,
    required this.ingredientName,
    required this.onScanned,
  });

  final bool hasAny;
  final String ingredientName;
  final ValueChanged<String> onScanned;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(HearthSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Only ever about the household's own foods: results from further
          // afield may well be listed directly underneath this.
          Text(
            hasAny
                ? 'None of your foods match.'
                : 'Your food library is empty.',
            style: context.text.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            'If you have the packet, scan it — "$ingredientName" is matched '
            'and filed in one go.',
            style: context.text.metadata.copyWith(
              color: context.colors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HearthSpacing.md),
          FilledButton.icon(
            onPressed: () async {
              final String? foodId = await context.push<String>(
                '/food/scan?pick=1',
              );
              if (foodId != null) onScanned(foodId);
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan a barcode'),
          ),
        ],
      ),
    ),
  );
}
