import 'package:drift/drift.dart';

import '../../domain/models/recipe.dart';
import '../mappers/recipe_mapper.dart';
import 'hearth_database.dart';

/// Local reads and writes for recipes.
///
/// A recipe is stored across four tables but only ever moves as a whole: an
/// upsert replaces its sections, ingredients, and steps outright rather than
/// diffing them. That is what keeps whole-record last-write-wins meaningful —
/// a half-applied edit would leave a recipe that never existed on either
/// device (spec §7.1).
class RecipeStore {
  RecipeStore(this._db);

  final HearthDatabase _db;

  /// One recipe with everything hanging off it, or null when unknown.
  Future<Recipe?> byId(String id) async {
    final RecipeRow? row = await (_db.select(
      _db.recipes,
    )..where(($RecipesTable r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final List<Recipe> assembled = await _assemble(<RecipeRow>[row]);
    return assembled.single;
  }

  /// Every recipe in the household, newest edit first.
  ///
  /// Soft-deleted recipes are excluded by default but remain in the table, so
  /// a past log that references one still resolves (spec §4).
  Future<List<Recipe>> all({
    required String householdId,
    bool includeDeleted = false,
  }) async {
    final List<RecipeRow> rows =
        await (_db.select(_db.recipes)
              ..where(($RecipesTable r) {
                final Expression<bool> scope = r.householdId.equals(
                  householdId,
                );
                return includeDeleted
                    ? scope
                    : scope & r.isDeleted.equals(false);
              })
              ..orderBy(<OrderClauseGenerator<$RecipesTable>>[
                ($RecipesTable r) => OrderingTerm.desc(r.updatedAt),
              ]))
            .get();
    return _assemble(rows);
  }

  /// Emits the household's recipes and then again on every local change, so
  /// an open list updates itself after a sync lands.
  Stream<List<Recipe>> watchAll({
    required String householdId,
    bool includeDeleted = false,
  }) => _db
      .select(_db.recipes)
      .watch()
      .asyncMap(
        (_) => all(householdId: householdId, includeDeleted: includeDeleted),
      );

  /// Inserts or replaces a recipe and all of its children atomically.
  Future<void> upsert(
    Recipe recipe, {
    required DateTime updatedAt,
  }) => _db.transaction(() async {
    await _db
        .into(_db.recipes)
        .insertOnConflictUpdate(RecipeMapper.toCompanion(recipe, updatedAt));

    // Children are replaced wholesale. Diffing them would risk leaving an
    // ingredient behind that the edit removed.
    await (_db.delete(
      _db.recipeIngredients,
    )..where(($RecipeIngredientsTable t) => t.recipeId.equals(recipe.id))).go();
    await (_db.delete(
      _db.recipeSteps,
    )..where(($RecipeStepsTable t) => t.recipeId.equals(recipe.id))).go();
    await (_db.delete(
      _db.recipeSections,
    )..where(($RecipeSectionsTable t) => t.recipeId.equals(recipe.id))).go();

    await _db.batch((Batch batch) {
      batch.insertAll(
        _db.recipeSections,
        RecipeMapper.sectionCompanions(recipe),
      );
      batch.insertAll(
        _db.recipeIngredients,
        RecipeMapper.ingredientCompanions(recipe),
      );
      batch.insertAll(_db.recipeSteps, RecipeMapper.stepCompanions(recipe));
    });
  });

  /// Hides a recipe without removing it. Recipes are never physically deleted,
  /// so historical logs keep resolving (spec §4).
  Future<void> softDelete(String id, {required DateTime updatedAt}) async {
    await (_db.update(
      _db.recipes,
    )..where(($RecipesTable r) => r.id.equals(id))).write(
      RecipesCompanion(
        isDeleted: const Value<bool>(true),
        updatedAt: Value<DateTime>(updatedAt),
      ),
    );
  }

  /// Replaces the local copy with the server's, used when sync pulls changes.
  Future<void> replaceAll(
    Iterable<Recipe> recipes, {
    required DateTime updatedAt,
  }) => _db.transaction(() async {
    for (final Recipe recipe in recipes) {
      await upsert(recipe, updatedAt: updatedAt);
    }
  });

  Future<List<Recipe>> _assemble(List<RecipeRow> rows) async {
    if (rows.isEmpty) return const <Recipe>[];
    final List<String> ids = rows.map((RecipeRow r) => r.id).toList();

    final List<RecipeSectionRow> sections =
        await (_db.select(_db.recipeSections)
              ..where(($RecipeSectionsTable t) => t.recipeId.isIn(ids))
              ..orderBy(<OrderClauseGenerator<$RecipeSectionsTable>>[
                ($RecipeSectionsTable t) => OrderingTerm.asc(t.sortOrder),
              ]))
            .get();
    final List<RecipeIngredientRow> ingredients =
        await (_db.select(_db.recipeIngredients)
              ..where(($RecipeIngredientsTable t) => t.recipeId.isIn(ids))
              ..orderBy(<OrderClauseGenerator<$RecipeIngredientsTable>>[
                ($RecipeIngredientsTable t) => OrderingTerm.asc(t.sortOrder),
              ]))
            .get();
    final List<RecipeStepRow> steps =
        await (_db.select(_db.recipeSteps)
              ..where(($RecipeStepsTable t) => t.recipeId.isIn(ids))
              ..orderBy(<OrderClauseGenerator<$RecipeStepsTable>>[
                ($RecipeStepsTable t) => OrderingTerm.asc(t.stepNumber),
              ]))
            .get();

    return <Recipe>[
      for (final RecipeRow row in rows)
        RecipeMapper.toDomain(
          recipe: row,
          sections: sections
              .where((RecipeSectionRow s) => s.recipeId == row.id)
              .toList(growable: false),
          ingredients: ingredients
              .where((RecipeIngredientRow i) => i.recipeId == row.id)
              .toList(growable: false),
          steps: steps
              .where((RecipeStepRow s) => s.recipeId == row.id)
              .toList(growable: false),
        ),
    ];
  }
}
