import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/parsing/ingredient_parser.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import '../foods/food_draft.dart';
import '../foods/food_picker.dart';
import '../foods/ingredient_food_capture.dart';
import '../foods/read_label_sheet.dart';
import 'match_review_controller.dart';

/// Recipe matches returned together, plus explicit household remembering.
/// This remains a Map for existing callers; callers that persist remembered
/// wording must use [rememberIngredientNames], never all of [keys].
class ReviewedIngredientMatches extends UnmodifiableMapView<String, String> {
  ReviewedIngredientMatches(
    Map<String, String> matches, {
    Set<String> rememberIngredientNames = const {},
  }) : rememberIngredientNames = Set.unmodifiable(rememberIngredientNames),
       super(Map<String, String>.of(matches));

  final Set<String> rememberIngredientNames;
}

Future<ReviewedIngredientMatches?> showMatchReview(
  BuildContext context, {
  required List<ParsedIngredient> ingredients,
  List<AiEstimate> estimates = const <AiEstimate>[],
}) => Navigator.of(context).push<ReviewedIngredientMatches>(
  MaterialPageRoute<ReviewedIngredientMatches>(
    builder: (context) => ProviderScope(
      overrides: [matchReviewProvider.overrideWith(MatchReviewController.new)],
      child: _MatchReviewScreen(ingredients: ingredients, estimates: estimates),
    ),
  ),
);

class _MatchReviewScreen extends ConsumerStatefulWidget {
  const _MatchReviewScreen({
    required this.ingredients,
    required this.estimates,
  });

  final List<ParsedIngredient> ingredients;
  final List<AiEstimate> estimates;

  @override
  ConsumerState<_MatchReviewScreen> createState() => _MatchReviewScreenState();
}

class _MatchReviewScreenState extends ConsumerState<_MatchReviewScreen> {
  bool _applying = false;
  int? _resolving;
  int? _focusIndex;
  String? _error;
  late final String _household;
  late final String _user;
  final Map<int, GlobalKey> _rowKeys = {};

  // Stable IDs across a partial library save and retry. Recipe matches still
  // return in one result only after the entire reviewed selection is ready.
  final Map<String, Food> _prepared = {};
  final Set<String> _saved = {};

  bool get _sameAccount =>
      mounted &&
      ref.read(currentHouseholdIdProvider) == _household &&
      ref.read(currentUserIdProvider) == _user;
  bool get _canDeliver =>
      _sameAccount && (ModalRoute.of(context)?.isCurrent ?? false);
  bool get _busy => _applying || _resolving != null;

  @override
  void initState() {
    super.initState();
    // Capture identity before the first async lookup, not when it returns.
    _household = ref.read(currentHouseholdIdProvider);
    _user = ref.read(currentUserIdProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(matchReviewProvider.notifier)
            .findMatches(widget.ingredients, estimates: widget.estimates);
      }
    });
  }

  Future<void> _advance(int index) async {
    final state = ref.read(matchReviewProvider);
    if (state is! MatchReviewReady) return;
    final next = state.nextUnresolvedAfter(index);
    setState(() => _focusIndex = next);
    if (next == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_canDeliver) return;
    final target = _rowKeys[next]?.currentContext;
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      alignment: 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
    );
  }

  Future<void> _resolve(int index, _Resolution action) async {
    final ready = ref.read(matchReviewProvider);
    if (ready is! MatchReviewReady || _busy || !_canDeliver) return;
    final row = ready.rows[index];
    final capture = IngredientFoodCapture(
      ingredientName: row.ingredient.name,
      authoredLine: row.authoredLine,
      recipeLineCount: row.lineCount,
    );
    final repository = ref.read(foodRepositoryProvider);
    setState(() {
      _resolving = index;
      _error = null;
    });
    try {
      String? chosen;
      switch (action) {
        case _Resolution.search:
          chosen = await showFoodPicker(
            context,
            ingredientName: row.ingredient.name,
            authoredLine: row.authoredLine,
            capture: capture,
            currentFoodId: row.fromLibrary ? row.food?.id : null,
            offerSeasoning: false,
            offerUnmatch: false,
            rememberOnChoose: false,
          );
        case _Resolution.scan:
          chosen = await context.push<String>(
            '/food/scan?pick=1',
            extra: IngredientFoodRouteExtra(capture: capture),
          );
        case _Resolution.manual:
          chosen = await context.push<String>(
            '/food/new',
            extra: IngredientFoodRouteExtra(
              capture: capture,
              draft: FoodDraft.blank().copyWith(name: row.ingredient.name),
            ),
          );
        case _Resolution.label:
          final reading = await showReadLabelSheet(context, capture: capture);
          if (!mounted || reading == null || !_canDeliver) return;
          chosen = await context.push<String>(
            '/food/new',
            extra: IngredientFoodRouteExtra(
              capture: capture,
              draft: FoodDraft.blank()
                  .copyWith(name: row.ingredient.name)
                  .withLabel(reading),
            ),
          );
      }
      if (!_canDeliver || chosen == null) return;
      final food = await repository.byId(chosen);
      if (!mounted || !_canDeliver) return;
      if (food == null || food.isDeleted || food.isModifier) {
        setState(
          () =>
              _error = 'That food is no longer available. Choose another food.',
        );
        return;
      }
      ref.read(matchReviewProvider.notifier).replaceWithSavedFood(index, food);
      await _advance(index);
    } catch (_) {
      if (_canDeliver) {
        setState(
          () => _error = 'Could not use that food. Your choices are still here. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _resolving = null);
    }
  }

  Future<void> _apply(MatchReviewReady ready) async {
    if (_busy || !_canDeliver) return;
    final repository = ref.read(foodRepositoryProvider);
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final Map<String, String> matches = {};
      final Set<String> remember = {};
      for (int i = 0; i < ready.rows.length; i++) {
        final row = ready.rows[i];
        if (!row.resolved) continue;
        if (!mounted || !_canDeliver) return;
        final Food food;
        if (row.fromLibrary) {
          final existing = await repository.byId(row.food!.id);
          if (!mounted || !_canDeliver) return;
          if (existing == null || existing.isDeleted || existing.isModifier) {
            throw StateError('The selected food is no longer available.');
          }
          food = existing;
        } else {
          final key = '$i:${row.food?.id ?? 'estimate'}';
          final Food prepared = _prepared.putIfAbsent(
            key,
            () => row.food != null
                ? FoodDraft.fromLookup(row.food!).toFood()
                : _foodFromEstimate(row),
          );
          if (_saved.contains(prepared.id)) {
            // A partial Apply can wait here through a deletion or correction
            // elsewhere. Keep its stable ID, but never treat the cached draft
            // as proof that the saved food is still usable or save it again.
            final Food? existing = await repository.byId(prepared.id);
            if (!mounted || !_canDeliver) return;
            if (existing == null || existing.isDeleted || existing.isModifier) {
              throw StateError('The selected food is no longer available.');
            }
            food = existing;
          } else {
            await repository.save(prepared);
            _saved.add(prepared.id);
            food = prepared;
          }
        }
        if (!mounted || !_canDeliver) return;
        matches[row.ingredient.name] = food.id;
        if (row.remember) remember.add(row.ingredient.name);
      }
      if (mounted && _canDeliver) {
        Navigator.of(context).pop(
          ReviewedIngredientMatches(matches, rememberIngredientNames: remember),
        );
      }
    } catch (_) {
      if (_canDeliver) {
        setState(
          () => _error = 'Could not apply these matches. Your choices are still here. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Food _foodFromEstimate(IngredientMatchRow row) {
    final estimate = row.estimate!;
    final Quantity amount =
        row.ingredient.quantity ?? Quantity.of(1, Units.item);
    return Food(
      id: const Uuid().v4(),
      name: row.ingredient.name,
      source: FoodSource.aiEstimate,
      servingOptions: [
        ServingOption(
          id: const Uuid().v4(),
          label: QuantityFormat.formatAsAuthored(amount),
          amount: amount,
          macros: Macros(
            kcal: estimate.kcal,
            proteinG: estimate.proteinG,
            carbG: estimate.carbG,
            fatG: estimate.fatG,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentHouseholdIdProvider);
    ref.watch(currentUserIdProvider);
    final state = ref.watch(matchReviewProvider);
    final canRead = canReadLabels(ref);
    final gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;
    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: Text('Matches', style: context.text.sectionHeader),
          leading: IconButton(
            tooltip: 'Cancel match review',
            onPressed: _applying ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ),
        body: SafeArea(
          child: !_sameAccount
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(gutter),
                    child: Text(
                      'Your account changed. Close this review and open the recipe again.',
                      style: context.text.body,
                    ),
                  ),
                )
              : switch (state) {
                  MatchReviewIdle() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  MatchReviewSearching(:final done, :final total) => Center(
                    child: Padding(
                      padding: EdgeInsets.all(gutter),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: HearthSpacing.md),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              'Looking up $done of $total',
                              style: context.text.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  MatchReviewReady() => SingleChildScrollView(
                    key: const Key('match-review-scroll'),
                    padding: EdgeInsets.all(gutter),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                '${state.resolvedCount} of ${state.rows.length} resolved',
                                key: const Key('match-review-count'),
                                style: context.text.sectionHeader,
                              ),
                            ),
                            const SizedBox(height: HearthSpacing.xs),
                            Text(
                              'Unmatched lines won’t block saving.',
                              style: context.text.body.copyWith(
                                color: context.colors.textSecondary,
                              ),
                            ),
                            if (state.skippedCount > 0)
                              Text(
                                '${state.skippedCount} skipped for now',
                                style: context.text.metadata,
                              ),
                            const SizedBox(height: HearthSpacing.lg),
                            for (int i = 0; i < state.rows.length; i++)
                              Padding(
                                key: _rowKeys.putIfAbsent(i, GlobalKey.new),
                                padding: const EdgeInsets.only(
                                  bottom: HearthSpacing.md,
                                ),
                                child: _MatchRow(
                                  index: i,
                                  row: state.rows[i],
                                  active: _focusIndex == i,
                                  enabled: !_busy,
                                  canRead: canRead,
                                  onAccept: (value) {
                                    ref
                                        .read(matchReviewProvider.notifier)
                                        .setAccepted(i, accepted: value);
                                    if (value) _advance(i);
                                  },
                                  onRemember: (value) => ref
                                      .read(matchReviewProvider.notifier)
                                      .setRemember(i, remember: value),
                                  onResolve: (action) => _resolve(i, action),
                                  onSkip: () {
                                    ref
                                        .read(matchReviewProvider.notifier)
                                        .skip(i);
                                    _advance(i);
                                  },
                                ),
                              ),
                            if (_error != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  key: const Key('match-review-error'),
                                  style: context.text.body.copyWith(
                                    color: context.colors.error,
                                  ),
                                ),
                              ),
                              const SizedBox(height: HearthSpacing.md),
                            ],
                            FilledButton(
                              key: const Key('match-review-apply'),
                              onPressed: _busy ? null : () => _apply(state),
                              child: Text(
                                _applying
                                    ? 'Applying…'
                                    : 'Apply reviewed ${state.resolvedCount} together',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: HearthSpacing.sm),
                            Text(
                              'Only these reviewed matches change the recipe. '
                              'Household wording is remembered only where you select it.',
                              style: context.text.metadata.copyWith(
                                color: context.colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                },
        ),
      ),
    );
  }
}

enum _Resolution { search, scan, label, manual }

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.index,
    required this.row,
    required this.active,
    required this.enabled,
    required this.canRead,
    required this.onAccept,
    required this.onRemember,
    required this.onResolve,
    required this.onSkip,
  });

  final int index;
  final IngredientMatchRow row;
  final bool active;
  final bool enabled;
  final bool canRead;
  final ValueChanged<bool> onAccept;
  final ValueChanged<bool> onRemember;
  final ValueChanged<_Resolution> onResolve;
  final VoidCallback onSkip;

  String get _source => switch (row.food?.source) {
    FoodSource.openFoodFacts => 'Open Food Facts',
    FoodSource.usda => 'USDA',
    FoodSource.manual => 'Your library',
    FoodSource.aiEstimate => 'AI estimate',
    FoodSource.restaurant => 'Restaurant menu',
    null => '',
  };

  String _macrosFor(ParsedIngredient ingredient) {
    final computed = MacroCalculator.forIngredient(
      RecipeIngredient(
        id: 'preview',
        sectionId: 'preview',
        name: ingredient.name,
        sortOrder: 0,
        quantity: ingredient.quantity,
      ),
      food: row.food,
    );
    return switch (computed.status) {
      IngredientMacroStatus.resolved =>
        '${computed.macros.kcal.round()} kcal · '
            '${computed.macros.proteinG.round()} g protein',
      IngredientMacroStatus.noQuantity => 'No amount on the line',
      IngredientMacroStatus.unconvertible =>
        'Cannot convert ${QuantityFormat.formatAsAuthored(ingredient.quantity!)} to this food\'s servings',
      _ => '',
    };
  }

  Widget _action(String label, IconData icon, _Resolution action) =>
      OutlinedButton.icon(
        key: Key('match-$index-${action.name}'),
        onPressed: enabled ? () => onResolve(action) : null,
        icon: Icon(icon, size: 18),
        label: Text(label, textAlign: TextAlign.center),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final food = row.food;
    return Container(
      key: Key('match-row-$index'),
      padding: const EdgeInsets.all(HearthSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(HearthRadius.md),
        border: Border.all(
          color: active ? colors.outlineStrong : colors.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active) Text('Next ingredient', style: context.text.metadata),
          if (row.lineCount > 1) ...[
            Text(
              'Applies to ${row.lineCount} recipe lines',
              style: context.text.label,
            ),
            Text(
              'Choose, skip, or remember once for all these lines.',
              style: context.text.metadata,
            ),
            const SizedBox(height: HearthSpacing.sm),
          ],
          for (final line in row.authoredLines)
            Text(line, style: context.text.ingredient),
          const SizedBox(height: HearthSpacing.sm),
          if (food != null || row.estimate != null)
            Semantics(
              checked: row.accepted,
              label:
                  '${row.authoredLine}. ${food?.name ?? 'AI estimate'}. '
                  '${row.accepted ? 'Included in review' : 'Not included in review'}.',
              onTap: enabled ? () => onAccept(!row.accepted) : null,
              child: InkWell(
                key: Key('match-$index-accept'),
                onTap: enabled ? () => onAccept(!row.accepted) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: HearthSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          row.accepted
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: colors.accent,
                        ),
                      ),
                      const SizedBox(width: HearthSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (food != null) ...[
                              Text(
                                food.brand == null
                                    ? food.name
                                    : '${food.name} · ${food.brand}',
                                style: context.text.body,
                              ),
                              Text(
                                [
                                  _source,
                                  if (food.defaultServing != null)
                                    'per ${food.defaultServing!.label}',
                                  if (row.lineCount == 1 &&
                                      _macrosFor(row.ingredient).isNotEmpty)
                                    _macrosFor(row.ingredient),
                                ].join(' · '),
                                style: context.text.metadata.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              if (row.lineCount > 1)
                                for (final ingredient in row.ingredients)
                                  Text(
                                    '${ingredient.quantity == null ? ingredient.name : QuantityFormat.formatAsAuthored(ingredient.quantity!)}: ${_macrosFor(ingredient)}',
                                    style: context.text.metadata.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                            ] else ...[
                              Text(
                                'Nothing found in a real database · about ${row.estimate!.kcal.round()} kcal'
                                '${row.lineCount > 1 ? ' for ${row.authoredLines.first}' : ''}',
                                style: context.text.body,
                              ),
                              Text(
                                'AI estimate · Hearth\'s own guess — saved as an estimate, never as fact',
                                style: context.text.metadata.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                            if (row.isAmbiguous)
                              Text(
                                'Several fit equally well — check this one',
                                style: context.text.metadata.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            Text(
                              row.accepted
                                  ? 'Included in review'
                                  : 'Not included yet',
                              style: context.text.metadata,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Text(
              'Nothing found. Match it yourself, or leave it.',
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
          if (row.skipped)
            Text(
              'Skipped for now · nutrition remains incomplete',
              style: context.text.metadata,
            ),
          const SizedBox(height: HearthSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = <Widget>[
                _action('Search', Icons.search, _Resolution.search),
                _action(
                  'Scan barcode',
                  Icons.qr_code_scanner,
                  _Resolution.scan,
                ),
                if (canRead)
                  _action(
                    'Read label',
                    Icons.document_scanner_outlined,
                    _Resolution.label,
                  ),
                _action(
                  'Enter nutrition',
                  Icons.edit_outlined,
                  _Resolution.manual,
                ),
                TextButton(
                  key: Key('match-$index-skip'),
                  onPressed: enabled ? onSkip : null,
                  child: const Text(
                    'Skip for now',
                    textAlign: TextAlign.center,
                  ),
                ),
              ];
              return MediaQuery.textScalerOf(context).scale(14) > 20
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final action in actions)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: HearthSpacing.xs,
                            ),
                            child: action,
                          ),
                      ],
                    )
                  : Wrap(
                      spacing: HearthSpacing.sm,
                      runSpacing: HearthSpacing.xs,
                      children: actions,
                    );
            },
          ),
          if (row.resolved)
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                key: Key('match-$index-remember'),
                value: row.remember,
                onChanged: enabled
                    ? (value) => onRemember(value ?? false)
                    : null,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Remember “${row.ingredient.name}” for the household',
                  style: context.text.metadata,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
