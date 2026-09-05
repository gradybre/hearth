import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

/// Builders that keep the domain tests readable. Ids are generated so a test
/// never has to invent one, but can pass its own where identity matters.
int _seq = 0;
String _id(String prefix) => '$prefix-${_seq++}';

RecipeIngredient anIngredient(
  String name, {
  num? amount,
  Unit? unit,
  String sectionId = _defaultSectionId,
  bool optional = false,
  bool needsNoMatch = false,
  String? foodId,
  String? prepNote,
  int sortOrder = 0,
  String? id,
}) => RecipeIngredient(
  id: id ?? _id('ing'),
  sectionId: sectionId,
  name: name,
  quantity: amount == null || unit == null ? null : Quantity.of(amount, unit),
  prepNote: prepNote,
  foodId: foodId,
  needsNoMatch: needsNoMatch,
  isOptional: optional,
  sortOrder: sortOrder,
);

RecipeStep aStep(
  String text, {
  String sectionId = _defaultSectionId,
  int stepNumber = 1,
  int? timerSeconds,
}) => RecipeStep(
  id: _id('step'),
  sectionId: sectionId,
  stepNumber: stepNumber,
  text: text,
  timerSeconds: timerSeconds,
);

RecipeSection aSection({
  String name = Recipe.defaultSectionName,
  String id = _defaultSectionId,
  int sortOrder = 0,
  List<RecipeIngredient> ingredients = const <RecipeIngredient>[],
  List<RecipeStep> steps = const <RecipeStep>[],
}) => RecipeSection(
  id: id,
  name: name,
  sortOrder: sortOrder,
  ingredients: ingredients,
  steps: steps,
);

Recipe aRecipe({
  String? id,
  String householdId = 'household-1',
  String title = 'Test recipe',
  double servings = 4,
  List<RecipeSection>? sections,
  List<RecipeIngredient>? ingredients,
  List<RecipeStep>? steps,
  List<String> tags = const <String>[],
  RecipeKind kind = RecipeKind.cooked,
  String? cuisine,
  Duration? prepTime,
  Duration? cookTime,
  bool isDeleted = false,
  String? iconSvg,
  DateTime? updatedAt,
}) {
  final String recipeId = id ?? _id('recipe');
  // Section ids are primary keys in their own right, so the default section
  // is named after its recipe rather than a shared constant. Two fixture
  // recipes built with the defaults used to collide the moment both reached
  // a real database.
  final String sectionId = 'sec-$recipeId';

  return Recipe(
    id: recipeId,
    householdId: householdId,
    title: title,
    servings: servings,
    tags: tags,
    kind: kind,
    cuisine: cuisine,
    prepTime: prepTime,
    cookTime: cookTime,
    isDeleted: isDeleted,
    iconSvg: iconSvg,
    updatedAt: updatedAt,
    sections:
        sections ??
        <RecipeSection>[
          aSection(
            id: sectionId,
            // Children left on `anIngredient`/`aStep`'s default section are
            // re-parented onto it, so a caller that never mentions sections
            // still gets a recipe whose children actually belong to one.
            ingredients: <RecipeIngredient>[
              for (final RecipeIngredient i
                  in ingredients ?? const <RecipeIngredient>[])
                i.sectionId == _defaultSectionId
                    ? i.copyWith(sectionId: sectionId)
                    : i,
            ],
            steps: <RecipeStep>[
              for (final RecipeStep step in steps ?? const <RecipeStep>[])
                step.sectionId == _defaultSectionId
                    ? RecipeStep(
                        id: step.id,
                        sectionId: sectionId,
                        stepNumber: step.stepNumber,
                        text: step.text,
                        timerSeconds: step.timerSeconds,
                      )
                    : step,
            ],
          ),
        ],
  );
}

/// The section id `anIngredient` and `aStep` default to, and the one
/// [aRecipe] re-parents off.
const String _defaultSectionId = 'section-main';

ServingOption aServing({
  required num amount,
  required Unit unit,
  required Macros macros,
  String? id,
  String? label,
}) => ServingOption(
  id: id ?? _id('serving'),
  label: label ?? '$amount ${unit.label}',
  amount: Quantity.of(amount, unit),
  macros: macros,
);

Food aFood(
  String name, {
  String? id,
  String? brand,
  String? barcode,
  List<ServingOption>? servingOptions,
  double? gramsPerMillilitre,
  String? menuGroup,
  int? menuOrder,
  FoodSource source = FoodSource.manual,
  DateTime? updatedAt,
  bool isDefault = false,
  bool isZeroCalorie = false,
  bool isModifier = false,
}) => Food(
  id: id ?? _id('food'),
  name: name,
  brand: brand,
  barcode: barcode,
  servingOptions: servingOptions ?? const <ServingOption>[],
  gramsPerMillilitre: gramsPerMillilitre,
  menuGroup: menuGroup,
  menuOrder: menuOrder,
  source: source,
  updatedAt: updatedAt,
  isDefault: isDefault,
  isZeroCalorie: isZeroCalorie,
  isModifier: isModifier,
);

/// A food defined per 100 g, the usual shape of an Open Food Facts record.
Food aFoodPer100g(
  String name, {
  required double kcal,
  double protein = 0,
  double carbs = 0,
  double fat = 0,
  String? id,
  double? gramsPerMillilitre,
}) => aFood(
  name,
  id: id,
  gramsPerMillilitre: gramsPerMillilitre,
  servingOptions: <ServingOption>[
    aServing(
      amount: 100,
      unit: Units.gram,
      macros: Macros(kcal: kcal, proteinG: protein, carbG: carbs, fatG: fat),
    ),
  ],
);

/// Small copy helpers so a food test can vary one field without restating the
/// whole constructor. Kept in the test tree rather than on the domain model,
/// which has no need for them.
extension FoodTestCopies on Food {
  Food withHousehold(String? id) => _copy(householdId: id);
  Food withBrand(String brand) => _copy(brand: brand);
  Food withBarcode(String barcode) => _copy(barcode: barcode);
  Food withStoreTag(String tag) => _copy(storeTag: tag);
  Food withDeleted() => _copy(isDeleted: true);
  Food asDefault() => _copy(isDefault: true);
  Food asZeroCalorie() => _copy(isZeroCalorie: true);

  /// A menu row published as a deduction (spec §5.2).
  Food asModifier() => _copy(isModifier: true);

  Food _copy({
    Object? householdId = _unset,
    String? brand,
    String? barcode,
    String? storeTag,
    bool? isDeleted,
    bool? isDefault,
    bool? isZeroCalorie,
    bool? isModifier,
  }) => Food(
    id: id,
    name: name,
    servingOptions: servingOptions,
    source: source,
    householdId: householdId == _unset
        ? this.householdId
        : householdId as String?,
    brand: brand ?? this.brand,
    storeTag: storeTag ?? this.storeTag,
    barcode: barcode ?? this.barcode,
    gramsPerMillilitre: gramsPerMillilitre,
    macrosOverridden: macrosOverridden,
    isDefault: isDefault ?? this.isDefault,
    isZeroCalorie: isZeroCalorie ?? this.isZeroCalorie,
    isModifier: isModifier ?? this.isModifier,
    isDeleted: isDeleted ?? this.isDeleted,
    updatedAt: updatedAt,
  );
}

const Object _unset = Object();
