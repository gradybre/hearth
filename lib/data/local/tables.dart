/// Drift tables mirroring the Supabase schema for the offline cache.
///
/// Only the subset spec §7.1 calls for is cached: recipes, the food library,
/// and the current week's plan — the two low-signal moments are cooking and
/// logging, and both have to work with no network.
///
/// Ids are the server's uuids as text, so a row created offline keeps its
/// identity when it syncs. Every synced table carries `updatedAt`, which is
/// what whole-record last-write-wins compares (spec §7.1).
library;

import 'dart:convert';

import 'package:drift/drift.dart';

/// Stores a `List<String>` as a JSON array.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const <String>[];
    final Object? decoded = jsonDecode(fromDb);
    if (decoded is! List) return const <String>[];
    return decoded.map((Object? e) => e.toString()).toList(growable: false);
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

@DataClassName('RecipeRow')
class Recipes extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get title => text()();
  RealColumn get servings => real()();
  IntColumn get prepSeconds => integer().nullable()();
  IntColumn get cookSeconds => integer().nullable()();
  TextColumn get cuisine => text().nullable()();
  TextColumn get tags => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('RecipeSectionRow')
class RecipeSections extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withDefault(const Constant('Main'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('RecipeIngredientRow')
class RecipeIngredients extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.cascade)();
  TextColumn get sectionId => text()();
  TextColumn get foodId => text().nullable()();
  TextColumn get rawText => text().nullable()();
  TextColumn get name => text()();

  /// Stored canonically: ml, g, or items. Null for "salt to taste".
  RealColumn get quantityCanonical => real().nullable()();
  TextColumn get quantityKind => text().nullable()();

  /// The unit the line was authored in — a display hint only.
  TextColumn get quantityUnit => text().nullable()();
  TextColumn get prepNote => text().nullable()();
  BoolColumn get isOptional => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('RecipeStepRow')
class RecipeSteps extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.cascade)();
  TextColumn get sectionId => text()();
  IntColumn get stepNumber => integer()();
  TextColumn get body => text()();
  IntColumn get timerSeconds => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('FoodRow')
class Foods extends Table {
  TextColumn get id => text()();

  /// Null means a global food from the shared catalogue.
  TextColumn get householdId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get storeTag => text().nullable()();
  TextColumn get barcode => text().nullable()();
  RealColumn get gramsPerMillilitre => real().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  BoolColumn get macrosOverridden =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('FoodServingOptionRow')
class FoodServingOptions extends Table {
  TextColumn get id => text()();
  TextColumn get foodId =>
      text().references(Foods, #id, onDelete: KeyAction.cascade)();
  TextColumn get label => text()();
  RealColumn get amountCanonical => real()();
  TextColumn get amountKind => text()();
  TextColumn get amountUnit => text().nullable()();
  RealColumn get kcal => real().withDefault(const Constant(0))();
  RealColumn get proteinG => real().withDefault(const Constant(0))();
  RealColumn get carbG => real().withDefault(const Constant(0))();
  RealColumn get fatG => real().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('MealPlanDayRow')
class MealPlanDays extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  DateTimeColumn get day => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{userId, day},
  ];
}

@DataClassName('MealPlanEntryRow')
class MealPlanEntries extends Table {
  TextColumn get id => text()();
  TextColumn get dayId =>
      text().references(MealPlanDays, #id, onDelete: KeyAction.cascade)();
  TextColumn get mealSlot => text()();
  TextColumn get refType => text()();
  TextColumn get refId => text()();
  RealColumn get servings => real()();
  BoolColumn get isPlanned => boolean().withDefault(const Constant(true))();
  BoolColumn get isLogged => boolean().withDefault(const Constant(false))();
  DateTimeColumn get loggedAt => dateTime().nullable()();

  /// Macros and portion frozen at log time, as JSON. Never recomputed —
  /// editing a recipe later must not rewrite past days (spec §4).
  TextColumn get macroSnapshot => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('MacroTargetRow')
class MacroTargets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  DateTimeColumn get weekStartDate => dateTime()();
  RealColumn get kcal => real()();
  RealColumn get proteinG => real()();
  RealColumn get carbG => real()();
  RealColumn get fatG => real()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{userId, weekStartDate},
  ];
}

/// Writes made while offline, replayed in order on reconnect (spec §7.1).
@DataClassName('PendingWriteRow')
class PendingWrites extends Table {
  IntColumn get sequence => integer().autoIncrement()();

  /// The Supabase table this write targets.
  TextColumn get entityTable => text()();
  TextColumn get entityId => text()();

  /// `upsert` or `delete`. Recipes and foods are soft-deleted, so a hard
  /// delete only ever reaches rows the spec allows to disappear.
  TextColumn get operation => text()();

  /// The full row as JSON. Whole-record last-write-wins means the payload is
  /// the entire record, never a patch (spec §7.1).
  TextColumn get payload => text()();
  DateTimeColumn get queuedAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

/// A remembered ingredient-string to food mapping (spec §5.3).
///
/// Correcting a match is remembered so the same string never has to be fixed
/// twice: once "evoo" has been pointed at olive oil, every future recipe line
/// saying "evoo" resolves on its own.
@DataClassName('IngredientMatchRow')
class IngredientMatches extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();

  /// The normalised ingredient string — the same key the density lookup and
  /// consolidation use, so they all agree on what counts as "the same thing".
  TextColumn get ingredientString => text()();
  TextColumn get foodId =>
      text().references(Foods, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{householdId, ingredientString},
  ];
}

/// A recipe favourited by one user (spec §5.2, §8.2).
///
/// User-scoped, not household-scoped: favouriting is personal, so a partner's
/// hearts must never show up as yours. The primary key is the pair, which
/// makes favouriting idempotent — tapping twice cannot create two rows.
@DataClassName('RecipeFavoriteRow')
class RecipeFavorites extends Table {
  TextColumn get userId => text()();
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId, recipeId};
}

/// A "cookbook" — a household-shared grouping of recipes (spec §5.2).
@DataClassName('CollectionRow')
class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Membership: a recipe can live in several collections at once (spec §5.2).
@DataClassName('RecipeCollectionRow')
class RecipeCollections extends Table {
  TextColumn get collectionId =>
      text().references(Collections, #id, onDelete: KeyAction.cascade)();
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    collectionId,
    recipeId,
  };
}
