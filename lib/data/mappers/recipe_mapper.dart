import 'package:drift/drift.dart';

import '../../domain/models/recipe.dart';
import '../local/hearth_database.dart';
import 'quantity_mapper.dart';

/// Maps recipes between the domain aggregate and the four tables that store
/// it.
///
/// A recipe is read and written as a whole: sections, ingredients, and steps
/// have no independent life, and treating them as one unit is what makes
/// whole-record last-write-wins coherent (spec §7.1).
abstract final class RecipeMapper {
  static const Map<String, RecipeSource> _sourceFromSql =
      <String, RecipeSource>{
        'manual': RecipeSource.manual,
        'imported': RecipeSource.imported,
        'ai_generated': RecipeSource.aiGenerated,
      };

  static String sourceToSql(RecipeSource source) => switch (source) {
    RecipeSource.manual => 'manual',
    RecipeSource.imported => 'imported',
    RecipeSource.aiGenerated => 'ai_generated',
  };

  static RecipeSource sourceFromSql(String value) =>
      _sourceFromSql[value] ?? RecipeSource.manual;

  /// Assembles the aggregate from its rows.
  static Recipe toDomain({
    required RecipeRow recipe,
    required List<RecipeSectionRow> sections,
    required List<RecipeIngredientRow> ingredients,
    required List<RecipeStepRow> steps,
  }) => Recipe(
    id: recipe.id,
    householdId: recipe.householdId,
    title: recipe.title,
    servings: recipe.servings,
    prepTime: recipe.prepSeconds == null
        ? null
        : Duration(seconds: recipe.prepSeconds!),
    cookTime: recipe.cookSeconds == null
        ? null
        : Duration(seconds: recipe.cookSeconds!),
    cuisine: recipe.cuisine,
    kind: kindFromSql(recipe.kind),
    tags: recipe.tags,
    source: sourceFromSql(recipe.source),
    photoUrl: recipe.photoUrl,
    iconSvg: recipe.iconSvg,
    notes: recipe.notes,
    createdBy: recipe.createdBy,
    isDeleted: recipe.isDeleted,
    updatedAt: recipe.updatedAt,
    sections: <RecipeSection>[
      for (final RecipeSectionRow section in sections)
        RecipeSection(
          id: section.id,
          name: section.name,
          sortOrder: section.sortOrder,
          ingredients: <RecipeIngredient>[
            for (final RecipeIngredientRow row in ingredients)
              if (row.sectionId == section.id) _ingredientToDomain(row),
          ],
          steps: <RecipeStep>[
            for (final RecipeStepRow row in steps)
              if (row.sectionId == section.id)
                RecipeStep(
                  id: row.id,
                  sectionId: row.sectionId,
                  stepNumber: row.stepNumber,
                  text: row.body,
                  timerSeconds: row.timerSeconds,
                ),
          ],
        ),
    ],
  );

  static RecipeIngredient _ingredientToDomain(RecipeIngredientRow row) =>
      RecipeIngredient(
        id: row.id,
        sectionId: row.sectionId,
        name: row.name,
        quantity: QuantityMapper.fromSql(
          canonicalAmount: row.quantityCanonical,
          kind: row.quantityKind,
          unitId: row.quantityUnit,
        ),
        rawText: row.rawText,
        prepNote: row.prepNote,
        foodId: row.foodId,
        isOptional: row.isOptional,
        needsNoMatch: row.needsNoMatch,
        sortOrder: row.sortOrder,
      );

  /// The wire and column spelling of [RecipeKind].
  ///
  /// Snake case, matching every other enum stored here, and unknown values
  /// read as `cooked` rather than throwing — a row written by a newer client
  /// should degrade to an ordinary recipe rather than break the pull.
  static String kindToSql(RecipeKind kind) => switch (kind) {
    RecipeKind.cooked => 'cooked',
    RecipeKind.eatenOut => 'eaten_out',
  };

  static RecipeKind kindFromSql(String value) => switch (value) {
    'eaten_out' => RecipeKind.eatenOut,
    _ => RecipeKind.cooked,
  };

  static RecipesCompanion toCompanion(Recipe recipe, DateTime updatedAt) =>
      RecipesCompanion.insert(
        id: recipe.id,
        householdId: recipe.householdId ?? '',
        title: recipe.title,
        servings: recipe.servings,
        prepSeconds: Value<int?>(recipe.prepTime?.inSeconds),
        cookSeconds: Value<int?>(recipe.cookTime?.inSeconds),
        cuisine: Value<String?>(recipe.cuisine),
        kind: Value<String>(kindToSql(recipe.kind)),
        tags: Value<List<String>>(recipe.tags),
        source: Value<String>(sourceToSql(recipe.source)),
        photoUrl: Value<String?>(recipe.photoUrl),
        iconSvg: Value<String?>(recipe.iconSvg),
        notes: Value<String?>(recipe.notes),
        createdBy: Value<String?>(recipe.createdBy),
        isDeleted: Value<bool>(recipe.isDeleted),
        updatedAt: updatedAt,
      );

  static List<RecipeSectionsCompanion> sectionCompanions(Recipe recipe) =>
      <RecipeSectionsCompanion>[
        for (final RecipeSection section in recipe.sections)
          RecipeSectionsCompanion.insert(
            id: section.id,
            recipeId: recipe.id,
            name: Value<String>(section.name),
            sortOrder: Value<int>(section.sortOrder),
          ),
      ];

  static List<RecipeIngredientsCompanion> ingredientCompanions(Recipe recipe) =>
      <RecipeIngredientsCompanion>[
        for (final RecipeSection section in recipe.sections)
          for (final RecipeIngredient ingredient in section.ingredients)
            RecipeIngredientsCompanion.insert(
              id: ingredient.id,
              recipeId: recipe.id,
              sectionId: section.id,
              foodId: Value<String?>(ingredient.foodId),
              rawText: Value<String?>(ingredient.rawText),
              name: ingredient.name,
              quantityCanonical: Value<double?>(
                QuantityMapper.amountToSql(ingredient.quantity),
              ),
              quantityKind: Value<String?>(
                QuantityMapper.kindColumnToSql(ingredient.quantity),
              ),
              quantityUnit: Value<String?>(
                QuantityMapper.unitToSql(ingredient.quantity),
              ),
              prepNote: Value<String?>(ingredient.prepNote),
              isOptional: Value<bool>(ingredient.isOptional),
              needsNoMatch: Value<bool>(ingredient.needsNoMatch),
              sortOrder: Value<int>(ingredient.sortOrder),
            ),
      ];

  static List<RecipeStepsCompanion> stepCompanions(Recipe recipe) =>
      <RecipeStepsCompanion>[
        for (final RecipeSection section in recipe.sections)
          for (final RecipeStep step in section.steps)
            RecipeStepsCompanion.insert(
              id: step.id,
              recipeId: recipe.id,
              sectionId: section.id,
              stepNumber: step.stepNumber,
              body: step.text,
              timerSeconds: Value<int?>(step.timerSeconds),
            ),
      ];

  /// The recipe as the sync payload: the aggregate in one object, matching the
  /// shape the remote gateway writes across the four Supabase tables.
  ///
  /// Whole-record last-write-wins means the payload is always the complete
  /// recipe, never a patch (spec §7.1).
  static Map<String, Object?> toJson(
    Recipe recipe, {
    required DateTime updatedAt,
  }) => <String, Object?>{
    'id': recipe.id,
    'household_id': recipe.householdId,
    'title': recipe.title,
    'servings': recipe.servings,
    'prep_seconds': recipe.prepTime?.inSeconds,
    'cook_seconds': recipe.cookTime?.inSeconds,
    'cuisine': recipe.cuisine,
    'kind': kindToSql(recipe.kind),
    'tags': recipe.tags,
    'source': sourceToSql(recipe.source),
    'photo_url': recipe.photoUrl,
    'icon_svg': recipe.iconSvg,
    'notes': recipe.notes,
    'created_by': recipe.createdBy,
    'is_deleted': recipe.isDeleted,
    'updated_at': updatedAt.toIso8601String(),
    'sections': <Map<String, Object?>>[
      for (final RecipeSection section in recipe.orderedSections)
        <String, Object?>{
          'id': section.id,
          'recipe_id': recipe.id,
          'name': section.name,
          'sort_order': section.sortOrder,
        },
    ],
    'ingredients': <Map<String, Object?>>[
      for (final RecipeSection section in recipe.orderedSections)
        for (final RecipeIngredient ingredient in section.ingredients)
          <String, Object?>{
            'id': ingredient.id,
            'recipe_id': recipe.id,
            'section_id': section.id,
            'food_id': ingredient.foodId,
            'raw_text': ingredient.rawText,
            'name': ingredient.name,
            'quantity_canonical': QuantityMapper.amountToSql(
              ingredient.quantity,
            ),
            'quantity_kind': QuantityMapper.kindColumnToSql(
              ingredient.quantity,
            ),
            'quantity_unit': QuantityMapper.unitToSql(ingredient.quantity),
            'prep_note': ingredient.prepNote,
            'is_optional': ingredient.isOptional,
            'needs_no_match': ingredient.needsNoMatch,
            'sort_order': ingredient.sortOrder,
          },
    ],
    'steps': <Map<String, Object?>>[
      for (final RecipeSection section in recipe.orderedSections)
        for (final RecipeStep step in section.steps)
          <String, Object?>{
            'id': step.id,
            'recipe_id': recipe.id,
            'section_id': section.id,
            'step_number': step.stepNumber,
            'body': step.text,
            'timer_seconds': step.timerSeconds,
          },
    ],
  };
}
