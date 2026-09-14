import 'package:meta/meta.dart';

import '../../domain/units/quantity.dart';
import 'recipe_ai.dart';

/// One serving as a Nutrition Facts panel states it (spec §5.5).
@immutable
class LabelServing {
  const LabelServing({
    required this.amount,
    required this.unitId,
    this.kcal = 0,
    this.proteinG = 0,
    this.carbG = 0,
    this.fatG = 0,
    this.fiberG,
    this.sodiumMg,
    this.cholesterolMg,
  });

  final double amount;

  /// A unit id Hearth already knows — 'g', 'oz', 'cup'. The function narrows
  /// the model to this list, so anything else never reaches here.
  final String unitId;

  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  /// The three minor nutrients, null where the panel did not print them
  /// (spec §5.6). A US label is required by law to carry all three, so these
  /// are usually there — but a cropped photo is a real thing, and a zero
  /// would be Hearth asserting a fact no label stated.
  final double? fiberG;
  final double? sodiumMg;
  final double? cholesterolMg;
}

/// What a photographed label says.
///
/// The plural in [servings] is the point. A US panel usually states one
/// portion several ways — "Serving size 1oz (28g/about 1/4 cup)" — and a
/// weight and a volume for the same portion are, between them, the only
/// statement of how dense the food is. That is the fact a recipe line
/// measured in cups needs from a food the shops sell by weight, and no other
/// source in the chain provides it.
@immutable
class LabelReading {
  const LabelReading({
    required this.servings,
    this.name,
    this.brand,
    this.uncertain = const <AiUncertainty>[],
  });

  final List<LabelServing> servings;

  /// Null when the photo is of the panel alone, which is the common case.
  final String? name;
  final String? brand;

  /// Anything blurred, cut off, or ambiguous (spec §5.3's flag-never-guess).
  final List<AiUncertainty> uncertain;

  bool get isEmpty => servings.isEmpty;
}

/// What a package says it holds — "NET WT 24 OZ" (spec §5.7).
///
/// A different question from [LabelReading], off the same box. The Nutrition
/// Facts panel states a *serving*; the net contents state the *packet*, and
/// the shopping list needs the second to count jars rather than weigh them.
/// Reading both from one answer was tempting and wrong: a label photographed
/// panel-first usually does not have the net weight in frame at all, and a
/// mode that had to answer both would be a mode that guessed at one.
@immutable
class PackReading {
  const PackReading({
    this.size,
    this.name,
    this.brand,
    this.uncertain = const <AiUncertainty>[],
  });

  /// How much is in the packet, or null when nothing legible said.
  ///
  /// Null is a first-class answer rather than a failure. A wrong pack size
  /// does not fail loudly — it silently buys the wrong amount — so a photo
  /// that did not show the net contents has to come back saying so, not
  /// carrying a number worked out from something else on the box.
  final Quantity? size;

  /// What the packet calls itself, when the front was in frame.
  final String? name;
  final String? brand;

  /// Anything blurred, cut off, or ambiguous (spec §5.3's flag-never-guess).
  final List<AiUncertainty> uncertain;

  bool get isEmpty => size == null;
}

/// Reading a nutrition label out of a photo, behind an interface
/// (CLAUDE.md rule 7).
///
/// The fallback chain in §5.5 ends at manual entry: when a barcode misses and
/// no source has the food, the only way out was typing four macros and two
/// servings off a packet already in your hand. This is the same fallback with
/// the typing removed — and, unlike the databases above it, it can answer the
/// question the databases cannot, because it is reading the actual box.
///
/// Nothing here saves anything. Every reading lands in the food editor to be
/// checked first (CLAUDE.md rule 4): a misread panel looks exactly as
/// confident as a correct one, and the review screen is what catches it.
abstract interface class LabelReader {
  Future<LabelReading> read(List<AiImage> images);

  /// What the packet says it holds, off a photo of the packet.
  ///
  /// On this interface rather than one of its own because it is the same key,
  /// the same model, the same image plumbing and the same size caps — the
  /// reasoning that put label reading into `recipe-ai` in the first place. A
  /// second interface would mean a second provider, a second fake and a
  /// second set of size guards, all to keep a name accurate.
  Future<PackReading> readPack(List<AiImage> images);
}
