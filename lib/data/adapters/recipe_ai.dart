import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Something the model could not read confidently (spec §5.3).
///
/// The whole point of carrying these separately is that a flagged guess is
/// useful and a confident wrong number is not: "1/2 or 12 tsp" gets
/// transcribed *and* pointed at, so the user checks one field instead of
/// re-reading the whole recipe.
@immutable
class AiUncertainty {
  const AiUncertainty({required this.field, required this.note});

  final String field;
  final String note;
}

/// One section as the model returned it — text, not parsed rows.
///
/// Hearth already parses ingredient and direction text, already shows that
/// parse back before saving, and the user already corrects it there. Asking
/// the model to parse as well would add a way for it to be wrong that nothing
/// downstream would catch.
@immutable
class AiSection {
  const AiSection({
    required this.name,
    required this.ingredientsText,
    required this.directionsText,
  });

  final String name;
  final String ingredientsText;
  final String directionsText;
}

/// The model's own guess at what one ingredient line contributes (spec §5.4).
///
/// A last resort, and never trusted on its own. Generated recipes have their
/// ingredients run through the real OFF → USDA chain at save time; these are
/// used only for the lines that chain cannot match, and are labelled as
/// estimates when they are. A rough number that admits to being rough is
/// worth more than a silent zero.
@immutable
class AiEstimate {
  const AiEstimate({
    required this.ingredient,
    required this.kcal,
    this.proteinG = 0,
    this.carbG = 0,
    this.fatG = 0,
  });

  /// The ingredient line as the model wrote it, which is how it is matched
  /// back to a row on the review screen.
  final String ingredient;

  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;
}

/// A recipe the model produced, before anyone has looked at it.
@immutable
class AiRecipe {
  const AiRecipe({
    required this.title,
    required this.sections,
    this.servings,
    this.prepMinutes,
    this.cookMinutes,
    this.cuisine,
    this.tags = const <String>[],
    this.uncertain = const <AiUncertainty>[],
    this.estimates = const <AiEstimate>[],
    this.reply,
    this.usage,
  });

  final String title;
  final List<AiSection> sections;
  final double? servings;
  final int? prepMinutes;
  final int? cookMinutes;
  final String? cuisine;
  final List<String> tags;

  /// Fields worth checking before saving (spec §5.3).
  final List<AiUncertainty> uncertain;

  /// Per-ingredient fallbacks, used only where real data cannot be found
  /// (spec §5.4). Empty for an extraction.
  final List<AiEstimate> estimates;

  /// What to say back in the chat. Null when extracting (spec §5.4).
  final String? reply;

  /// Where the month's AI budget stands after this call (spec §3, §8.1).
  ///
  /// Null when the function did not say — an older deployment, or a counter
  /// that could not be read. Absent is not zero, and the screens treat it as
  /// "no news" rather than as "nothing spent".
  final AiUsage? usage;
}

/// One turn of the generation conversation (spec §5.4).
@immutable
class AiTurn {
  const AiTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

/// The month's AI spend against its ceiling (spec §3, §8.1).
///
/// Returned with every answer rather than fetched separately: the number is
/// only interesting next to a thing that just spent some of it, and a second
/// round trip to learn it would itself be a cost.
@immutable
class AiUsage {
  const AiUsage({
    required this.spentUsd,
    required this.ceilingUsd,
    required this.fraction,
    required this.warn,
  });

  final double spentUsd;
  final double ceilingUsd;

  /// 0..1 and beyond. Past 1 the function refuses, so the app only ever sees
  /// this above 1 on the refusal itself.
  final double fraction;

  /// Whether the app should say something. Decided server-side so the
  /// threshold lives in one place rather than in every screen that shows it.
  final bool warn;

  int get percent => (fraction * 100).round();
}

/// An image on its way to extraction.
@immutable
class AiImage {
  const AiImage({required this.bytes, required this.mediaType});

  final Uint8List bytes;

  /// 'image/jpeg', 'image/png' — what the API is told this is.
  final String mediaType;
}

/// Raised when import or generation could not complete.
///
/// Carries a sentence worth showing: §5.3 and §5.4 both require failing soft
/// with a retry, and "something went wrong" gives the user nothing to decide
/// with.
class RecipeAiException implements Exception {
  const RecipeAiException(this.message, {this.isRetryable = true});

  final String message;

  /// False when retrying the identical request cannot help — a bad URL, an
  /// image too large, a key that is not configured.
  final bool isRetryable;

  @override
  String toString() => message;
}

/// Recipe import and generation, behind an interface (CLAUDE.md rule 7).
///
/// The only implementation goes through an Edge Function because the API key
/// cannot ship in the client (§8.1). The interface exists so that stays true
/// of any future provider, and so every screen above it can be tested without
/// a network or a key.
abstract interface class RecipeAiSource {
  /// Reads a recipe out of images, a page, or both (spec §5.3).
  ///
  /// Several images are pages of *one* recipe, not several — that is the
  /// MacrosFirst migration path, where a recipe spans two or three screens.
  /// [text] is a recipe somebody pasted or shared as words — the usual shape
  /// of an Instagram DM, where the whole thing arrives as a message.
  /// [notes] are the user's own instructions about the source — which end of
  /// a range to take, that the stated yield is wrong, that half the
  /// screenshot is an advert. They override what the source appears to say.
  Future<AiRecipe> extract({
    List<AiImage> images = const <AiImage>[],
    String? url,
    String? text,
    String? notes,
  });

  /// Writes or revises a recipe from a conversation (spec §5.4).
  ///
  /// [profile] is the user's food profile, passed as standing context so
  /// allergies and dislikes do not have to be restated every turn.
  /// [recipe] is an existing recipe to revise, as text. Given, the
  /// conversation is about changing that rather than writing something new —
  /// which is what the editor's chat is for.
  Future<AiRecipe> generate({
    required List<AiTurn> turns,
    Map<String, Object?> profile = const <String, Object?>{},
    String? recipe,
  });
}
