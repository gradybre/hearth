import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/mass_display_mode.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/step_amounts.dart';

import '../../support/fixtures.dart';

void main() {
  for (final bool cooking in [false, true]) {
    for (final bool weight in [false, true]) {
      testWidgets(
        'step cooking=$cooking weight=$weight preserves explicit package evidence',
        (tester) async {
          final food = aFood(
            'canned tomatoes',
            id: 'tomatoes',
            massDisplayMode: weight
                ? MassDisplayMode.weight
                : MassDisplayMode.automatic,
          );
          final amount = Quantity.of(3.5, Units.pound);
          final ingredient = RecipeIngredient(
            id: 'i',
            sectionId: 's',
            name: 'canned tomatoes',
            quantity: amount,
            foodId: food.id,
            rawText: '2 (28 oz) cans tomatoes',
            sortOrder: 0,
          );
          final step = aStep('Add the canned tomatoes.', sectionId: 's');
          final section = aSection(
            id: 's',
            ingredients: [ingredient],
            steps: [step],
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: HearthTheme.light(),
              home: Scaffold(
                body: StepAmounts(
                  step: step,
                  section: section,
                  forCooking: cooking,
                  foods: <String, Food>{food.id: food},
                ),
              ),
            ),
          );
          expect(
            find.text('${weight ? '3.5 lb' : '56 oz'} canned tomatoes'),
            findsOneWidget,
          );
          expect(ingredient.quantity!.canonicalAmount, amount.canonicalAmount);
        },
      );
    }
  }
}
