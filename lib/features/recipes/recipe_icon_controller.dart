import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/recipe_icon.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../domain/text/text_normaliser.dart';

/// Draws a recipe's sketch icon in the background, after the save has landed
/// (spec §5.2, §6.1).
///
/// **On rule 4.** CLAUDE.md says anything automated that produces user data
/// passes a review screen first. An icon written straight into the library
/// without one is in tension with that, and the tension is settled — with
/// Brendan, deliberately, not quietly — in favour of writing it: an icon is
/// decorative, it makes no nutritional claim, it changes nothing a day is
/// logged against, and it is reversible in one tap from the editor. The rule
/// exists so a model cannot put a number, an ingredient or an order into the
/// household's data unseen; a drawing is none of those. What the rule is
/// really asking for is that the user stays in charge, so they are: an icon
/// can be redrawn or thrown away, and throwing it away keeps it away until
/// the title changes — see [needsDrawing], where that promise is actually
/// kept. Anything with a number in it still goes through review.
///
/// **Why it runs here and not in the editor.** Saving must never wait on a
/// picture. The editor fires this and pops; the icon appears when it arrives,
/// on whatever screen is showing the recipe by then, because it lands in the
/// store rather than in a widget's state.
class RecipeIconController {
  const RecipeIconController({
    required RecipeIconSource? source,
    required RecipeRepository recipes,
  }) : _source = source,
       _recipes = recipes;

  /// Null when there is no backend to reach: an unconfigured build simply has
  /// no icons, which is the state every recipe starts in anyway.
  final RecipeIconSource? _source;

  final RecipeRepository _recipes;

  bool get isAvailable => _source != null;

  /// Whether saving [titleNow] should spend a call on a drawing.
  ///
  /// Two reasons, and both are about a dish that has no drawing of *itself*:
  /// the recipe is new, or the title has materially changed. Not an
  /// ingredient edit, not a keystroke in the notes — those would pay to
  /// redraw a picture that would come back the same.
  ///
  /// **Not "it has no icon".** That was the rule, and it made the editor's
  /// removal control a lie: removing an icon and pressing Save fired a fresh
  /// paid call and landed a new sketch, so the one tap the rule-4 exception
  /// rests on did not actually undo anything. The same mechanism re-billed on
  /// every save of a recipe whose icon was missing because the answer failed
  /// validation or the month's picture budget was spent. An existing recipe
  /// with no icon is now left alone, and the way to get one is to ask — which
  /// is the "Draw one now" button the editor already offers, one tap away
  /// from where the removal happened.
  ///
  /// "Materially" is [normaliseKey]'s definition, the one the rest of the app
  /// already uses for "the same string": case, punctuation and spacing do not
  /// count, so fixing a capital letter or a stray full stop is free.
  static bool needsDrawing({
    required String? currentIcon,
    required String titleWhenOpened,
    required String titleNow,
    required bool isNewRecipe,
  }) =>
      (isNewRecipe && currentIcon == null) ||
      normaliseKey(titleWhenOpened) != normaliseKey(titleNow);

  /// Draws an icon for [recipeId] and stores it. True when one landed.
  ///
  /// Never throws. The answer is for the one caller who is waiting on it —
  /// the editor's own "Draw another", where somebody pressed a button and
  /// deserves to be told when nothing came of it. The background draw after a
  /// save ignores it, and should: the recipe is already safely saved by then,
  /// and a decorative picture that failed to arrive is not worth interrupting
  /// anybody over.
  Future<bool> drawFor({
    required String recipeId,
    required String title,
  }) async {
    final RecipeIconSource? source = _source;
    if (source == null || title.trim().isEmpty) return false;

    try {
      final String? svg = await source.draw(title: title);
      if (svg == null) return false;
      await _recipes.setIconSvg(recipeId, svg);
      return true;
    } on Object {
      // Swallowed, not reported: whether this is worth saying is the caller's
      // decision, and the two callers answer it differently.
      return false;
    }
  }

  /// Throws an icon away, at the user's request.
  Future<void> clear(String recipeId) => _recipes.setIconSvg(recipeId, null);
}

/// The controller, wired to whatever backend this build has.
final Provider<RecipeIconController> recipeIconControllerProvider =
    Provider<RecipeIconController>(
      (Ref ref) => RecipeIconController(
        source: ref.watch(recipeIconProvider),
        recipes: ref.watch(recipeRepositoryProvider),
      ),
    );
