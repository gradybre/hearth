import 'package:flutter/material.dart';

import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../app/widgets/reading_column.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/nutrient_coverage.dart';
import '../../domain/recipes/macro_calculator.dart';
import '../../domain/recipes/recipe_nutrition_receipt.dart';
import '../../domain/units/quantity.dart';
import 'macro_stats_row.dart';

/// The same nutrition basis, coverage and explanation entry in the reader
/// and the editor. Callers own the chosen basis and the displayed recipe.
class RecipeNutritionSummary extends StatelessWidget {
  const RecipeNutritionSummary({
    required this.recipe,
    required this.macros,
    required this.wholeDish,
    required this.onChanged,
    required this.foods,
    this.authoredRecipe,
    this.isDraft = false,
    super.key,
  });

  final Recipe recipe;
  final RecipeMacros macros;
  final bool wholeDish;
  final ValueChanged<bool> onChanged;
  final Map<String, Food> foods;
  final Recipe? authoredRecipe;
  final bool isDraft;

  void _explain(BuildContext context) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => RecipeNutritionReceiptScreen(
        receipt: RecipeNutritionReceipt(
          recipe: recipe,
          authoredRecipe: authoredRecipe,
          calculation: macros,
          foods: foods,
          wholeDish: wholeDish,
        ),
        isDraft: isDraft,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bool validYield = recipe.servings.isFinite && recipe.servings > 0;
    final Macros shown = wholeDish ? macros.total : macros.perServing;
    final int resolved = macros.ingredients
        .where((IngredientMacros i) => i.isResolved)
        .length;
    final int counted = macros.ingredients
        .where((IngredientMacros i) => i.isResolved || i.isDataGap)
        .length;
    final bool canShowNumbers = resolved > 0 && (wholeDish || validYield);
    final String yield = validYield
        ? '${_number(recipe.servings)} ${recipe.servings == 1 ? 'serving' : 'servings'}'
        : 'Recipe yield needs a positive number of servings';
    final String qualification = macros.isIncomplete ? ' known' : '';
    final String approximation = macros.usesApproximatePackageNutrition
        ? 'about '
        : '';
    final String basis = validYield && resolved > 0
        ? '$yield · $approximation${macros.perServing.kcal.round()} kcal each$qualification · '
              '$approximation${macros.total.kcal.round()} kcal whole dish$qualification'
        : yield;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Tooltip(
          message: 'How this is calculated',
          child: TextButton(
            key: const ValueKey<String>('recipe-nutrition-receipt'),
            onPressed: () => _explain(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(
                HearthTouch.androidTarget,
                HearthTouch.androidTarget,
              ),
              alignment: Alignment.centerLeft,
            ),
            child: Wrap(
              spacing: HearthSpacing.sm,
              runSpacing: HearthSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  'Nutrition',
                  style: context.text.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.info_outline, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: HearthSpacing.sm),
        Wrap(
          spacing: HearthSpacing.sm,
          runSpacing: HearthSpacing.xs,
          children: <Widget>[
            _NutritionBasisChip(
              label: 'Per serving',
              selected: !wholeDish,
              onSelected: (_) => onChanged(false),
            ),
            _NutritionBasisChip(
              label: 'Whole dish',
              selected: wholeDish,
              onSelected: (_) => onChanged(true),
            ),
          ],
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          basis,
          style: context.text.metadata.copyWith(
            color: context.colors.textMuted,
          ),
        ),
        const SizedBox(height: HearthSpacing.sm),
        if (canShowNumbers) ...<Widget>[
          if (macros.isIncomplete)
            TextButton(
              key: const ValueKey<String>('recipe-nutrition-coverage'),
              onPressed: () => _explain(context),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(
                  HearthTouch.androidTarget,
                  HearthTouch.androidTarget,
                ),
                alignment: Alignment.centerLeft,
              ),
              child: Text(
                'Known nutrition · $resolved of $counted ingredients counted',
                style: context.text.metadata,
              ),
            ),
          if (MediaQuery.textScalerOf(context).scale(14) <= 21)
            MacroStatsRow(macros: shown)
          else
            for (final (String label, double value) in <(String, double)>[
              ('kcal', shown.kcal),
              ('g protein', shown.proteinG),
              ('g carbs', shown.carbG),
              ('g fat', shown.fatG),
            ])
              Text('${value.round()} $label', style: context.text.ingredient),
          if (shown.knowsAnyMinor) ...<Widget>[
            const SizedBox(height: HearthSpacing.sm),
            MinorNutrientsLine(
              macros: shown,
              partialFor: (MinorNutrient nutrient) =>
                  macros.partialNoteFor(nutrient) ??
                  (macros.coverage.of(nutrient) == MinorCoverage.partial
                      ? 'Some ingredients are not counted'
                      : null),
            ),
          ],
        ] else
          Text(
            !wholeDish && !validYield
                ? 'Set a recipe yield to see nutrition per serving.'
                : counted == 0
                ? 'No nutrition-counting ingredients.'
                : 'Nutrition not available yet',
            style: context.text.body,
          ),
        if (macros.usesApproximatePackageNutrition) ...<Widget>[
          const SizedBox(height: HearthSpacing.xs),
          Text(
            'Uses approximate package servings',
            style: context.text.metadata,
          ),
        ],
        if (macros.incompleteReason case final String reason) ...<Widget>[
          const SizedBox(height: HearthSpacing.sm),
          Text(
            reason,
            style: context.text.metadata.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// A selected chip's built-in checkmark takes width away from a single-line
/// label. Keep the check and complete words together in a wrapping label.
class _NutritionBasisChip extends StatelessWidget {
  const _NutritionBasisChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      const double horizontalPadding = HearthSpacing.sm * 4;
      final double labelWidth = constraints.maxWidth > horizontalPadding
          ? constraints.maxWidth - horizontalPadding
          : 0;
      return ChoiceChip(
        selected: selected,
        onSelected: onSelected,
        showCheckmark: false,
        padding: const EdgeInsets.all(HearthSpacing.sm),
        labelPadding: const EdgeInsets.symmetric(horizontal: HearthSpacing.sm),
        // Chip measures label height before subtracting its padding. Give
        // both measurements the same width so a wrapped check/label grows
        // the chip instead of painting below its tappable surface.
        label: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: labelWidth),
          child: Wrap(
            spacing: HearthSpacing.xs,
            runSpacing: HearthSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (selected)
                Builder(
                  builder: (BuildContext context) => Icon(
                    Icons.check,
                    size: 18,
                    color: DefaultTextStyle.of(context).style.color,
                  ),
                ),
              Text(label),
            ],
          ),
        ),
      );
    },
  );
}

/// A snapshot of the current calculation, not a log or a matching workflow.
class RecipeNutritionReceiptScreen extends StatelessWidget {
  const RecipeNutritionReceiptScreen({
    required this.receipt,
    this.isDraft = false,
    super.key,
  });

  final RecipeNutritionReceipt receipt;
  final bool isDraft;

  @override
  Widget build(BuildContext context) {
    final String basis = receipt.wholeDish ? 'Whole dish' : 'Per serving';
    final Recipe recipe = receipt.recipe;
    final RecipeMacros calculation = receipt.calculation;
    final Macros? shown = receipt.shown;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        leading: const BackButton(key: ValueKey<String>('receipt-back')),
        title: const SizedBox.shrink(),
      ),
      body: SafeArea(
        child: ReadingColumn(
          child: ListView(
            key: const ValueKey<String>('recipe-nutrition-receipt-list'),
            padding: const EdgeInsets.all(HearthSpacing.lg),
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  'Nutrition details',
                  style: context.text.sectionHeader,
                ),
              ),
              const SizedBox(height: HearthSpacing.sm),
              Text(recipe.title, style: context.text.sectionHeader),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                isDraft ? 'Current editor preview' : 'Current recipe facts',
                style: context.text.metadata,
              ),
              const SizedBox(height: HearthSpacing.lg),
              Text(basis, style: context.text.sectionHeader),
              Text(
                receipt.hasValidYield
                    ? 'Displayed yield: ${_number(recipe.servings)} ${recipe.servings == 1 ? 'serving' : 'servings'}.'
                    : 'Yield is not set. Per serving needs a positive recipe yield.',
                style: context.text.body,
              ),
              if (receipt.isScaled)
                Text(
                  'As written: ${_number(receipt.authoredRecipe.servings)} servings. '
                  'Whole dish is scaled to ${_number(recipe.servings)} servings; '
                  'Per serving is unchanged.',
                  style: context.text.body,
                ),
              const SizedBox(height: HearthSpacing.sm),
              Text(
                'Ingredient amounts and serving multipliers describe the whole dish. '
                'Contributions below are ${receipt.wholeDish ? 'for the Whole dish' : 'Per serving'}.',
                style: context.text.body,
              ),
              if (calculation.usesApproximatePackageNutrition)
                Text(
                  'Uses approximate package servings',
                  style: context.text.body,
                ),
              const SizedBox(height: HearthSpacing.lg),
              if (shown != null) ...<Widget>[
                Text(
                  calculation.isIncomplete
                      ? 'Known contributions · ${receipt.resolvedCount} of ${receipt.requiredCount} ingredients counted'
                      : '${receipt.resolvedCount} ${receipt.resolvedCount == 1 ? 'ingredient' : 'ingredients'} counted',
                  style: context.text.label,
                ),
                _ReceiptNutrients(
                  macros: shown,
                  coverage: calculation.coverage,
                ),
              ] else
                Text(
                  !receipt.wholeDish && !receipt.hasValidYield
                      ? 'Per-serving nutrition is unavailable until the yield is set.'
                      : receipt.requiredCount == 0
                      ? 'No nutrition-counting ingredients.'
                      : 'Nutrition is not available yet. Missing ingredients are not zero-calorie ingredients.',
                  style: context.text.body,
                ),
              if (calculation.incompleteReason case final String reason)
                Text(reason, style: context.text.body),
              const SizedBox(height: HearthSpacing.xl),
              for (int i = 0; i < receipt.ingredients.length; i++) ...<Widget>[
                Divider(color: context.colors.outline),
                Padding(
                  key: ValueKey<String>('receipt-ingredient-$i'),
                  padding: const EdgeInsets.symmetric(
                    vertical: HearthSpacing.lg,
                  ),
                  child: _IngredientReceipt(row: receipt.ingredients[i]),
                ),
              ],
              const SizedBox(height: HearthSpacing.lg),
              Text(
                'These are current recipe facts. Past logs keep their saved nutrition.',
                style: context.text.metadata.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IngredientReceipt extends StatelessWidget {
  const _IngredientReceipt({required this.row});

  final IngredientNutritionReceipt row;

  @override
  Widget build(BuildContext context) {
    final IngredientMacros part = row.calculation;
    final Food? food = row.food;
    final ServingOption? serving = part.serving;
    final Quantity? authored = row.authored.quantity;
    final Quantity? displayed = part.ingredient.quantity;
    final Macros? contribution = row.contribution;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(row.authored.name, style: context.text.sectionHeader),
        ),
        const SizedBox(height: HearthSpacing.sm),
        Text(
          authored == null
              ? 'As written: amount not specified'
              : 'As written: ${QuantityFormat.formatAsAuthored(authored)}',
          style: context.text.body,
        ),
        if (authored != null &&
            displayed != null &&
            authored.canonicalAmount != displayed.canonicalAmount)
          Text(
            'Displayed amount: ${QuantityFormat.formatAsAuthored(displayed)}',
            style: context.text.body,
          ),
        Text(
          food != null
              ? 'Matched food: ${food.name}'
              : part.ingredient.foodId == null
              ? 'No food matched'
              : 'Matched food is unavailable',
          style: context.text.body,
        ),
        if (food != null)
          Text(
            'Source: ${switch (food.source) {
              FoodSource.openFoodFacts => 'Open Food Facts',
              FoodSource.usda => 'USDA FoodData Central',
              FoodSource.manual => 'Entered manually',
              FoodSource.aiEstimate => 'AI estimate',
              FoodSource.restaurant => 'Published restaurant nutrition',
            }}',
            style: context.text.body,
          ),
        if (serving != null && part.servingCount != null) ...<Widget>[
          Text(
            'Serving basis: ${_servingBasis(serving)} · ${_value(serving.macros.kcal)} kcal',
            style: context.text.body,
          ),
          Text(
            'Calculation amount: ${_multiplier(part.servingCount!, approximate: part.usesApproximatePackage)} × ${serving.label}',
            style: context.text.body,
          ),
        ],
        if (part.usesApproximatePackage)
          Text('Uses approximate package servings', style: context.text.body),
        const SizedBox(height: HearthSpacing.sm),
        if (contribution != null) ...<Widget>[
          Text(
            '${contribution.isBelowNothing ? 'Included adjustment' : 'Included'} · '
            '${row.wholeDish ? 'Whole dish' : 'Per serving'}',
            style: context.text.label,
          ),
          _ReceiptNutrients(macros: contribution),
        ] else
          Text(_reason(part, food), style: context.text.body),
      ],
    );
  }

  static String _reason(IngredientMacros part, Food? food) =>
      switch (part.status) {
        IngredientMacroStatus.optionalExcluded =>
          'Optional ingredient — excluded from nutrition.',
        IngredientMacroStatus.noMatchNeeded =>
          'Excluded — marked as needing no nutrition match.',
        IngredientMacroStatus.noQuantity =>
          'Amount not specified — contribution is unknown, not zero.',
        IngredientMacroStatus.noFoodMatch =>
          food != null && food.servingOptions.isEmpty
              ? 'This food has no nutrition serving — contribution is unknown, not zero.'
              : part.ingredient.foodId == null
              ? 'No food match — contribution is unknown, not zero.'
              : 'The matched food is unavailable — contribution is unknown, not zero.',
        IngredientMacroStatus.unconvertible => 'No compatible serving for this amount and unit — contribution is unknown, not zero.',
        IngredientMacroStatus.resolved => 'Included in the Whole dish. Per serving is unavailable until the yield is set.',
      };
}

class _ReceiptNutrients extends StatelessWidget {
  const _ReceiptNutrients({required this.macros, this.coverage});

  final Macros macros;
  final NutrientCoverage? coverage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (final (String label, double value) in <(String, double)>[
        ('kcal', macros.kcal),
        ('g protein', macros.proteinG),
        ('g carbs', macros.carbG),
        ('g fat', macros.fatG),
      ])
        Text('${_value(value)} $label', style: context.text.body),
      for (final MinorNutrient nutrient in MinorNutrient.values)
        Text(
          macros.minor(nutrient) == null
              ? '${nutrient.label}: not stated'
              : '${nutrient.label}: ${_value(macros.minor(nutrient)!)} ${nutrient.unit}'
                    '${coverage?.of(nutrient) == MinorCoverage.partial ? ' known · partial' : ''}',
          style: context.text.body,
        ),
    ],
  );
}

String _servingBasis(ServingOption serving) {
  final String amount = QuantityFormat.formatAsAuthored(serving.amount);
  final String label = serving.label.trim();
  return label.isEmpty || label == amount ? amount : '$label ($amount)';
}

// This explains arithmetic, so kitchen-fraction snapping would change the
// stated calculation. Qualify any decimal shortening as an approximation.
String _multiplier(double value, {required bool approximate}) {
  final List<String> pieces = value.toStringAsPrecision(6).split('e');
  final String mantissa = pieces.first.contains('.')
      ? pieces.first.replaceFirst(RegExp(r'\.?0+$'), '')
      : pieces.first;
  final String number = pieces.length == 1
      ? mantissa
      : '${mantissa}e${pieces.last}';
  final bool rounded = double.tryParse(number) != value;
  return '${approximate || rounded ? 'about ' : ''}${number.replaceFirst('-', '−')}';
}

// Cooking fractions are useful for ordinary portions, but a receipt must
// never describe a small, nonzero contribution as zero servings.
String _number(double value) => value != 0 && value.abs() < 0.1
    ? _value(value)
    : QuantityFormat.count(value);

String _value(double value) {
  if (value < 0) return '−${_value(-value)}';
  if (value == value.roundToDouble()) return value.round().toString();
  final String formatted = value < 1
      ? value.toStringAsPrecision(2)
      : value.toStringAsFixed(1);
  return formatted.contains('.') && !formatted.contains('e')
      ? formatted.replaceFirst(RegExp(r'\.?0+$'), '')
      : formatted;
}
