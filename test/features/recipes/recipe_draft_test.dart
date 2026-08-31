import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/quantity.dart';
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
  List<DraftSection>? sections,
}) => RecipeDraft(
  title: title,
  servings: servings,
  sections:
      sections ??
      <DraftSection>[
        DraftSection(ingredientsText: ingredients, directionsText: directions),
      ],
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
        reopened.sections.single.ingredientsText,
        '2 tbsp olive oil\n3 cloves garlic, minced',
      );
    });

    test('reopens directions already numbered', () {
      final Recipe original = draft().toRecipe(idFactory: sequentialIds());
      final RecipeDraft reopened = RecipeDraft.fromRecipe(original);

      expect(
        reopened.sections.single.directionsText,
        startsWith('1. Season the ribs'),
      );
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

  group('component groups (spec §5.2)', () {
    RecipeDraft grouped() => draft(
      sections: const <DraftSection>[
        DraftSection(
          name: 'Sauce',
          ingredientsText: '1 cup passata\n2 tbsp olive oil',
          directionsText: 'Simmer the passata\nSeason it',
        ),
        DraftSection(
          name: 'Main',
          ingredientsText: '500 g rigatoni',
          directionsText: 'Boil the pasta\nToss it through',
        ),
      ],
    );

    test('each section keeps its own ingredients and steps', () {
      final Recipe recipe = grouped().toRecipe(idFactory: sequentialIds());

      expect(recipe.orderedSections.map((RecipeSection s) => s.name), <String>[
        'Sauce',
        'Main',
      ]);
      expect(recipe.orderedSections.first.ingredients, hasLength(2));
      expect(recipe.orderedSections.last.ingredients, hasLength(1));
    });

    test('steps are numbered straight through, not restarted per group', () {
      // A cook counting steps counts the whole method — "step 3" has to mean
      // one thing.
      final Recipe recipe = grouped().toRecipe(idFactory: sequentialIds());

      expect(recipe.allSteps.map((RecipeStep s) => s.stepNumber), <int>[
        1,
        2,
        3,
        4,
      ]);
      expect(recipe.allSteps.last.text, 'Toss it through');
    });

    test('ingredients belong to the section they were typed in', () {
      final Recipe recipe = grouped().toRecipe(idFactory: sequentialIds());
      final RecipeSection sauce = recipe.orderedSections.first;

      expect(
        sauce.ingredients.every(
          (RecipeIngredient i) => i.sectionId == sauce.id,
        ),
        isTrue,
      );
    });

    test('the whole recipe still flattens for nutrition and shopping', () {
      // Grouped is for cooking; flattened is what the macros are computed on.
      final Recipe recipe = grouped().toRecipe(idFactory: sequentialIds());
      expect(recipe.allIngredients, hasLength(3));
    });

    test('an untouched section left behind is dropped, not saved', () {
      // "Add a section" tapped and thought better of should leave no trace.
      final Recipe recipe = draft(
        sections: const <DraftSection>[
          DraftSection(ingredientsText: '2 tbsp olive oil'),
          DraftSection(),
        ],
      ).toRecipe(idFactory: sequentialIds());

      expect(recipe.sections, hasLength(1));
    });

    test('a recipe is never left with no sections at all', () {
      final Recipe recipe = draft(
        sections: const <DraftSection>[DraftSection()],
      ).toRecipe(idFactory: sequentialIds());

      expect(recipe.sections, hasLength(1));
      expect(recipe.sections.single.name, Recipe.defaultSectionName);
    });

    test('an unnamed section stores as the transparent default', () {
      final Recipe recipe = draft().toRecipe(idFactory: sequentialIds());
      expect(recipe.sections.single.isDefault, isTrue);
    });

    test('a grouped recipe reopens grouped, with its names', () {
      final Recipe saved = grouped().toRecipe(idFactory: sequentialIds());
      final RecipeDraft reopened = RecipeDraft.fromRecipe(saved);

      expect(reopened.sections.map((DraftSection s) => s.name), <String>[
        'Sauce',
        'Main',
      ]);
      expect(reopened.sections.first.ingredientsText, contains('passata'));
      expect(reopened.hasSections, isTrue);
    });

    test('an ungrouped recipe reopens with no section name to explain', () {
      // The user never typed "Main"; showing it back would be putting words
      // in their mouth.
      final Recipe saved = draft().toRecipe(idFactory: sequentialIds());
      final RecipeDraft reopened = RecipeDraft.fromRecipe(saved);

      expect(reopened.sections.single.name, isEmpty);
      expect(reopened.hasSections, isFalse);
    });

    test('editing a grouped recipe reuses every section id', () {
      // Otherwise the ingredient rows would point at sections that no longer
      // exist.
      final Recipe saved = grouped().toRecipe(idFactory: sequentialIds());
      final Recipe resaved = RecipeDraft.fromRecipe(saved)
          .toRecipe(idFactory: sequentialIds());

      expect(
        resaved.orderedSections.map((RecipeSection s) => s.id),
        saved.orderedSections.map((RecipeSection s) => s.id),
      );
    });

    test('reordering sections reorders the steps with them', () {
      final RecipeDraft reordered = grouped().copyWith(
        sections: grouped().sections.reversed.toList(),
      );
      final Recipe recipe = reordered.toRecipe(idFactory: sequentialIds());

      expect(recipe.orderedSections.first.name, 'Main');
      expect(recipe.allSteps.first.text, 'Boil the pasta');
      expect(recipe.allSteps.map((RecipeStep s) => s.stepNumber), <int>[
        1,
        2,
        3,
        4,
      ], reason: 'numbering follows the new order rather than the old one');
    });
  });

  group('reopening a recipe re-reads its lines', () {
    // Why editing a *food* could not fix Brendan's frozen onions: the recipe
    // stores the quantity the parser produced when it was saved. A recipe
    // written before the parser understood "4 (10 oz) bags" still holds four
    // bare items, and a count converts to nothing however many servings the
    // food gains afterwards.
    //
    // The raw line is kept on every ingredient precisely so this is
    // recoverable: reopening the recipe parses it again, and saving stores
    // the better reading.
    test('a line saved by an older parser is re-read on the way in', () {
      final Recipe stale = aStaleRecipe();
      expect(
        stale.allIngredients.single.quantity!.kind,
        UnitKind.count,
        reason: 'the stored quantity is what the old parser produced',
      );

      final Recipe reopened = RecipeDraft.fromRecipe(stale)
          .toRecipe(idFactory: sequentialIds());

      final RecipeIngredient onion = reopened.allIngredients.single;
      expect(onion.quantity!.kind, UnitKind.mass);
      expect(onion.quantity!.amountIn(Units.ounce), closeTo(40, 1e-9));
      expect(onion.name, 'frozen chopped onion');
    });

    test('a line with no raw text falls back to its name', () {
      // Older rows may carry no rawText at all; re-reading must not lose the
      // ingredient entirely.
      final Recipe reopened = RecipeDraft.fromRecipe(
        const Recipe(
          id: 'r',
          title: 'T',
          servings: 2,
          sections: <RecipeSection>[
            RecipeSection(
              id: 's',
              name: Recipe.defaultSectionName,
              sortOrder: 0,
              ingredients: <RecipeIngredient>[
                RecipeIngredient(
                  id: 'i',
                  sectionId: 's',
                  name: 'olive oil',
                  sortOrder: 0,
                ),
              ],
            ),
          ],
        ),
      ).toRecipe(idFactory: sequentialIds());

      expect(reopened.allIngredients.single.name, 'olive oil');
    });
  });
}

/// A recipe as it would have been stored before the parser understood the
/// bracketed multipack form: four bare items, with the real line preserved.
Recipe aStaleRecipe() => Recipe(
  id: 'recipe-ragu',
  title: 'Beef ragu bowl',
  servings: 4,
  sections: <RecipeSection>[
    RecipeSection(
      id: 'sec',
      name: Recipe.defaultSectionName,
      sortOrder: 0,
      ingredients: <RecipeIngredient>[
        RecipeIngredient(
          id: 'ing',
          sectionId: 'sec',
          name: 'frozen chopped onion',
          quantity: Quantity.of(4, Units.item),
          rawText: '4 (10 oz) bags frozen chopped onion',
          sortOrder: 0,
        ),
      ],
    ),
  ],
);
