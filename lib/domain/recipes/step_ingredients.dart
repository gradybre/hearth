import '../models/recipe.dart';
import '../text/text_normaliser.dart';

/// Which of a section's ingredients a direction step is talking about
/// (spec §5.2's cook-along reading).
///
/// A step says "brown the ground beef" and the amount lives twenty lines
/// above it in the ingredient list. Showing it beside the step is the whole
/// difference between cooking from a recipe and scrolling back and forth
/// through one.
///
/// **Scoped to the step's own section, never the whole recipe.** A recipe
/// with cumin in its sauce and cumin in its rub has two separate amounts,
/// and a cook browning the beef needs the rub's two teaspoons, not the four
/// that adding them together would produce. Sections already own both their
/// ingredients and their steps, which is exactly the split this needs.
abstract final class StepIngredients {
  /// Words too common to identify anything, and too common to risk.
  ///
  /// "Oil" is deliberately absent: a step saying "heat the oil" really does
  /// mean the oil in the list. These are the words that would match nearly
  /// every step in every recipe.
  static const Set<String> _tooCommon = <String>{
    'and',
    'for',
    'more',
    'mix',
    'mixture',
    'pieces',
    'the',
    'to',
  };

  /// The ingredients of [section] that [step] appears to use, in the order
  /// the section lists them.
  ///
  /// Only quantified ingredients: "salt to taste" has no amount to show, and
  /// a step mentioning salt is not helped by being told so.
  static List<RecipeIngredient> forStep(
    RecipeStep step,
    RecipeSection section,
  ) {
    final String haystack = normaliseKey(step.text);
    if (haystack.isEmpty) return const <RecipeIngredient>[];

    return <RecipeIngredient>[
      for (final RecipeIngredient ingredient in section.ingredients)
        if (ingredient.quantity != null && _mentions(haystack, ingredient))
          ingredient,
    ];
  }

  /// Whether a step's text refers to this ingredient.
  ///
  /// Keyed on the head noun — the last significant word of the name, since
  /// English puts it last. "Ground beef" is beef, "yellow onion" is onion,
  /// and a step saying "add the onion" means the yellow one because it is
  /// the only onion this section has. Matching on *any* word instead would
  /// tie "ground beef" to a step about ground cumin.
  static bool _mentions(String haystack, RecipeIngredient ingredient) {
    final String? head = _headNoun(ingredient.name);
    if (head == null) return false;
    return _containsWord(haystack, head);
  }

  /// The last word of a name worth matching on, or null when there is none.
  static String? _headNoun(String name) {
    final List<String> words = <String>[
      for (final String word in normaliseKey(name).split(' '))
        if (word.length >= 3 && !_tooCommon.contains(word)) word,
    ];
    if (words.isEmpty) return null;

    // Singularised so "2 eggs" is found by a step that says "the egg", and
    // vice versa. Only the plain -s: -es and -ies rules would turn
    // "molasses" into "molasse" and cost more than they buy.
    return _singular(words.last);
  }

  static String _singular(String word) =>
      word.length > 3 && word.endsWith('s') && !word.endsWith('ss')
      ? word.substring(0, word.length - 1)
      : word;

  /// Whether [word] appears in [haystack] as a whole word, give or take a
  /// trailing plural.
  static bool _containsWord(String haystack, String word) {
    for (final String candidate in haystack.split(' ')) {
      if (_singular(candidate) == word) return true;
    }
    return false;
  }
}
