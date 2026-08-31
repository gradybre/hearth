import 'package:meta/meta.dart';

import '../units/quantity.dart';

/// How a recipe entered the library, kept for provenance (spec §4, §5.4).
enum RecipeSource { manual, imported, aiGenerated }

/// One ingredient line, parsed into structured fields.
///
/// The structure is what makes scaling and shopping aggregation possible —
/// a raw string cannot be scaled (spec §5.2).
@immutable
class RecipeIngredient {
  const RecipeIngredient({
    required this.id,
    required this.sectionId,
    required this.name,
    required this.sortOrder,
    this.quantity,
    this.rawText,
    this.prepNote,
    this.foodId,
    this.isOptional = false,
  });

  final String id;
  final String sectionId;

  /// The ingredient itself, with quantity and prep note stripped out:
  /// "garlic", "all-purpose flour".
  final String name;

  /// Null for unquantified lines like "salt to taste". Such a line contributes
  /// nothing to macros; whether that is *fine* or *incomplete* depends on
  /// [isOptional].
  final Quantity? quantity;

  /// The line as originally typed or imported, kept so the user can see what
  /// the parser was working from.
  final String? rawText;

  /// "minced", "finely chopped" — display only, never affects the maths.
  final String? prepNote;

  /// Resolved nutrition match, null until the ingredient is matched to a food.
  final String? foodId;

  /// Salt to taste, garnishes. Excluded from macro totals *and* the shopping
  /// list, deliberately — not a data gap (spec §5.2).
  final bool isOptional;

  final int sortOrder;

  bool get isQuantified => quantity != null;

  RecipeIngredient copyWith({
    Quantity? quantity,
    String? sectionId,
    String? foodId,
    int? sortOrder,
  }) => RecipeIngredient(
    id: id,
    sectionId: sectionId ?? this.sectionId,
    name: name,
    sortOrder: sortOrder ?? this.sortOrder,
    quantity: quantity ?? this.quantity,
    rawText: rawText,
    prepNote: prepNote,
    foodId: foodId ?? this.foodId,
    isOptional: isOptional,
  );

  @override
  bool operator ==(Object other) => other is RecipeIngredient && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RecipeIngredient($name)';
}

/// One direction step.
@immutable
class RecipeStep {
  const RecipeStep({
    required this.id,
    required this.sectionId,
    required this.stepNumber,
    required this.text,
    this.timerSeconds,
  });

  final String id;
  final String sectionId;
  final int stepNumber;
  final String text;

  /// Drives an embedded cook-along timer; several can run at once (spec §5.2).
  final int? timerSeconds;

  bool get hasTimer => timerSeconds != null && timerSeconds! > 0;

  @override
  bool operator ==(Object other) => other is RecipeStep && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A named component group — "Sauce", "Marinade" — owning both its ingredients
/// and its steps, so complex recipes read the way a cookbook writes them.
///
/// Simple recipes have a single section named [Recipe.defaultSectionName],
/// which the UI renders without a group header (spec §5.2).
@immutable
class RecipeSection {
  const RecipeSection({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.ingredients = const <RecipeIngredient>[],
    this.steps = const <RecipeStep>[],
  });

  final String id;
  final String name;
  final int sortOrder;
  final List<RecipeIngredient> ingredients;
  final List<RecipeStep> steps;

  /// This section's steps in reading order.
  List<RecipeStep> get orderedSteps => <RecipeStep>[
    ...steps,
  ]..sort((RecipeStep a, RecipeStep b) => a.stepNumber.compareTo(b.stepNumber));

  bool get isDefault => name == Recipe.defaultSectionName;

  RecipeSection copyWith({
    List<RecipeIngredient>? ingredients,
    List<RecipeStep>? steps,
  }) => RecipeSection(
    id: id,
    name: name,
    sortOrder: sortOrder,
    ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps,
  );

  @override
  bool operator ==(Object other) => other is RecipeSection && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A recipe in the shared household library (spec §4, §5.2).
@immutable
class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.servings,
    required this.sections,
    this.householdId,
    this.prepTime,
    this.cookTime,
    this.cuisine,
    this.tags = const <String>[],
    this.source = RecipeSource.manual,
    this.photoUrl,
    this.notes,
    this.createdBy,
    this.isDeleted = false,
    this.updatedAt,
  });

  /// The section every simple recipe gets. Rendered without a header.
  static const String defaultSectionName = 'Main';

  final String id;
  final String? householdId;
  final String title;

  /// Yield. Required by spec §5.2 — nutrition is shown per serving by default,
  /// which is meaningless without it.
  final double servings;

  final List<RecipeSection> sections;
  final Duration? prepTime;
  final Duration? cookTime;
  final String? cuisine;
  final List<String> tags;
  final RecipeSource source;
  final String? photoUrl;
  final String? notes;
  final String? createdBy;

  /// Soft delete — the row stays so historical logs keep resolving (spec §4).
  final bool isDeleted;

  /// When this recipe was last written, for sorting a library by recency.
  ///
  /// Null for a recipe that has not been through the household's own store —
  /// an unsaved draft, an import still under review. The sort puts those last
  /// rather than treating a missing date as "just now".
  final DateTime? updatedAt;

  Duration? get totalTime => switch ((prepTime, cookTime)) {
    (null, null) => null,
    (final Duration p, null) => p,
    (null, final Duration c) => c,
    (final Duration p, final Duration c) => p + c,
  };

  /// Whether this recipe is really grouped, or is one transparent default.
  ///
  /// A single unnamed "Main" is how every simple recipe is stored; it must
  /// never render a header, or an ordinary recipe would look organised into
  /// groups it never asked for (spec §5.2).
  bool get isGrouped =>
      sections.length > 1 || sections.any((RecipeSection s) => !s.isDefault);

  /// Sections in display order.
  List<RecipeSection> get orderedSections => <RecipeSection>[...sections]
    ..sort(
      (RecipeSection a, RecipeSection b) => a.sortOrder.compareTo(b.sortOrder),
    );

  /// Every ingredient across every section, in reading order.
  ///
  /// This is the *ungrouped* view — it does not merge duplicates. For the
  /// shopping and nutrition view that sums "olive oil" appearing in two
  /// sections, use `IngredientConsolidator.flatten` (spec §5.2).
  List<RecipeIngredient> get allIngredients => <RecipeIngredient>[
    for (final RecipeSection section in orderedSections)
      ...(<RecipeIngredient>[...section.ingredients]..sort(
        (RecipeIngredient a, RecipeIngredient b) =>
            a.sortOrder.compareTo(b.sortOrder),
      )),
  ];

  /// Every step across every section, in reading order.
  List<RecipeStep> get allSteps => <RecipeStep>[
    for (final RecipeSection section in orderedSections)
      ...(<RecipeStep>[...section.steps]..sort(
        (RecipeStep a, RecipeStep b) => a.stepNumber.compareTo(b.stepNumber),
      )),
  ];

  Recipe copyWith({
    double? servings,
    List<RecipeSection>? sections,
    String? title,
  }) => Recipe(
    id: id,
    title: title ?? this.title,
    servings: servings ?? this.servings,
    sections: sections ?? this.sections,
    householdId: householdId,
    prepTime: prepTime,
    cookTime: cookTime,
    cuisine: cuisine,
    tags: tags,
    source: source,
    photoUrl: photoUrl,
    notes: notes,
    createdBy: createdBy,
    isDeleted: isDeleted,
    updatedAt: updatedAt,
  );

  @override
  bool operator ==(Object other) => other is Recipe && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Recipe($id, $title)';
}
