import 'package:flutter/material.dart';

import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/foods/restaurant_menu.dart';
import '../../domain/foods/usual_order_projection.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/recipes/macro_calculator.dart';
import 'usual_order_variation.dart';

/// A review of changes to a saved order, costed from current menu facts.
/// Its parent scrolls this together with the menu at every text size.
class UsualOrderReceipt extends StatelessWidget {
  const UsualOrderReceipt({
    required this.base,
    required this.picks,
    required this.onReset,
    required this.onReview,
    this.needsReset = false,
    super.key,
  });

  final UsualOrderProjection base;
  final List<MenuPick> picks;
  final VoidCallback onReset;
  final VoidCallback? onReview;
  final bool needsReset;

  @override
  Widget build(BuildContext context) {
    final List<UsualOrderChange> changes = UsualOrderChange.between(
      base.picks,
      picks,
    );
    final RecipeMacros baseNutrition = base.nutrition;
    final List<String> conflicts = usualOrderVariationConflicts(
      base: base,
      picks: picks,
    );
    final RecipeMacros? variationNutrition = conflicts.isNotEmpty
        ? null
        : MacroCalculator.forRecipe(
            usualOrderVariation(base: base, picks: picks).toRecipe(),
            foods: <String, Food>{
              for (final UsualOrderComponent component in base.components)
                if (component.food case final Food food) food.id: food,
              for (final MenuPick pick in picks) pick.food.id: pick.food,
            },
          );
    return Container(
      key: const Key('usual-customization-receipt'),
      padding: const EdgeInsets.all(HearthSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceSunken,
        borderRadius: BorderRadius.circular(HearthRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Customize ${base.recipe.title}',
            style: context.text.sectionHeader,
          ),
          const SizedBox(height: HearthSpacing.sm),
          Text(
            'Save a new variation. Your saved usual stays unchanged.',
            style: context.text.body,
          ),
          const SizedBox(height: HearthSpacing.md),
          Text('Base', style: context.text.sectionHeader),
          Text(base.recipe.title, style: context.text.ingredient),
          Text(
            'Whole recipe · ${writeAmount(base.recipe.servings)} '
            '${base.recipe.servings == 1 ? 'serving' : 'servings'}. '
            'Your personal portion is separate.',
            style: context.text.metadata,
          ),
          for (final UsualOrderComponent component in base.components)
            if (component.pick != null)
              Text(
                '${QuantityFormat.formatAsAuthored(component.ingredient.quantity!)} '
                '${component.ingredient.name}',
                style: context.text.body,
              ),
          Text('Current menu nutrition', style: context.text.metadata),
          UsualOrderNutrients(
            macros: baseNutrition.total,
            partial: _partial(baseNutrition),
          ),
          if (baseNutrition.isIncomplete)
            Text(
              'Partial total — some saved components could not be counted.',
              style: context.text.metadata,
            ),
          if (base.unresolved.isNotEmpty) ...<Widget>[
            const SizedBox(height: HearthSpacing.md),
            Text('Needs review', style: context.text.sectionHeader),
            Text(
              'These saved lines stay in the recipe review. They have not '
              'been replaced with menu portions.',
              style: context.text.body,
            ),
            for (final UsualOrderComponent component in base.unresolved)
              Padding(
                padding: const EdgeInsets.only(top: HearthSpacing.sm),
                child: Text(
                  '${component.ingredient.name}: ${component.reason}',
                  style: context.text.body,
                ),
              ),
          ],
          if (needsReset) ...<Widget>[
            const SizedBox(height: HearthSpacing.md),
            Text(
              'Menu portions changed while you were customizing. Reset to '
              'the saved order and review the current amounts before continuing.',
              style: context.text.body,
            ),
          ] else ...<Widget>[
            _Changes(
              title: 'Added',
              changes: changes.where((UsualOrderChange c) => c.added).toList(),
              empty: 'No additions',
            ),
            _Changes(
              title: 'Removed',
              changes: changes.where((UsualOrderChange c) => !c.added).toList(),
              empty: 'No removals',
            ),
            const SizedBox(height: HearthSpacing.md),
            if (variationNutrition != null) ...<Widget>[
              Text('Variation total', style: context.text.sectionHeader),
              UsualOrderNutrients(
                macros: variationNutrition.total,
                partial: _partial(variationNutrition),
              ),
              if (variationNutrition.isIncomplete)
                Text(
                  'Partial total — review the saved lines above.',
                  style: context.text.metadata,
                ),
            ] else ...<Widget>[
              Text(
                'Ingredient names need review',
                style: context.text.sectionHeader,
              ),
              Text(
                '${conflicts.join(', ')}: this name refers to different '
                'saved foods or matching choices. Review it before creating '
                'a variation. Your saved usual is unchanged.',
                style: context.text.body,
              ),
            ],
          ],
          const SizedBox(height: HearthSpacing.md),
          TextButton(
            key: const Key('usual-reset'),
            onPressed: onReset,
            child: const Text(
              'Reset customizations',
              textAlign: TextAlign.center,
            ),
          ),
          FilledButton(
            key: const Key('usual-review-variation'),
            onPressed: needsReset ? null : onReview,
            child: const Text(
              'Review new variation',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _Changes extends StatelessWidget {
  const _Changes({
    required this.title,
    required this.changes,
    required this.empty,
  });

  final String title;
  final List<UsualOrderChange> changes;
  final String empty;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: HearthSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: context.text.sectionHeader),
        if (changes.isEmpty) Text(empty, style: context.text.body),
        for (final UsualOrderChange change in changes)
          Padding(
            padding: const EdgeInsets.only(top: HearthSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(change.pick.food.name, style: context.text.ingredient),
                Text(change.pick.portionLabel, style: context.text.metadata),
                UsualOrderNutrients(macros: change.nutrients, signed: true),
                if (change.pick.food.isModifier)
                  Text(
                    'Published menu adjustment',
                    style: context.text.metadata,
                  )
                else if (!change.added)
                  Text(
                    'Assumption: this component was included in the base '
                    'order. The menu does not confirm that relationship.',
                    style: context.text.metadata,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Null nutrients stay unknown; signed changes preserve each column's sign.
class UsualOrderNutrients extends StatelessWidget {
  const UsualOrderNutrients({
    required this.macros,
    this.signed = false,
    this.partial = const <String>{},
    super.key,
  });

  final Macros? macros;
  final bool signed;
  final Set<String> partial;

  @override
  Widget build(BuildContext context) {
    final Macros? m = macros;
    final List<(String, double?, String)> values = <(String, double?, String)>[
      ('Energy', m?.kcal, 'kcal'),
      ('Protein', m?.proteinG, 'g'),
      ('Carbs', m?.carbG, 'g'),
      ('Fat', m?.fatG, 'g'),
      ('Fibre', m?.fiberG, 'g'),
      ('Sodium', m?.sodiumMg, 'mg'),
      ('Cholesterol', m?.cholesterolMg, 'mg'),
    ];
    return Wrap(
      spacing: HearthSpacing.md,
      runSpacing: HearthSpacing.xs,
      children: <Widget>[
        for (final (String label, double? value, String unit) in values)
          Text(
            '$label ${value == null ? 'unknown' : '${_signed(value)} $unit'}'
            '${value != null && partial.contains(label) ? ' (partial)' : ''}',
            style: context.text.metadata,
          ),
      ],
    );
  }

  String _signed(double value) =>
      '${value < 0
          ? '−'
          : signed && value > 0
          ? '+'
          : ''}${_number(value.abs())}';
}

String _number(double value) =>
    value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

Set<String> _partial(RecipeMacros nutrition) => <String>{
  if (nutrition.unknownCountFor(MinorNutrient.fiber) > 0) 'Fibre',
  if (nutrition.unknownCountFor(MinorNutrient.sodium) > 0) 'Sodium',
  if (nutrition.unknownCountFor(MinorNutrient.cholesterol) > 0) 'Cholesterol',
};
