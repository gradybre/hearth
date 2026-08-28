import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';
import 'package:test/test.dart';

/// Stable ids so a test can assert structure rather than uuids.
String Function() sequentialIds() {
  int next = 0;
  return () => 'id-${next++}';
}

RecipeDraft draft({
  String title = 'Braised short ribs',
  double servings = 4,
  String ingredients = '2 tbsp olive oil\n3 cloves garlic, minced',
  String directions = 'Season the ribs generously and sear them until browned.',
  int? prepMinutes,
  int? cookMinutes,
  String? cuisine,
  List<String> tags = const <String>[],
}) => RecipeDraft(
  title: title,
  servings: servings,
  ingredientsText: ingredients,
  directionsText: directions,
  prepMinutes: prepMinutes,
  cookMinutes: cookMinutes,
  cuisine: cuisine,
  tags: tags,
);

void main() {
  group('validation', () {
    test('a title is required', () {
      expect(draft(title: '   ').titleError, isNotNull);
      expect(draft(title: '   ').isValid, isFalse);
      expect(draft().titleError, isNull);
    });

    test('servings must be positive', () {
      expect(draft(servings: 0).servingsError, isNotNull);
      expect(draft(servings: -1).isValid, isFalse);
    });

    test('everything else is optional', () {
      // Missing data flags, never blocks (spec §5.3) — that applies to the
      // user's own typing too.
      final RecipeDraft bare = draft(ingredients: '', directions: '');
      expect(bare.isValid, isTrue);
      expect(bare.toRecipe(idFactory: sequentialIds()).allIngredients, isEmpty);
    });
  });

  group('building a recipe', () {
    test('parses ingredient lines into structured fields', () {
      final Recipe recipe = draft().toRecipe(idFactory: sequentialIds());
      final List<RecipeIngredient> ingredients = recipe.allIngredients;

      expect(ingredients, hasLength(2));
      expect(ingredients.first.name, 'olive oil');
      expect(ingredients.first.quantity!.amountIn(Units.tbsp), 2);
      expect(ingredients[1].name, 'garlic');
      expect(ingredients[1].prepNote, 'minced');
      expect(ingredients[1].quantity!.amountIn(Units.clove), 3);
    });

    test('keeps the raw line so an edit shows what was typed', () {
      final Recipe recipe = draft().toRecipe(idFactory: sequentialIds());
      expect(recipe.allIngredients.first.rawText, '2 tbsp olive oil');
    });

    test('marks to-taste lines optional', () {
      final Recipe recipe = draft(
        ingredients: '2 tbsp olive oil\nsalt to taste',
      ).toRecipe(idFactory: sequentialIds());

      expect(recipe.allIngredients.last.isOptional, isTrue);
      expect(recipe.allIngredients.last.quantity, isNull);
    });

    test('splits directions into numbered steps', () {
      final Recipe recipe = draft().toRecipe(idFactory: sequentialIds());
      expect(recipe.allSteps, hasLength(2));
      expect(recipe.allSteps.first.stepNumber, 1);
      expect(recipe.allSteps.first.text, 'Season the ribs generously');
      expect(recipe.allSteps.last.stepNumber, 2);
    });

    test('blank ingredient lines are skipped', () {
      final Recipe recipe = draft(
        ingredients: '2 tbsp olive oil\n\n   \n3 cloves garlic',
      ).toRecipe(idFactory: sequentialIds());
      expect(recipe.allIngredients, hasLength(2));
    });

    test('everything lands in one transparent default section', () {
      final Recipe recipe = draft().toRecipe(idFactory: sequentialIds());
      expect(recipe.sections, hasLength(1));
      expect(recipe.sections.single.name, Recipe.defaultSectionName);
      expect(
        recipe.allIngredients.every(
          (RecipeIngredient i) => i.sectionId == recipe.sections.single.id,
        ),
        isTrue,
      );
    });

    test('times and metadata carry through', () {
      final Recipe recipe = draft(
        prepMinutes: 30,
        cookMinutes: 180,
        cuisine: 'French',
        tags: <String>['weeknight'],
      ).toRecipe(idFactory: sequentialIds());

      expect(recipe.prepTime, const Duration(minutes: 30));
      expect(recipe.cookTime, const Duration(minutes: 180));
      expect(recipe.totalTime, const Duration(minutes: 210));
      expect(recipe.cuisine, 'French');
      expect(recipe.tags, <String>['weeknight']);
    });

    test('blank optional text becomes null rather than an empty string', () {
      final Recipe recipe = draft(cuisine: '   ')
          .toRecipe(idFactory: sequentialIds());
      expect(recipe.cuisine, isNull);
    });

    test('the title is trimmed', () {
      final Recipe recipe = draft(title: '  Short ribs  ')
          .toRecipe(idFactory: sequentialIds());
      expect(recipe.title, 'Short ribs');
    });
  });

  group('editing an existing recipe', () {
    test('keeps the same id so a save updates rather than duplicates', () {
      final Recipe original = draft().toRecipe(idFactory: sequentialIds());
      final RecipeDraft reopened = RecipeDraft.fromRecipe(original);

      expect(reopened.isEditing, isTrue);
      expect(reopened.toRecipe(idFactory: sequentialIds()).id, original.id);
    });

    test('reopens showing the lines the user originally typed', () {
      final Recipe original = draft().toRecipe(idFactory: sequentialIds());
      final RecipeDraft reopened = RecipeDraft.fromRecipe(original);

      expect(
        reopened.ingredientsText,
        '2 tbsp olive oil\n3 cloves garlic, minced',
      );
    });

    test('reopens directions already numbered', () {
      final Recipe original = draft().toRecipe(idFactory: sequentialIds());
      final RecipeDraft reopened = RecipeDraft.fromRecipe(original);

      expect(reopened.directionsText, startsWith('1. Season the ribs'));
      // Re-parsing numbered text must not re-split it (the parser transcribes
      // existing structure), so a round trip is stable.
      expect(
        reopened.toRecipe(idFactory: sequentialIds()).allSteps.length,
        original.allSteps.length,
      );
    });

    test('a full round trip preserves the ingredient list', () {
      final Recipe original = draft().toRecipe(idFactory: sequentialIds());
      final Recipe reSaved = RecipeDraft.fromRecipe(original)
          .toRecipe(idFactory: sequentialIds());

      expect(
        reSaved.allIngredients.map((RecipeIngredient i) => i.name),
        original.allIngredients.map((RecipeIngredient i) => i.name),
      );
      expect(
        reSaved.allIngredients.first.quantity!.canonicalAmount,
        original.allIngredients.first.quantity!.canonicalAmount,
      );
    });

    test('reuses the section id so ingredients keep a valid parent', () {
      final Recipe original = draft().toRecipe(idFactory: sequentialIds());
      final Recipe reSaved = RecipeDraft.fromRecipe(original)
          .toRecipe(idFactory: sequentialIds());

      expect(reSaved.sections.single.id, original.sections.single.id);
    });
  });

  group('step timers come across from the text (spec §5.2)', () {
    test('a step that states a duration arrives with a timer', () {
      // Otherwise timer_seconds is only ever set by hand and cook-along's
      // timers go unused, which is the same as not having them.
      final Recipe recipe = draft(
        directions: '1. Season the ribs\n2. Cover and cook for 3 hr.',
      ).toRecipe(idFactory: sequentialIds());

      final List<RecipeStep> steps = recipe.allSteps;
      expect(steps.first.hasTimer, isFalse);
      expect(steps.last.timerSeconds, 10800);
    });
  });
}
