import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/step_ingredients.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  importedRecipeBugs();
  crossSectionTests();

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

/// The bugs Brendan photographed in an imported beef-and-broccoli recipe.
///
/// Every case here is taken from that recipe as it actually rendered, because
/// each is a different way word-matching goes wrong and a fix for one does
/// not fix the others.
void importedRecipeBugs() {
  RecipeSection sauceSection({List<RecipeStep> steps = const <RecipeStep>[]}) =>
      aSection(
        id: 'sec-sauce',
        name: 'Sauce',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'low-sodium soy sauce',
            amount: 1.125,
            unit: Units.cup,
            sectionId: 'sec-sauce',
          ),
          anIngredient(
            'unsalted beef broth',
            amount: 1,
            unit: Units.cup,
            sectionId: 'sec-sauce',
          ),
          anIngredient(
            'red pepper flakes',
            amount: 2,
            unit: Units.tsp,
            sectionId: 'sec-sauce',
          ),
          anIngredient(
            'matchstick carrots',
            amount: 3,
            unit: Units.cup,
            sectionId: 'sec-sauce',
          ),
          anIngredient(
            'red bell peppers',
            amount: 3,
            unit: Units.item,
            sectionId: 'sec-sauce',
          ),
          anIngredient(
            '99% lean ground beef',
            amount: 2,
            unit: Units.pound,
            sectionId: 'sec-sauce',
          ),
        ],
        steps: steps,
      );

  List<String> namesFor(String stepText, {RecipeSection? section}) =>
      StepIngredients.forStep(
        aStep(stepText, sectionId: 'sec-sauce'),
        section ?? sauceSection(),
      ).map((RecipeIngredient i) => i.name).toList();

  group('a word inside another ingredient is not a mention', () {
    test('"red pepper flakes" does not drag in the bell peppers', () {
      // Screenshot: step 1 whisks the sauce and listed "3 red bell peppers"
      // among its amounts. It never mentions them — the head noun "pepper"
      // was found inside "red pepper flakes", which is a different thing you
      // buy in a different aisle.
      final List<String> used = namesFor(
        'Whisk soy sauce, honey, rice vinegar, sesame oil, beef broth, '
        'ginger, garlic, and red pepper flakes in the insert. Stir in the '
        'carrots.',
      );

      expect(used, contains('red pepper flakes'));
      expect(used, contains('matchstick carrots'));
      expect(used, contains('low-sodium soy sauce'));
      expect(used, isNot(contains('red bell peppers')));
    });

    test('and the bell peppers are still found when actually named', () {
      final List<String> used = namesFor(
        'Stir the beef and sliced bell peppers into the pot.',
      );
      expect(used, contains('red bell peppers'));
    });

    test('"the beef" is the ground beef, not the beef broth', () {
      // Screenshot: step 2 says "stir the beef in" and showed only peppers.
      // "Beef broth" is a broth — its head noun is broth — so there is no
      // competition here to be conservative about.
      final List<String> used = namesFor(
        'Stir the beef and sliced bell peppers into the pot.',
      );
      expect(used, contains('99% lean ground beef'));
      expect(used, isNot(contains('unsalted beef broth')));
    });
  });

  group('a word for what you are making is not an ingredient', () {
    test('"until the sauce is thick" is not the soy sauce', () {
      // Screenshot: step 3 whisks cornstarch into cold water and listed
      // "1⅛ cups low-sodium soy sauce". Every recipe talks about "the sauce"
      // it is making; only some of them mean the bottle.
      final List<String> used = namesFor(
        'Whisk the cornstarch into the cold water until completely smooth, '
        'then stir in. Lid off, HIGH, 12-15 minutes, until the sauce is '
        'thick and glossy.',
      );
      expect(used, isNot(contains('low-sodium soy sauce')));
    });

    test('but the soy sauce is found when the step says soy sauce', () {
      final List<String> used = namesFor(
        'Whisk soy sauce, honey and rice vinegar in the insert.',
      );
      expect(used, contains('low-sodium soy sauce'));
    });
  });
}

/// A step and its ingredient filed under different headings (spec §5.3).
void crossSectionTests() {
  RecipeSection sauce() => aSection(
    id: 'sec-sauce',
    name: 'Sauce',
    ingredients: <RecipeIngredient>[
      anIngredient(
        'low-sodium soy sauce',
        amount: 1,
        unit: Units.cup,
        sectionId: 'sec-sauce',
      ),
    ],
  );

  RecipeSection finishing() => aSection(
    id: 'sec-finish',
    name: 'Finishing and assembly',
    ingredients: <RecipeIngredient>[
      anIngredient(
        'cornstarch',
        amount: 5,
        unit: Units.tbsp,
        sectionId: 'sec-finish',
      ),
      anIngredient(
        'cold water',
        amount: 8,
        unit: Units.tbsp,
        sectionId: 'sec-finish',
      ),
    ],
  );

  test('a step reaches an ingredient the import filed elsewhere', () {
    // Brendan's recipe whisks the cornstarch in the sauce section while
    // listing the cornstarch under "Finishing and assembly". Scoping then hid
    // the one number the step needed.
    final List<String> used = StepIngredients.forStep(
      aStep(
        'Whisk the cornstarch into the cold water until smooth.',
        sectionId: 'sec-sauce',
      ),
      sauce(),
      elsewhere: <RecipeSection>[sauce(), finishing()],
    ).map((RecipeIngredient i) => i.name).toList();

    expect(used, contains('cornstarch'));
    expect(used, contains('cold water'));
  });

  test('but a name two sections share stays out of reach', () {
    // The ambiguity scoping exists for. Two teaspoons in the sauce and two in
    // the rub must never be read as one another.
    RecipeSection withCumin(String id) => aSection(
      id: id,
      name: id,
      ingredients: <RecipeIngredient>[
        anIngredient('ground cumin', amount: 2, unit: Units.tsp, sectionId: id),
      ],
    );

    final List<RecipeIngredient> used = StepIngredients.forStep(
      aStep('Stir in the cumin', sectionId: 'sec-a'),
      aSection(id: 'sec-a', name: 'A'),
      elsewhere: <RecipeSection>[withCumin('sec-a2'), withCumin('sec-b')],
    );

    expect(used, isEmpty);
  });

  test('the step\'s own section still wins for its own names', () {
    final List<RecipeIngredient> used = StepIngredients.forStep(
      aStep('Whisk the soy sauce in', sectionId: 'sec-sauce'),
      sauce(),
      elsewhere: <RecipeSection>[sauce(), finishing()],
    );

    expect(used.single.sectionId, 'sec-sauce');
  });
}
