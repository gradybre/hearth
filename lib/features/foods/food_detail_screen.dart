import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/theme/hearth_typography.dart';
import '../../app/widgets/centred_message.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';

/// A read-only destination for the current library food behind a planned meal.
/// A removed planned serving is explained, never silently changed on the plan.
class FoodDetailScreen extends ConsumerWidget {
  const FoodDetailScreen({
    required this.foodId,
    this.servingOptionId,
    super.key,
  });

  final String foodId;
  final String? servingOptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Food?> food = ref.watch(foodByIdProvider(foodId));
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: food.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(
            child: CircularProgressIndicator(semanticsLabel: 'Loading food'),
          ),
          error: (Object error, StackTrace stack) => _FoodMessage(
            title: 'Could not open this food',
            message: 'Try loading it again.',
            onRetry: () => ref.invalidate(foodByIdProvider(foodId)),
          ),
          data: (Food? loaded) => loaded == null || loaded.isDeleted
              ? const _FoodMessage(
                  title: 'Food unavailable',
                  message:
                      'This food is no longer available in the library. '
                      'Your plan and saved logs have not changed.',
                )
              : _FoodSummary(food: loaded, servingOptionId: servingOptionId),
        ),
      ),
    );
  }
}

class _FoodSummary extends StatelessWidget {
  const _FoodSummary({required this.food, required this.servingOptionId});

  final Food food;
  final String? servingOptionId;

  static bool _usable(ServingOption serving) =>
      !serving.isReference &&
      serving.amount.canonicalAmount.isFinite &&
      serving.amount.canonicalAmount > 0 &&
      (serving.amount.preferredUnit == null ||
          serving.amount.preferredUnit!.kind == serving.amount.kind);

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final HearthTextStyles text = context.text;
    final ServingOption? requested = servingOptionId == null
        ? null
        : food.servingOptions
              .where((ServingOption serving) => serving.id == servingOptionId)
              .firstOrNull;
    final ServingOption? serving = requested != null && _usable(requested)
        ? requested
        : food.servingOptions.where(_usable).firstOrNull;
    final bool missingPlannedServing =
        servingOptionId != null && requested == null;
    final bool unusablePlannedServing =
        requested != null && !_usable(requested);
    final String basis = serving == null
        ? 'Current serving'
        : serving.id == food.defaultServing?.id
        ? 'Current default serving'
        : 'Current serving';
    final String? brand = food.brand?.trim();

    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HearthLayout.launcherWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(HearthSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(food.name, style: text.recipeTitle),
                ),
                if (brand != null && brand.isNotEmpty) ...<Widget>[
                  const SizedBox(height: HearthSpacing.sm),
                  Text(brand, style: text.body),
                ],
                const SizedBox(height: HearthSpacing.sm),
                Text(
                  'Source: ${_sourceLabel(food.source)}',
                  style: text.body.copyWith(color: colors.textSecondary),
                ),
                if (food.macrosOverridden)
                  Text(
                    'Nutrition corrected in your household.',
                    style: text.body.copyWith(color: colors.textSecondary),
                  ),
                const SizedBox(height: HearthSpacing.lg),
                Text(
                  'Current library values, not a past log.',
                  style: text.body.copyWith(color: colors.textSecondary),
                ),
                if (missingPlannedServing ||
                    unusablePlannedServing) ...<Widget>[
                  const SizedBox(height: HearthSpacing.lg),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      missingPlannedServing
                          ? 'The serving selected in your plan is no longer '
                                'available. Your plan has not changed.'
                          : 'The serving selected in your plan cannot be read. '
                                'Your plan has not changed.',
                      style: text.body,
                    ),
                  ),
                ],
                const SizedBox(height: HearthSpacing.xl),
                if (serving == null) ...<Widget>[
                  Semantics(
                    header: true,
                    child: Text('No usable serving', style: text.sectionHeader),
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                  Text(
                    'This food has no usable serving size yet, so a nutrition '
                    'summary is not available.',
                    style: text.body,
                  ),
                ] else ...<Widget>[
                  Semantics(
                    header: true,
                    child: Text(basis, style: text.sectionHeader),
                  ),
                  const SizedBox(height: HearthSpacing.sm),
                  if (serving.label.trim().isNotEmpty)
                    Text(serving.label, style: text.body),
                  Text(
                    'Per ${QuantityFormat.formatAsAuthored(serving.amount)}',
                    style: text.body,
                  ),
                  if (food.needsAttention) ...<Widget>[
                    const SizedBox(height: HearthSpacing.sm),
                    Text(
                      'Nutrition may be incomplete. Zero calories have not '
                      'been confirmed for this food.',
                      style: text.body.copyWith(color: colors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: HearthSpacing.lg),
                  _Nutrient(
                    label: 'Calories',
                    value: serving.macros.kcal,
                    unit: 'kcal',
                  ),
                  _Nutrient(
                    label: 'Protein',
                    value: serving.macros.proteinG,
                    unit: 'g',
                  ),
                  _Nutrient(
                    label: 'Carbohydrate',
                    value: serving.macros.carbG,
                    unit: 'g',
                  ),
                  _Nutrient(
                    label: 'Fat',
                    value: serving.macros.fatG,
                    unit: 'g',
                  ),
                  for (final MinorNutrient nutrient in MinorNutrient.values)
                    _Nutrient(
                      label: nutrient.label,
                      value: serving.macros.minor(nutrient),
                      unit: nutrient.unit,
                    ),
                ],
                const SizedBox(height: HearthSpacing.xl),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _sourceLabel(FoodSource source) => switch (source) {
    FoodSource.openFoodFacts => 'Open Food Facts',
    FoodSource.usda => 'USDA',
    FoodSource.manual => 'Entered by hand',
    FoodSource.aiEstimate => 'AI estimate',
    FoodSource.restaurant => 'Restaurant nutrition',
  };
}

class _Nutrient extends StatelessWidget {
  const _Nutrient({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final double? value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final double? amount = value;
    final String reading = amount == null || !amount.isFinite
        ? 'Unknown'
        : '${_number(amount)} $unit';
    return Semantics(
      label: '$label: $reading',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HearthSpacing.sm),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget name = Text(label, style: context.text.body);
            final Widget number = Text(reading, style: context.text.ingredient);
            if (MediaQuery.textScalerOf(context).scale(16) > 24) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[name, number],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: name),
                const SizedBox(width: HearthSpacing.md),
                Flexible(child: number),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _number(double value) {
    final String number = value
        .abs()
        .toStringAsFixed(1)
        .replaceFirst(RegExp(r'\.0$'), '');
    return value < 0 ? '−$number' : number;
  }
}

class _FoodMessage extends StatelessWidget {
  const _FoodMessage({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => CentredMessage(
    children: <Widget>[
      Semantics(
        header: true,
        child: Text(
          title,
          style: context.text.sectionHeader,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: HearthSpacing.sm),
      Text(message, style: context.text.body, textAlign: TextAlign.center),
      const SizedBox(height: HearthSpacing.lg),
      if (onRetry != null) ...<Widget>[
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
        const SizedBox(height: HearthSpacing.sm),
      ],
      OutlinedButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Go back'),
      ),
    ],
  );
}
