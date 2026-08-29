import 'package:meta/meta.dart';

/// What the household member wants out of a recipe (spec §4, §5.4).
///
/// Read by the generator so allergies and dislikes never have to be restated.
/// The distinction between them is load-bearing: an allergy is a hard
/// constraint the model must not break, a dislike is steering the user can
/// overrule in conversation. Folding them together would lose exactly the
/// thing that matters.
///
/// Private per user (§8.2). A partner's dislikes are not the household's
/// business, even though the recipe that comes out of them is shared.
@immutable
class FoodProfile {
  const FoodProfile({
    required this.userId,
    this.allergies = const <String>[],
    this.dislikes = const <String>[],
    this.dietaryPreferences = const <String>[],
    this.preferredMealTypes = const <String>[],
    this.caloriesPerMeal,
    this.proteinPerMealG,
  });

  /// An empty profile, which is a perfectly good one — §5.8 makes the
  /// questionnaire skippable, so "no constraints" must work everywhere.
  factory FoodProfile.empty(String userId) => FoodProfile(userId: userId);

  final String userId;

  /// Hard constraints. Never to be broken, whatever the conversation says.
  final List<String> allergies;

  /// Soft constraints — avoided unless the user asks for them anyway.
  final List<String> dislikes;

  /// "vegetarian", "low carb", "high protein".
  final List<String> dietaryPreferences;

  /// "bowls", "soups", "rice bowls" — shapes of meal, not dishes.
  final List<String> preferredMealTypes;

  /// Roughly what a meal should come to, as the user thinks of it. Null means
  /// no opinion, which is not the same as zero.
  final double? caloriesPerMeal;
  final double? proteinPerMealG;

  bool get isEmpty =>
      allergies.isEmpty &&
      dislikes.isEmpty &&
      dietaryPreferences.isEmpty &&
      preferredMealTypes.isEmpty &&
      caloriesPerMeal == null &&
      proteinPerMealG == null;

  /// What the generator is told, with the empty parts left out.
  ///
  /// Omitting rather than sending empty lists is deliberate: an empty
  /// `allergies: []` reads as a considered "none", and the difference between
  /// that and "not asked" is not worth spending the model's attention on.
  Map<String, Object?> toPrompt() => <String, Object?>{
    if (allergies.isNotEmpty) 'allergies': allergies,
    if (dislikes.isNotEmpty) 'dislikes': dislikes,
    if (dietaryPreferences.isNotEmpty)
      'dietary_preferences': dietaryPreferences,
    if (preferredMealTypes.isNotEmpty)
      'preferred_meal_types': preferredMealTypes,
    if (caloriesPerMeal != null) 'calories_per_meal': caloriesPerMeal,
    if (proteinPerMealG != null) 'protein_per_meal_g': proteinPerMealG,
  };

  FoodProfile copyWith({
    List<String>? allergies,
    List<String>? dislikes,
    List<String>? dietaryPreferences,
    List<String>? preferredMealTypes,
    double? caloriesPerMeal,
    double? proteinPerMealG,
    bool clearCaloriesPerMeal = false,
    bool clearProteinPerMealG = false,
  }) => FoodProfile(
    userId: userId,
    allergies: allergies ?? this.allergies,
    dislikes: dislikes ?? this.dislikes,
    dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
    preferredMealTypes: preferredMealTypes ?? this.preferredMealTypes,
    caloriesPerMeal: clearCaloriesPerMeal
        ? null
        : caloriesPerMeal ?? this.caloriesPerMeal,
    proteinPerMealG: clearProteinPerMealG
        ? null
        : proteinPerMealG ?? this.proteinPerMealG,
  );
}

/// Turning a comma-separated line into a list and back (spec §5.8).
///
/// The editor asks for "peanuts, shellfish" rather than making the user add
/// them one chip at a time — a list of three things is a sentence, and typing
/// it should feel like typing a sentence.
abstract final class ProfileList {
  static List<String> parse(String value) => <String>[
    for (final String part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  static String format(List<String> values) => values.join(', ');
}
