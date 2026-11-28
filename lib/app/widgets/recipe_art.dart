import 'package:flutter/material.dart';

import '../theme/hearth_colors.dart';
import '../theme/hearth_theme.dart';

/// The drawings that have actually been made.
///
/// The registry in `recipe_artwork.dart` names every drawing the app knows
/// how to ask for, which is allowed to run ahead of the artist — it is also
/// the brief. This is the shorter list of ones that exist, and it is what
/// decides whether a picture is drawn.
///
/// A set rather than a look at the asset bundle, because asking the bundle
/// for a file that is not there is an error, not an answer: it logs a
/// Flutter exception, and every widget test in the app that asserts
/// `takeException()` is null would start failing for a picture nobody had
/// drawn yet. Declaring what exists costs one line per drawing in the same
/// change that adds the file.
///
/// Batch one, November 2026: six drawings, checked against §3 of the brief
/// and held to it by `artwork_is_line_art_test.dart`.
const Set<String> kArtworkShipped = <String>{
  'chilli-bowl',
  'porridge-jar',
  'pot-pie',
  'ramen-bowl',
  'soup-bowl',
  'stew-pot',
};

/// A drawing of the *kind* of thing a recipe is (spec §5.2, §6.1).
///
/// Below a recipe's own photograph and above its own sketch: a photograph
/// is this dish, a sketch is this recipe's doodle of itself, and this is the
/// house's drawing of the category. Nothing at all when the category has no
/// drawing yet, which is most of them to begin with — the caller falls
/// through.
///
/// **Tinted, not painted.** The art is single-tone line work on
/// transparency, and the colour comes from the theme through a `srcIn`
/// blend. That is what makes one file correct in light and dark, and it is
/// the same bargain [HearthSketch] makes with vector marks: §6.1 ships both
/// themes from day one, so art with its own colours would be wrong in one
/// of them. Grain and shading survive it, because they live in the alpha.
///
/// Decorative. The recipe's name carries the meaning, and a screen reader
/// announcing "drawing of a stew pot" in front of "Weeknight chilli" reads
/// the decoration twice and the recipe once (spec §6.3).
class RecipeArt extends StatelessWidget {
  const RecipeArt({
    required this.artworkId,
    required this.size,
    this.color,
    this.shipped = kArtworkShipped,
    super.key,
  });

  /// From `pickRecipeArtwork`, or null when nothing fitted.
  final String? artworkId;

  final double size;

  /// Defaults to the body text colour, like every other drawing in the app.
  final Color? color;

  /// Which drawings exist. Injectable so a test can stand one up without
  /// the app having to ship it.
  final Set<String> shipped;

  /// Where a drawing lives once it has been made.
  ///
  /// PNG, for now. The drawings arrive as PNG with an alpha channel and
  /// nothing on this machine converts to WebP — which is the format the
  /// whole set will want, because a hundred and fifty of these at the size
  /// batch one came in is twenty megabytes of app. One line here and a
  /// pass of `cwebp` when the set is complete.
  static String assetFor(String id) => 'assets/art/$id.png';

  /// Whether this would draw anything.
  ///
  /// For a caller deciding on layout before it builds — a row leaves no gap
  /// where a picture was never going to appear.
  bool get hasArt => artworkId != null && shipped.contains(artworkId);

  @override
  Widget build(BuildContext context) {
    if (!hasArt) return const SizedBox.shrink();
    final HearthColors colors = context.colors;
    return ExcludeSemantics(
      child: Image.asset(
        assetFor(artworkId!),
        width: size,
        height: size,
        color: color ?? colors.textSecondary,
        // The art is line work on transparency, so the tint is the whole of
        // its colour and the alpha carries the drawing.
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        // Belt and braces. The set above is meant to make this unreachable;
        // if the two ever disagree, a recipe row loses its picture rather
        // than the screen losing a frame.
        errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
            const SizedBox.shrink(),
      ),
    );
  }
}
