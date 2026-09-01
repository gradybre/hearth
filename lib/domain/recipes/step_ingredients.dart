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

  /// Words that name what a recipe is *making* rather than what goes into it.
  ///
  /// Nearly every recipe says "until the sauce is thick" at some point, and
  /// it means the pan, not the bottle. So an ingredient whose head noun is one
  /// of these has to be named more fully — "soy sauce" — before a step counts
  /// as mentioning it. Without that, a beef and broccoli recipe put "1⅛ cups
  /// low-sodium soy sauce" beside the step that whisks cornstarch into water.
  static const Set<String> _preparations = <String>{
    'batter',
    'dough',
    'dressing',
    'filling',
    'glaze',
    'marinade',
    'sauce',
    'topping',
  };

  /// The ingredients of [section] that [step] appears to use, in the order
  /// the section lists them.
  ///
  /// Only quantified ingredients: "salt to taste" has no amount to show, and
  /// a step mentioning salt is not helped by being told so.
  /// [elsewhere] lets a step reach an ingredient another section holds, when
  /// no section holds two of that name.
  ///
  /// Section scoping is right and stays the rule: two teaspoons of cumin in
  /// the sauce and two in the rub must read as two in each place. But an
  /// import can put a step and its ingredient in different sections — the
  /// recipe Brendan photographed whisks cornstarch in the sauce section while
  /// listing the cornstarch under "Finishing and assembly" — and scoping then
  /// hides the very number the step needs. A name that appears in exactly one
  /// section cannot be ambiguous, so reaching for it costs nothing the
  /// scoping was protecting.
  static List<RecipeIngredient> forStep(
    RecipeStep step,
    RecipeSection section, {
    List<RecipeSection> elsewhere = const <RecipeSection>[],
  }) {
    final List<String> words = <String>[
      for (final String word in normaliseKey(step.text).split(' '))
        if (word.isNotEmpty) word,
    ];
    if (words.isEmpty) return const <RecipeIngredient>[];

    final List<RecipeIngredient> candidates = <RecipeIngredient>[
      ...section.ingredients,
      ..._unambiguousElsewhere(section, elsewhere),
    ];

    // Every ingredient's best evidence, as a run of the step's own words.
    final Map<String, _Mention> found = <String, _Mention>{};
    for (final RecipeIngredient ingredient in candidates) {
      if (ingredient.quantity == null) continue;
      final _Mention? mention = _bestMention(words, ingredient.name);
      if (mention != null) found[ingredient.id] = mention;
    }

    // Where two ingredients claim the same words, the longer claim is the
    // real one. "Red pepper flakes" covers all three of its words, so the
    // bell peppers' lone "pepper" inside it is not a second mention — it is
    // the same three words being read twice.
    final List<_Mention> claims = found.values.toList(growable: false);
    return <RecipeIngredient>[
      for (final RecipeIngredient ingredient in candidates)
        if (found[ingredient.id] case final _Mention mine)
          if (!claims.any((_Mention other) => other.beats(mine))) ingredient,
    ];
  }

  /// Ingredients from other sections whose name nothing else shares.
  ///
  /// A name held by two sections is exactly the ambiguity scoping exists for,
  /// so it stays out of reach. One held by one section is simply somewhere
  /// else in the same recipe.
  static List<RecipeIngredient> _unambiguousElsewhere(
    RecipeSection section,
    List<RecipeSection> all,
  ) {
    final Map<String, int> sectionsPerName = <String, int>{};
    for (final RecipeSection other in all) {
      for (final String name in <String>{
        for (final RecipeIngredient i in other.ingredients)
          normaliseKey(i.name),
      }) {
        sectionsPerName[name] = (sectionsPerName[name] ?? 0) + 1;
      }
    }

    return <RecipeIngredient>[
      for (final RecipeSection other in all)
        if (other.id != section.id)
          for (final RecipeIngredient ingredient in other.ingredients)
            if (sectionsPerName[normaliseKey(ingredient.name)] == 1) ingredient,
    ];
  }

  /// The longest run of [words] that names [ingredientName], or null.
  ///
  /// Anchored at the head noun and grown leftwards: English puts the head
  /// last, so "low-sodium soy sauce" is looked for as "soy sauce" before
  /// "sauce", and "unsalted beef broth" can only ever be found as a broth —
  /// which is why a step saying "stir the beef in" means the ground beef and
  /// nothing else.
  static _Mention? _bestMention(List<String> words, String ingredientName) {
    final List<String> name = <String>[
      for (final String word in normaliseKey(ingredientName).split(' '))
        if (word.length >= 3 && !_tooCommon.contains(word)) _singular(word),
    ];
    if (name.isEmpty) return null;

    // A word for the dish itself has to be qualified to count.
    final int shortest = _preparations.contains(name.last) ? 2 : 1;
    if (name.length < shortest) return null;

    for (int length = name.length; length >= shortest; length--) {
      final List<String> phrase = name.sublist(name.length - length);
      final int at = _indexOfPhrase(words, phrase);
      if (at >= 0) return _Mention(start: at, length: length);
    }
    return null;
  }

  /// Where [phrase] appears in [words] as consecutive whole words, or -1.
  static int _indexOfPhrase(List<String> words, List<String> phrase) {
    for (int i = 0; i + phrase.length <= words.length; i++) {
      bool all = true;
      for (int j = 0; j < phrase.length; j++) {
        if (_singular(words[i + j]) != phrase[j]) {
          all = false;
          break;
        }
      }
      if (all) return i;
    }
    return -1;
  }

  static String _singular(String word) =>
      word.length > 3 && word.endsWith('s') && !word.endsWith('ss')
      ? word.substring(0, word.length - 1)
      : word;
}

/// Where in a step an ingredient was found, and how much of it was named.
///
/// Length is the evidence: three words beat one, and the loser is not a
/// second ingredient but the same words read twice.
class _Mention {
  const _Mention({required this.start, required this.length});

  final int start;
  final int length;

  int get end => start + length;

  /// Whether this claim covers [other]'s words and says more than it does.
  bool beats(_Mention other) =>
      length > other.length && start <= other.start && end >= other.end;
}
