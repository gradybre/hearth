import 'package:meta/meta.dart';

import '../text/text_normaliser.dart';
import 'food_concept.dart';

/// Whether an ingredient line is one that will never have a food behind it
/// (spec §5.3).
///
/// A pinch of salt has nothing to match and never will, but the editor counted
/// it among the unmatched all the same — so every recipe carried a handful of
/// permanently wrong-looking lines, and a warning that is always on stops being
/// read.
///
/// Deliberately not the existing `isOptional`. That is parsed out of the
/// recipe's own words and printed as "optional" on the recipe page; salt in a
/// bread recipe is not optional, and saying it is to quiet a warning would
/// misreport the recipe.
///
/// ## Matched by concept, and in the opposite direction to a default food
///
/// This is the subtle part, so it is stated once, here. A default food
/// **covers** a line: the food says everything the line said, so a
/// "Maverick Ranch 96/4 Ground Beef" answers "ground beef". A seasoning rule
/// is **covered by** a line: the line says everything the rule said, because
/// salt is still salt when it is kosher salt.
///
/// Containment on its own is too eager — "salt pork" contains "salt", and salt
/// pork is very much a food with macros. So what the line adds on top of the
/// rule has to be a *modifier*, not another ingredient. "Kosher salt" passes;
/// "salt pork" does not, because pork is not in [_modifiers].
@immutable
class NoMatchRules {
  const NoMatchRules({
    this.marked = const <String>{},
    this.unmarked = const <String>{},
  });

  /// Wordings this household has marked, as normalised keys.
  final Set<String> marked;

  /// Built-ins this household has explicitly turned back off.
  ///
  /// The seed list is shipped rather than written into anybody's data, so
  /// disagreeing with it has to be recordable — otherwise a built-in Hearth
  /// got wrong could never be undone.
  final Set<String> unmarked;

  static const NoMatchRules none = NoMatchRules();

  /// Whether [ingredientName] is a line that needs no food.
  bool covers(String ingredientName) {
    final String key = normaliseKey(ingredientName);
    if (key.isEmpty) return false;
    if (unmarked.contains(key)) return false;
    if (marked.contains(key)) return true;

    final FoodConcept line = FoodConcept.of(ingredientName);
    if (line.isEmpty) return false;

    for (final String rule in <String>[...marked, ...seasonings]) {
      if (unmarked.contains(rule)) continue;
      if (_answers(line, FoodConcept.of(rule))) return true;
    }
    return false;
  }

  /// Whether [line] is this [rule] wearing a modifier or two.
  static bool _answers(FoodConcept line, FoodConcept rule) {
    if (rule.isEmpty) return false;
    if (!line.base.containsAll(rule.base)) return false;

    // Everything the line says beyond the rule has to be a way of describing
    // it, not another ingredient. This is what keeps "salt pork" a food.
    return line.base
        .where((String word) => !rule.base.contains(word))
        .every(_modifiers.contains);
  }

  /// Ways of describing a seasoning that do not make it a different food.
  ///
  /// Finite, and that is the safe direction: a modifier this does not know
  /// means the line is not recognised and goes on asking to be matched, which
  /// costs a nag. Being too permissive would drop a real ingredient out of a
  /// recipe's macros silently, which costs the number.
  ///
  /// Only words [FoodConcept] leaves in a name's *base* belong here. It
  /// already reads "whole", "white", "smoked" and "crushed" as a kind or as
  /// noise, so those never reach this set and listing them would suggest a
  /// job this does that it does not.
  static const Set<String> _modifiers = <String>{
    'kosher',
    'sea',
    'table',
    'flaky',
    'flake',
    'coarse',
    'fine',
    'finely',
    'cracked',
    'freshly',
    'ground',
    'dried',
    'dry',
    'granulated',
    'powdered',
    'powder',
    'pink',
    'black',
    'red',
    'green',
    'toasted',
    'hot',
    'sweet',
    'mild',
    'iodised',
    'iodized',
    'himalayan',
    'rock',
    'cold',
    'warm',
    'boiling',
    'filtered',
    'leaf',
    'leaves',
    'seed',
    'seeds',
    'stick',
    'sticks',
    'taste',
  };

  /// What Hearth knows is a seasoning before anybody tells it.
  ///
  /// Shipped as a list the app *knows*, not as rows written into a household:
  /// nothing is in anybody's data until they put it there, the list can grow in
  /// a later version without a data migration, and disagreeing with an entry is
  /// a deliberate act recorded in [unmarked] rather than an edit to something
  /// that was never asked for.
  ///
  /// Every entry earns its place by carrying no macros worth counting at the
  /// amounts a recipe uses. Things that plainly do — butter, olive oil, honey,
  /// soy sauce — are absent however much they feel like seasonings.
  static const Set<String> seasonings = <String>{
    'salt',
    'pepper',
    'peppercorn',
    'water',
    'ice',
    'cumin',
    'paprika',
    'oregano',
    'basil',
    'thyme',
    'rosemary',
    'sage',
    'parsley',
    'cilantro',
    'coriander',
    'chives',
    'dill',
    'mint',
    'tarragon',
    'marjoram',
    'bay leaf',
    'cinnamon',
    'nutmeg',
    'clove',
    'allspice',
    'cardamom',
    'turmeric',
    'ginger powder',
    'garlic powder',
    'onion powder',
    'chilli powder',
    'chili powder',
    'chilli flakes',
    'chili flakes',
    'red pepper flakes',
    'cayenne',
    'curry powder',
    'garam masala',
    'italian seasoning',
    'poultry seasoning',
    'old bay',
    'mustard powder',
    'celery seed',
    'fennel seed',
    'caraway',
    'anise',
    'saffron',
    'sumac',
    'zaatar',
    'furikake',
    'msg',
    'baking soda',
    'baking powder',
    'cream of tartar',
    'food colouring',
    'food coloring',
    'vanilla extract',
    'almond extract',
    'cooking spray',
  };

  NoMatchRules copyWith({Set<String>? marked, Set<String>? unmarked}) =>
      NoMatchRules(
        marked: marked ?? this.marked,
        unmarked: unmarked ?? this.unmarked,
      );

  /// The built-in list, as the keys a household row would use to override one.
  static Set<String> get seasoningKeys => <String>{
    for (final String seasoning in seasonings) normaliseKey(seasoning),
  };
}
