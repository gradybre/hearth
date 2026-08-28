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
  String sectionId = 'section-main',
  bool optional = false,
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
  isOptional: optional,
  sortOrder: sortOrder,
);

RecipeStep aStep(
  String text, {
  String sectionId = 'section-main',
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
  String id = 'section-main',
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
}) => Recipe(
  id: id ?? _id('recipe'),
  householdId: householdId,
  title: title,
  servings: servings,
  sections:
      sections ??
      <RecipeSection>[
        aSection(
          ingredients: ingredients ?? const <RecipeIngredient>[],
          steps: steps ?? const <RecipeStep>[],
        ),
      ],
);

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
  List<ServingOption>? servingOptions,
  double? gramsPerMillilitre,
  FoodSource source = FoodSource.manual,
}) => Food(
  id: id ?? _id('food'),
  name: name,
  servingOptions: servingOptions ?? const <ServingOption>[],
  gramsPerMillilitre: gramsPerMillilitre,
  source: source,
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
