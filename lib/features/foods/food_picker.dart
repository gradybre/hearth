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
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (BuildContext context) => _FoodPickerSheet(
    ingredientName: ingredientName,
    currentFoodId: currentFoodId,
  ),
);

/// Returned by the sheet to mean "detach the food from this line".
const String clearFoodSentinel = '__clear__';

class _FoodPickerSheet extends ConsumerStatefulWidget {
  const _FoodPickerSheet({required this.ingredientName, this.currentFoodId});

  final String ingredientName;
  final String? currentFoodId;

  @override
  ConsumerState<_FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends ConsumerState<_FoodPickerSheet> {
  late final TextEditingController _search = TextEditingController(
    text: widget.ingredientName,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Hands the scanned food straight back as this line's match.
  void _useScanned(String foodId) {
    if (!mounted) return;
    Navigator.of(context).pop(foodId);
  }

  List<Food> _filter(List<Food> foods) {
    final String needle = normaliseKey(_search.text);
    if (needle.isEmpty) return foods;
    return foods
        .where(
          (Food food) =>
              normaliseKey(food.name).contains(needle) ||
              normaliseKey(food.brand ?? '').contains(needle) ||
              needle.contains(normaliseKey(food.name)),
        )
        .toList(growable: false);
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
                        const SizedBox(height: HearthSpacing.md),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: _search,
                                autofocus: false,
                                onChanged: (_) => setState(() {}),
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
                        final List<Food> visible = _filter(foods);
                        if (visible.isEmpty) {
                          return _NoFoods(
                            hasAny: foods.isNotEmpty,
                            ingredientName: widget.ingredientName,
                            onScanned: _useScanned,
                          );
                        }
                        return ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(
                            HearthSpacing.lg,
                            0,
                            HearthSpacing.lg,
                            HearthSpacing.xl,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (BuildContext context, int index) =>
                              const SizedBox(height: HearthSpacing.sm),
                          itemBuilder: (BuildContext context, int index) =>
                              _FoodOption(
                                food: visible[index],
                                selected:
                                    visible[index].id == widget.currentFoodId,
                              ),
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

class _FoodOption extends StatelessWidget {
  const _FoodOption({required this.food, required this.selected});

  final Food food;
  final bool selected;

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
          Text(
            hasAny
                ? 'No food matches that search.'
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
