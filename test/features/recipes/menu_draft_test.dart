import 'package:hearth/domain/foods/restaurant_menu.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/parsing/ingredient_parser.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

/// Building a meal from a restaurant's menu (spec §5.2).
///
/// The join worth testing is between two halves that could drift: the lines
/// this writes have to parse back to the names the match map is keyed on. If
/// they ever disagree the bowl arrives looking built and counting nothing.
void main() {
  Food item(String name, num amount, Unit unit, Macros macros) => aFood(
    name,
    id: 'f-${name.toLowerCase()}',
    brand: 'Chipotle',
    source: FoodSource.restaurant,
    servingOptions: <ServingOption>[
      aServing(amount: amount, unit: unit, macros: macros),
    ],
  );

  final Food chicken = item(
    'Chicken',
    4,
    Units.ounce,
    const Macros(kcal: 180, proteinG: 32, fatG: 7),
  );
  final Food rice = item(
    'Cilantro-Lime White Rice',
    4,
    Units.ounce,
    const Macros(kcal: 210, proteinG: 4, carbG: 40, fatG: 4),
  );
  final Food tortilla = item(
    'Flour Tortilla (burrito)',
    1,
    Units.item,
    const Macros(kcal: 320, proteinG: 8, carbG: 50, fatG: 9),
  );

  RecipeDraft built(List<MenuPick> picks) =>
      RecipeDraft.fromMenu(restaurant: 'Chipotle', picks: picks);

  test('arrives eaten out, one serving, and unnamed', () {
    final RecipeDraft draft = built(<MenuPick>[MenuPick(food: chicken)]);

    expect(draft.kind, RecipeKind.eatenOut);
    expect(draft.servings, 1);
    // Only the person who ate it knows what to call it.
    expect(draft.title, isEmpty);
    expect(draft.notes, 'Chipotle');
  });

  test('every line resolves to the food it was picked from', () {
    final RecipeDraft draft = built(<MenuPick>[
      MenuPick(food: chicken, count: 2),
      MenuPick(food: rice),
      MenuPick(food: tortilla),
    ]);

    // Parsed the way the editor parses it, then looked up the way the editor
    // looks it up. Nothing here trusts that the two agree.
    for (final ParsedIngredient parsed in draft.parsedIngredients) {
      expect(
        draft.foodIdFor(parsed.name),
        isNotNull,
        reason: 'no food behind "${parsed.name}"',
      );
    }
  });

  test('and the amounts survive the round trip through text', () {
    final RecipeDraft draft = built(<MenuPick>[
      MenuPick(food: chicken, count: 2),
      MenuPick(food: tortilla),
    ]);
    final Recipe recipe = draft.toRecipe();

    final RecipeIngredient meat = recipe.allIngredients.firstWhere(
      (RecipeIngredient i) => i.name.toLowerCase().contains('chicken'),
    );
    expect(meat.quantity!.amountIn(Units.ounce), closeTo(8, 1e-9));

    // The countable one is the case that would break silently: `Units.item`
    // has an empty label, so a bare "1 Flour Tortilla" would parse as no
    // amount at all and count nothing.
    final RecipeIngredient wrap = recipe.allIngredients.firstWhere(
      (RecipeIngredient i) => i.name.toLowerCase().contains('tortilla'),
    );
    expect(wrap.quantity, isNotNull);
    expect(wrap.quantity!.amountIn(Units.item), closeTo(1, 1e-9));
  });

  group('a component picked in the other direction (spec §5.2)', () {
    final Food lettuce = item(
      'Lettuce',
      0.5,
      Units.ounce,
      const Macros(kcal: 3, carbG: 1),
    );

    test('writes a line that reads back as a deduction', () {
      final MenuPick removed = MenuPick(food: lettuce, count: -1);

      expect(removed.isRemoval, isTrue);
      // A real minus, which is what the parser reads and what a screen reader
      // says out loud — not a hyphen, which is how a bulleted list starts.
      expect(removed.line, startsWith('−'));

      final ParsedIngredient parsed = IngredientParser.parse(removed.line);
      expect(parsed.quantity!.amountIn(Units.ounce), closeTo(-0.5, 1e-9));
      expect(parsed.name, 'Lettuce');
    });

    test('and the food behind it still resolves', () {
      final RecipeDraft draft = built(<MenuPick>[
        MenuPick(food: tortilla),
        MenuPick(food: lettuce, count: -1),
      ]);

      for (final ParsedIngredient parsed in draft.parsedIngredients) {
        expect(
          draft.foodIdFor(parsed.name),
          isNotNull,
          reason: 'no food behind "${parsed.name}"',
        );
      }
    });

    test('and the sign survives being saved and opened again', () {
      // Three parses deep: the builder writes the line, `toRecipe` parses it,
      // and reopening parses the stored raw text a second time. A sign lost at
      // any of them turns "no lettuce" into extra lettuce, silently.
      final Recipe saved = built(<MenuPick>[
        MenuPick(food: chicken),
        MenuPick(food: lettuce, count: -2),
      ]).toRecipe();

      final RecipeIngredient stored = saved.allIngredients.firstWhere(
        (RecipeIngredient i) => i.name == 'Lettuce',
      );
      expect(stored.quantity!.amountIn(Units.ounce), closeTo(-1, 1e-9));

      final RecipeDraft reopened = RecipeDraft.fromRecipe(saved);
      final ParsedIngredient reparsed = reopened.parsedIngredients.firstWhere(
        (ParsedIngredient i) => i.name == 'Lettuce',
      );
      expect(reparsed.quantity!.amountIn(Units.ounce), closeTo(-1, 1e-9));
      expect(reopened.foodIdFor('Lettuce'), lettuce.id);
    });
  });

  test('an empty pick list is an empty recipe, not a broken one', () {
    final RecipeDraft draft = built(const <MenuPick>[]);

    expect(draft.parsedIngredients, isEmpty);
    expect(draft.kind, RecipeKind.eatenOut);
  });
}
