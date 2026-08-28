import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/recipe.dart';
import '../../domain/parsing/direction_parser.dart';
import '../../domain/parsing/ingredient_parser.dart';

/// Turns what the user typed into a [Recipe].
///
/// Kept out of the widget so the conversion — which is where a mistyped
/// quantity or a mis-split step would do real damage — can be tested without
/// pumping a screen.
///
/// Ingredients and directions are entered as free text and parsed, because
/// typing a recipe line by line into separate fields is the slow path, and
/// the parsers already handle the shapes people actually paste (spec §5.2).
@immutable
class RecipeDraft {
  const RecipeDraft({
    required this.title,
    required this.servings,
    required this.ingredientsText,
    required this.directionsText,
    this.prepMinutes,
    this.cookMinutes,
    this.cuisine,
    this.tags = const <String>[],
    this.notes,
    this.existingId,
    this.existingSectionId,
  });

  final String title;
  final double servings;
  final String ingredientsText;
  final String directionsText;
  final int? prepMinutes;
  final int? cookMinutes;
  final String? cuisine;
  final List<String> tags;
  final String? notes;

  /// Set when editing, so a save updates rather than creating a duplicate.
  final String? existingId;

  /// Reusing the section id on edit keeps ingredient rows pointing at a
  /// section that still exists.
  final String? existingSectionId;

  bool get isEditing => existingId != null;

  /// A title is the only field required to save. Yield defaults rather than
  /// blocking, because "missing data flags, never blocks" (spec §5.3) applies
  /// just as much to the user's own typing.
  String? get titleError =>
      title.trim().isEmpty ? 'A recipe needs a title.' : null;

  String? get servingsError =>
      servings > 0 ? null : 'Servings must be more than zero.';

  bool get isValid => titleError == null && servingsError == null;

  /// The parsed ingredient lines, for the live preview.
  List<ParsedIngredient> get parsedIngredients => <ParsedIngredient>[
    for (final String line in ingredientsText.split('\n'))
      if (line.trim().isNotEmpty) IngredientParser.parse(line),
  ];

  /// The parsed steps, for the live preview.
  ParsedDirections get parsedDirections =>
      DirectionParser.parse(directionsText);

  /// Builds the recipe to save.
  ///
  /// [idFactory] is injectable so tests get stable ids.
  Recipe toRecipe({String Function()? idFactory}) {
    final String Function() newId = idFactory ?? const Uuid().v4;
    final String recipeId = existingId ?? newId();
    final String sectionId = existingSectionId ?? newId();

    final List<ParsedIngredient> ingredients = parsedIngredients;
    final ParsedDirections directions = parsedDirections;

    return Recipe(
      id: recipeId,
      title: title.trim(),
      servings: servings,
      prepTime: prepMinutes == null ? null : Duration(minutes: prepMinutes!),
      cookTime: cookMinutes == null ? null : Duration(minutes: cookMinutes!),
      cuisine: (cuisine ?? '').trim().isEmpty ? null : cuisine!.trim(),
      tags: tags,
      notes: (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      sections: <RecipeSection>[
        RecipeSection(
          // A single default section: it renders without a header, so a simple
          // recipe never has to know sections exist (spec §5.2).
          id: sectionId,
          name: Recipe.defaultSectionName,
          sortOrder: 0,
          ingredients: <RecipeIngredient>[
            for (int i = 0; i < ingredients.length; i++)
              RecipeIngredient(
                id: newId(),
                sectionId: sectionId,
                name: ingredients[i].name,
                quantity: ingredients[i].quantity,
                rawText: ingredients[i].raw,
                prepNote: ingredients[i].prepNote,
                isOptional: ingredients[i].isOptional,
                sortOrder: i,
              ),
          ],
          steps: <RecipeStep>[
            for (final ParsedStep step in directions.steps)
              RecipeStep(
                id: newId(),
                sectionId: sectionId,
                stepNumber: step.number,
                text: step.text,
              ),
          ],
        ),
      ],
    );
  }

  /// Rebuilds a draft from a saved recipe, so editing starts from what is
  /// actually stored rather than from a re-rendered guess.
  factory RecipeDraft.fromRecipe(Recipe recipe) {
    final RecipeSection? section = recipe.orderedSections.isEmpty
        ? null
        : recipe.orderedSections.first;

    return RecipeDraft(
      title: recipe.title,
      servings: recipe.servings,
      // The raw line is kept on every ingredient precisely so an edit shows
      // the user what they typed, not the parser's reconstruction.
      ingredientsText: recipe.allIngredients
          .map((RecipeIngredient i) => i.rawText ?? i.name)
          .join('\n'),
      directionsText: recipe.allSteps
          .map((RecipeStep s) => '${s.stepNumber}. ${s.text}')
          .join('\n'),
      prepMinutes: recipe.prepTime?.inMinutes,
      cookMinutes: recipe.cookTime?.inMinutes,
      cuisine: recipe.cuisine,
      tags: recipe.tags,
      notes: recipe.notes,
      existingId: recipe.id,
      existingSectionId: section?.id,
    );
  }

  RecipeDraft copyWith({
    String? title,
    double? servings,
    String? ingredientsText,
    String? directionsText,
    int? prepMinutes,
    int? cookMinutes,
    String? cuisine,
    List<String>? tags,
    String? notes,
  }) => RecipeDraft(
    title: title ?? this.title,
    servings: servings ?? this.servings,
    ingredientsText: ingredientsText ?? this.ingredientsText,
    directionsText: directionsText ?? this.directionsText,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    cookMinutes: cookMinutes ?? this.cookMinutes,
    cuisine: cuisine ?? this.cuisine,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
    existingId: existingId,
    existingSectionId: existingSectionId,
  );
}
