import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/step_ingredients.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  group('finding the ingredients a step uses', () {
    RecipeSection browning() => aSection(
      id: 'sec-main',
      name: 'Beef',
      ingredients: <RecipeIngredient>[
        anIngredient(
          'ground beef',
          amount: 2,
          unit: Units.pound,
          sectionId: 'sec-main',
        ),
        anIngredient(
          'ground cumin',
          amount: 2,
          unit: Units.tsp,
          sectionId: 'sec-main',
        ),
        anIngredient('salt', optional: true, sectionId: 'sec-main'),
      ],
    );

    test('a step naming an ingredient gets its amount', () {
      final List<RecipeIngredient> used = StepIngredients.forStep(
        aStep('Brown the ground beef in a wide pan', sectionId: 'sec-main'),
        browning(),
      );

      expect(used.map((RecipeIngredient i) => i.name), <String>['ground beef']);
      expect(used.single.quantity!.amountIn(Units.pound), 2);
    });

    test('a shared leading word does not tie two ingredients together', () {
      // "Ground beef" and "ground cumin" share a word that says nothing about
      // what either one is. Matching on any word would put the beef beside a
      // step that only mentions the cumin.
      final List<RecipeIngredient> used = StepIngredients.forStep(
        aStep('Stir in the ground cumin', sectionId: 'sec-main'),
        browning(),
      );

      expect(used.map((RecipeIngredient i) => i.name), <String>[
        'ground cumin',
      ]);
    });

    test('an ingredient with no amount is not offered', () {
      // "Salt to taste" has no number to show, so saying anything about it
      // beside the step is noise.
      final List<RecipeIngredient> used = StepIngredients.forStep(
        aStep('Season with salt', sectionId: 'sec-main'),
        browning(),
      );
      expect(used, isEmpty);
    });

    test('a step naming nothing in the list gets nothing', () {
      expect(
        StepIngredients.forStep(
          aStep('Let it rest for ten minutes', sectionId: 'sec-main'),
          browning(),
        ),
        isEmpty,
      );
    });

    test('a plural in either place still matches', () {
      final RecipeSection section = aSection(
        id: 'sec',
        ingredients: <RecipeIngredient>[
          anIngredient('eggs', amount: 2, unit: Units.item, sectionId: 'sec'),
          anIngredient(
            'yellow onion',
            amount: 1,
            unit: Units.item,
            sectionId: 'sec',
          ),
        ],
      );

      expect(
        StepIngredients.forStep(
          aStep('Crack the egg into the bowl', sectionId: 'sec'),
          section,
        ).single.name,
        'eggs',
      );
      // And the other way: the list says "onion", the step says "onions".
      expect(
        StepIngredients.forStep(
          aStep('Soften the onions', sectionId: 'sec'),
          section,
        ).single.name,
        'yellow onion',
      );
    });

    test('a descriptive name is found by its plain head noun', () {
      final RecipeSection section = aSection(
        id: 'sec',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'extra virgin olive oil',
            amount: 2,
            unit: Units.tbsp,
            sectionId: 'sec',
          ),
        ],
      );

      expect(
        StepIngredients.forStep(
          aStep('Heat the oil over medium', sectionId: 'sec'),
          section,
        ).single.name,
        'extra virgin olive oil',
      );
    });
  });

  group('the amounts stay separated by section', () {
    // Brendan's requirement, and the reason this is scoped to a section at
    // all: two teaspoons in the sauce and two in the rub is two teaspoons in
    // each step, never the four that adding them would produce.
    RecipeSection sauce() => aSection(
      id: 'sec-sauce',
      name: 'Sauce',
      ingredients: <RecipeIngredient>[
        anIngredient(
          'ground cumin',
          amount: 2,
          unit: Units.tsp,
          sectionId: 'sec-sauce',
        ),
      ],
      steps: <RecipeStep>[
        aStep('Whisk the cumin into the sauce', sectionId: 'sec-sauce'),
      ],
    );

    RecipeSection rub() => aSection(
      id: 'sec-rub',
      name: 'Rub',
      ingredients: <RecipeIngredient>[
        anIngredient(
          'ground cumin',
          amount: 2,
          unit: Units.tsp,
          sectionId: 'sec-rub',
        ),
      ],
      steps: <RecipeStep>[
        aStep('Rub the cumin over the beef', sectionId: 'sec-rub'),
      ],
    );

    test('each section reports only its own amount', () {
      final RecipeIngredient inSauce = StepIngredients.forStep(
        sauce().steps.single,
        sauce(),
      ).single;
      final RecipeIngredient inRub = StepIngredients.forStep(
        rub().steps.single,
        rub(),
      ).single;

      expect(inSauce.quantity!.amountIn(Units.tsp), 2);
      expect(inRub.quantity!.amountIn(Units.tsp), 2);
    });

    test("a step never sees another section's ingredients", () {
      // The sauce's step, checked against the rub's ingredients, must not
      // pick anything up just because both sections use cumin.
      final List<RecipeIngredient> crossed = StepIngredients.forStep(
        sauce().steps.single,
        aSection(
          id: 'sec-other',
          ingredients: <RecipeIngredient>[
            anIngredient(
              'ground beef',
              amount: 2,
              unit: Units.pound,
              sectionId: 'sec-other',
            ),
          ],
        ),
      );
      expect(crossed, isEmpty);
    });
  });
}
