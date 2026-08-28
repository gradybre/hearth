import 'package:hearth/domain/models/recipe.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

void main() {
  group('grouped or not (spec §5.2)', () {
    test('a single unnamed section is transparent, not a group', () {
      // Every simple recipe is stored this way. If it counted as grouped, an
      // ordinary recipe would render a header it never asked for.
      expect(aRecipe().isGrouped, isFalse);
    });

    test('two sections is a group', () {
      final Recipe recipe = aRecipe(
        sections: <RecipeSection>[
          aSection(id: 'a'),
          aSection(id: 'b', name: 'Sauce', sortOrder: 1),
        ],
      );
      expect(recipe.isGrouped, isTrue);
    });

    test('one deliberately named section is a group', () {
      final Recipe recipe = aRecipe(
        sections: <RecipeSection>[aSection(id: 'a', name: 'Marinade')],
      );
      expect(recipe.isGrouped, isTrue);
    });

    test('a section reads its own steps in order', () {
      final RecipeSection section = aSection(
        id: 'a',
        steps: <RecipeStep>[
          aStep('second', sectionId: 'a', stepNumber: 2),
          aStep('first', sectionId: 'a', stepNumber: 1),
        ],
      );
      expect(section.orderedSteps.map((RecipeStep s) => s.text), <String>[
        'first',
        'second',
      ]);
    });
  });
}
