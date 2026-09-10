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

  /// Cooked, or eaten out (spec §5.2). An eaten-out recipe never reaches the
  /// shopping list.
  TextColumn get kind => text().withDefault(const Constant('cooked'))();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get photoUrl => text().nullable()();

  /// A little hand-drawn sketch of the dish, as SVG markup (spec §5.2).
  ///
  /// Cached like the rest of the recipe so the library draws itself with no
  /// network. Never rendered without going through `SketchIcon.parse` — a
  /// row here can have arrived from another device, and it is model output
  /// either way.
  TextColumn get iconSvg => text().nullable()();

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

  /// A line that will never have a food behind it: salt, pepper, a spice
  /// (spec §5.3). Distinct from [isOptional], which is what the recipe said.
  BoolColumn get needsNoMatch => boolean().withDefault(const Constant(false))();
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

  /// The Walmart item id for the product bought, and how much is in one of
  /// them — what lets the shopping export fill a basket (spec §5.7).
  TextColumn get walmartItemId => text().nullable()();
  RealColumn get packCanonical => real().nullable()();
  TextColumn get packKind => text().nullable()();
  TextColumn get packUnit => text().nullable()();
  TextColumn get barcode => text().nullable()();

  /// Where this sits on a restaurant's menu, and how far down the sheet
  /// (spec §5.2). Null for anything that is not off a menu.
  TextColumn get menuGroup => text().nullable()();
  IntColumn get menuOrder => integer().nullable()();
  RealColumn get gramsPerMillilitre => real().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  BoolColumn get macrosOverridden =>
      boolean().withDefault(const Constant(false))();

  /// A standing choice, matched to recipe lines naming the same thing (§5.3).
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  /// Confirmed to carry no macros — black coffee, sparkling water (§5.5).
  BoolColumn get isZeroCalorie =>
      boolean().withDefault(const Constant(false))();

  /// A menu row published as a deduction rather than as something you order
  /// (spec §5.2). Its servings may hold negative macros; nothing else may.
  BoolColumn get isModifier => boolean().withDefault(const Constant(false))();
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

  /// The three minor nutrients (spec §5.6). Nullable and **no default**: null
  /// is unknown, and a `withDefault(0)` here would quietly turn every food
  /// that has never heard of fibre into one that claims to have none.
  RealColumn get fiberG => real().nullable()();
  RealColumn get sodiumMg => real().nullable()();
  RealColumn get cholesterolMg => real().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Carried from the food this belongs to and never authored on its own.
  ///
  /// It exists so the hosted `check (kcal >= 0 or is_modifier)` can see the
  /// food's answer, since a check constraint cannot read another table. There
  /// is deliberately **no** matching check here: a Drift `TableMigration`
  /// rebuild applies a new CHECK to every row it copies, so a device already
  /// holding a negative would fail to open its own database. The sign is
  /// enforced in Dart instead, where the user can be told why.
  BoolColumn get isModifier => boolean().withDefault(const Constant(false))();

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

  /// The three minor nutrients (spec §5.6). Null means the Daily Value, not
  /// "no target" — which is why there is no default here to confuse the two.
  RealColumn get fiberG => real().nullable()();
  RealColumn get sodiumMg => real().nullable()();
  RealColumn get cholesterolMg => real().nullable()();
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

  /// The earliest this write may be tried again, after a failure.
  ///
  /// Null means now. A failure that retried on every pass would hammer the
  /// server for as long as it kept being refused — and passes are triggered
  /// by local writes, so somebody typing a shopping list can produce several
  /// a second (spec §7.1).
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
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

  /// Null when the answer is [needsNoMatch] rather than a food.
  TextColumn get foodId =>
      text().nullable().references(Foods, #id, onDelete: KeyAction.cascade)();

  /// The other answer this row can carry: nothing to match, because the line
  /// is salt (spec §5.3).
  ///
  /// One table rather than two, because "what does this wording resolve to?"
  /// is one question — and the unique key below already guarantees one answer
  /// per wording. Two tables could disagree about the same string.
  BoolColumn get needsNoMatch => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{householdId, ingredientString},
  ];

  /// Never both at once. The NOT NULL this replaces held since the first
  /// migration, and a row claiming a food *and* no match is a bug the database
  /// is the right place to catch.
  ///
  /// Neither *is* allowed, and means something: this household has looked at
  /// this wording and said it needs an ordinary match — which is how a
  /// built-in seasoning gets turned back off. Three answers, one row, and the
  /// unique key below keeps a wording to one of them.
  @override
  List<String> get customConstraints => <String>[
    'CHECK (NOT ((food_id IS NOT NULL) AND needs_no_match))',
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

/// A shopping list, for a stretch of days rather than a week (spec §5.7).
///
/// A range and not a week because the shop happens on a Friday for a period
/// covering the weekend and the week after, and never lines up with a calendar
/// week.
@DataClassName('ShoppingListRow')
class ShoppingLists extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  DateTimeColumn get fromDate => dateTime()();
  DateTimeColumn get toDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// One line of a list, carrying three amounts (spec §5.7).
///
/// What the recipes call for, what the shopper decided to buy instead, and
/// what is already in the cupboard — each decided by someone different, and
/// the line has to be able to show its own arithmetic.
@DataClassName('ShoppingItemRow')
class ShoppingListItems extends Table {
  TextColumn get id => text()();
  TextColumn get listId => text()();

  /// What duplicates are matched on, so a line survives a rebuild by being
  /// recognised rather than by being in the same place.
  TextColumn get itemKey => text()();
  TextColumn get foodId => text().nullable()();
  TextColumn get name => text()();

  RealColumn get plannedCanonical => real().nullable()();
  TextColumn get plannedKind => text().nullable()();
  TextColumn get plannedUnit => text().nullable()();

  /// The rest of what the recipes said, when they said it more than one way.
  ///
  /// JSON list of {canonical, kind, unit}. A line written as 2 tbsp *and*
  /// 50 g with no density to reconcile them has two planned amounts; keeping
  /// only the first made the line read as measurable on reload and quietly
  /// dropped the other half of the requirement.
  TextColumn get plannedRest => text().withDefault(const Constant('[]'))();

  RealColumn get wantedCanonical => real().nullable()();
  TextColumn get wantedKind => text().nullable()();
  TextColumn get wantedUnit => text().nullable()();

  RealColumn get onHandCanonical => real().nullable()();
  TextColumn get onHandKind => text().nullable()();
  TextColumn get onHandUnit => text().nullable()();

  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();
  BoolColumn get hasUnquantified =>
      boolean().withDefault(const Constant(false))();
  TextColumn get storeTag => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Comma-separated, like the other places this cache stores a small list —
  /// it is only ever read back whole.
  TextColumn get sourceRecipeIds => text().withDefault(const Constant(''))();
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

/// A cook timer, kept across app launches (spec §5.2).
///
/// Local-only and never synced: a timer belongs to the pot on *this* stove, and
/// pushing it to a partner's phone would be someone else's oven alarm going off
/// in their pocket.
///
/// Stored as a start instant plus a duration rather than a remaining count, so
/// the time left is derived on read. A stored countdown would be wrong by
/// however long the app was closed — which, for a braise, is the whole point.
@DataClassName('CookTimerRow')
class CookTimers extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  IntColumn get durationSeconds => integer()();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get stepNumber => integer().nullable()();

  /// The step this timer belongs to — one timer per step, not one per tap.
  TextColumn get stepId => text().nullable()();

  /// Elapsed seconds at the moment it was paused; null while running.
  IntColumn get elapsedWhenPausedSeconds => integer().nullable()();

  /// What was being cooked, for a timer seen from outside cook mode.
  TextColumn get recipeTitle => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// The user's own food profile (spec §4, §5.4).
///
/// One row per user — the generator wants "the profile", not a history of it,
/// and the server enforces that with user_id as the primary key. Private per
/// user (§8.2): a partner's dislikes are not the household's business.
///
/// The list columns are stored as newline-joined text rather than a relation.
/// They are short, always read whole, and never queried across — a join table
/// would buy nothing and cost a migration.
@DataClassName('FoodProfileRow')
class FoodProfiles extends Table {
  TextColumn get userId => text()();
  RealColumn get caloriesPerMealTarget => real().nullable()();
  RealColumn get proteinTargetG => real().nullable()();
  TextColumn get preferredMealTypes =>
      text().withDefault(const Constant<String>(''))();
  TextColumn get dietaryPreferences =>
      text().withDefault(const Constant<String>(''))();
  TextColumn get dislikes => text().withDefault(const Constant<String>(''))();
  TextColumn get allergies => text().withDefault(const Constant<String>(''))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId};
}

/// Small local preferences — how the app is set up on *this* device.
///
/// Key/value rather than a column per setting: these are device-local view
/// choices, not household data, and adding one should not mean a migration.
/// Nothing here is synced; which view you last used in cook-along is not a
/// fact about the household.
@DataClassName('PreferenceRow')
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// Work in progress in an editor, so an interruption does not end it
/// (spec §5.2, review N01).
///
/// **Device-local, and deliberately not synced.** A half-typed recipe is not
/// a fact about the household — it is a fact about this phone, five minutes
/// ago, and pushing it would put an unreviewed draft in front of the other
/// person as though somebody had decided something. Rule 4 says nothing
/// automated reaches the library without review, and a draft is the state
/// *before* that review. It is in this file with `preferences` and
/// `cook_sessions` for the same reason all three are: they describe a device,
/// not a household.
///
/// Scoped by user because two people share a device in exactly one situation
/// — a sign-out and a sign-in — and inheriting a stranger's half-written
/// recipe would be both confusing and a small privacy failure.
@DataClassName('EditorDraftRow')
class EditorDrafts extends Table {
  /// What is being edited: `recipe:new`, `recipe:<id>`, `food:<id>`. One
  /// draft per target, because a second draft of the same recipe is not a
  /// thing anybody wants to be offered a choice between.
  TextColumn get id => text()();

  TextColumn get userId => text()();

  /// `recipe` or `food`. Stored rather than parsed back out of [id] so a
  /// reader does not have to know the id's shape to know what it holds.
  TextColumn get kind => text()();

  /// The record being edited, or null for a new one.
  TextColumn get targetId => text().nullable()();

  /// What the underlying record's `updatedAt` was when this draft started.
  ///
  /// The whole of the "somebody else edited it while your draft sat here"
  /// check. Null for a new record, which cannot have been edited underneath.
  DateTimeColumn get sourceUpdatedAt => dateTime().nullable()();

  /// The draft itself, as the editor's own JSON.
  TextColumn get payload => text()();

  DateTimeColumn get updatedAt => dateTime()();

  /// The user is part of the key, not just a filter.
  ///
  /// With `id` alone, two accounts on one device share a row: signing in as
  /// the other person and starting a new recipe overwrites the first
  /// person's draft, because `recipe:new` is the same key for both. Their
  /// work then disappears with nothing to say so — the exact failure this
  /// table exists to prevent, arriving through the table itself.
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId, id};
}

/// Where you are in cooking a particular recipe (spec §5.2).
///
/// Keyed by recipe, so opening a different one does not inherit another's
/// ticks. Local-only and never synced: this is where *you* are standing in the
/// method, not a fact about the household — a partner's phone showing your
/// half-ticked list would be a lie about their own cooking.
@DataClassName('CookSessionRow')
class CookSessions extends Table {
  TextColumn get recipeId => text()();
  IntColumn get currentStep => integer().withDefault(const Constant(0))();

  /// The ids of the steps ticked off, as a JSON array.
  TextColumn get checkedStepIds => text().withDefault(const Constant('[]'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{recipeId};
}

/// A good week, saved so it can be had again (spec §5.6).
///
/// User-scoped, like the plans it is made of: a partner's week is their own.
/// Entries are JSON — placed by weekday rather than by date, so a template
/// outlives the week it was saved from.
@DataClassName('PlanTemplateRow')
class PlanTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get entries => text().withDefault(const Constant<String>('[]'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// A recipe's hero photo as it sits on *this* device (spec §5.2, §7.2).
///
/// Its own table rather than a column on [Recipes]: that table is a sync
/// cache, and a record arriving from the server would overwrite the row —
/// taking a device-local file reference with it.
///
/// Only the file name is stored, never an absolute path. iOS moves an app's
/// container between installs, so an absolute path is a promise the device
/// stops keeping.
///
/// This table is never *pushed* — but it is no longer purely local either. It
/// is this device's index into a shared object store, and the pair
/// ([fileName], [remotePath]) encodes four states:
///
///   - file, no remote     → taken here, not uploaded yet. Also every row that
///                           existed before photo sync, which is what makes
///                           the backfill need no code of its own.
///   - file, remote == the recipe's photo_url → cached and current.
///   - file, remote != it  → stale; the partner replaced it. Re-download.
///   - no file, remote set → known about, not held. A failed download, or a
///                           reinstall that took the container with it.
@DataClassName('RecipePhotoRow')
class RecipePhotos extends Table {
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.cascade)();

  /// Null when this device knows about a photo it does not have.
  TextColumn get fileName => text().nullable()();

  /// The object path [fileName] is a copy of, or null when it was never
  /// uploaded. Compared against the recipe's `photoUrl` to spot a stale copy —
  /// a string compare, and reliable only because objects are immutable.
  TextColumn get remotePath => text().nullable()();

  /// Stops a permanently failing upload from retrying for ever.
  ///
  /// Load-bearing: writing this wakes the sync listener, which retries, which
  /// writes it again. The loop terminates *only* because the candidate query
  /// filters on this being under the limit.
  IntColumn get syncAttempts => integer().withDefault(const Constant<int>(0))();

  TextColumn get syncError => text().nullable()();

  /// The object path the last failed download was for.
  ///
  /// Separate from [remotePath], which says what [fileName] is a copy of. A
  /// stale row keeps its old file while a replacement fails to arrive, so the
  /// two paths genuinely differ — and "has the partner replaced it *again*
  /// since we gave up" can only be answered by remembering what was tried.
  TextColumn get attemptedPath => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{recipeId};
}
