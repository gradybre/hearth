import 'package:meta/meta.dart';

import '../../domain/shopping/walmart_link_reading.dart';
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
/// portion several ways — "Serving size 2/3 cup (85g)" — and a weight and a
/// volume for the same portion are, between them, the only statement of how
/// dense the food is. That is the fact a recipe line measured in cups needs
/// from a food the shops sell by weight, and no other source in the chain
/// provides it.
@immutable
class LabelReading {
  const LabelReading({
    required this.servings,
    this.name,
    this.brand,
    this.uncertain = const <AiUncertainty>[],
    this.packageSize,
    this.servingsPerContainer,
    this.servingsApproximate = false,
    this.packageBasis = 'unknown',
    this.fieldSources = const <String, String>{},
    this.walmartLink = const WalmartLinkReading.notFound(),
  });

  final List<LabelServing> servings;

  /// Photo provenance for the transcribed package and serving facts.
  ///
  /// 'nutrition', 'package', 'both' or 'unknown', by field. Advisory: it is
  /// the model's account of its own reading, and an older server sends none
  /// at all. The request's own intent — which photos were actually sent —
  /// is the authority, and lives in [LabelRequestIntent].
  final Map<String, String> fieldSources;

  /// Null when the photo is of the panel alone, which is the common case.
  final String? name;
  final String? brand;

  /// Anything blurred, cut off, or ambiguous (spec §5.3's flag-never-guess).
  final List<AiUncertainty> uncertain;

  /// What the front of the package says it holds — 'NET WT 10 OZ' — when a
  /// front-of-package photo was part of this read (spec §5.7/R11). Null when
  /// no package photo was supplied or none was legible.
  final Quantity? packageSize;

  /// How many of the selected nutrition serving the package states it
  /// holds, straight off the label. Null when not stated or not read.
  final double? servingsPerContainer;

  /// True when the panel itself hedges the count — 'about 3.5 servings'.
  final bool servingsApproximate;

  /// 'as_packaged', 'prepared', 'drained', or 'unknown' when the panel did
  /// not say or the photo did not make it clear.
  final String packageBasis;

  /// A Walmart product link read off screenshots, when the label read also
  /// included them. [WalmartLinkReading.notFound] when it did not.
  final WalmartLinkReading walmartLink;

  bool get isEmpty =>
      servings.isEmpty &&
      packageSize == null &&
      servingsPerContainer == null &&
      !walmartLink.hasLink;

  /// This reading with its serving nutrition removed, and a note saying why
  /// (spec R11).
  ///
  /// Everything the package photographs *could* state — the net contents, a
  /// printed count, the name, the link — is kept. Only the nutrition goes:
  /// no panel photo was selected, so nothing in this reply was asked to come
  /// off one, and nutrition nobody asked for is not nutrition to overwrite
  /// somebody's own with.
  LabelReading withoutPanelNutrition() => LabelReading(
    servings: const <LabelServing>[],
    name: name,
    brand: brand,
    packageSize: packageSize,
    servingsPerContainer: servingsPerContainer,
    servingsApproximate: servingsApproximate,
    packageBasis: packageBasis,
    fieldSources: <String, String>{...fieldSources, 'servings': 'package'},
    walmartLink: walmartLink,
    uncertain: <AiUncertainty>[
      ...uncertain,
      const AiUncertainty(
        field: 'servings',
        note:
            'Only the package photo was selected, so the nutrition that came '
            'back with it was not transcribed from a panel and was dropped.',
      ),
    ],
  );
}

/// The role a photo was chosen for, as the client states it.
///
/// Two words, shared by the picker, the controller, the adapter and the Edge
/// Function's own `labelRequestIntent`. They were string literals in four
/// places, which is three places for them to drift.
abstract final class LabelPhotoRole {
  static const String nutrition = 'nutrition';
  static const String package = 'package';

  static bool isKnown(String? role) => role == nutrition || role == package;
}

/// What a label request was actually *for*, judged by the photos it carried
/// (spec R11).
///
/// The authority on whether a reply may state nutrition. Provenance the model
/// returns is its own account of its own work: an older server sends none at
/// all, and a mistaken or an invented one reads exactly like a true one.
/// Which slots the user filled is a fact the client knows for certain.
///
/// It states a *purpose*, not the contents of any pixel. Nothing here knows
/// whether the photo in the package slot happens to show a panel as well.
/// What it knows is that nobody asked for one to be read, which is enough:
/// nutrition nobody asked for is not nutrition to replace somebody's own
/// with, and the one they did ask for is one photo away.
@immutable
class LabelRequestIntent {
  const LabelRequestIntent({required this.nutrition, required this.package});

  /// The permissive intent: nutrition is allowed because nothing said it is
  /// not. What a read with no roles at all means.
  static const LabelRequestIntent unknown = LabelRequestIntent(
    nutrition: true,
    package: true,
  );

  /// The intent of a request carrying [roles], one per image.
  ///
  /// Anything unrecognised, or an empty set, falls back to [unknown] rather
  /// than to a gate — and so does the server, on the same reasoning rather
  /// than as a second line of defence behind this one.
  ///
  /// Failing open is deliberate. The cost of the gate misfiring is a panel
  /// somebody photographed being thrown away; the requests it cannot
  /// classify are the legacy ones, which never expressed a package-only
  /// purpose to begin with and read panels perfectly well before any of this
  /// existed.
  factory LabelRequestIntent.ofRoles(Iterable<String?> roles) {
    final List<String?> all = roles.toList(growable: false);
    if (all.isEmpty || all.any((String? r) => !LabelPhotoRole.isKnown(r))) {
      return unknown;
    }
    return LabelRequestIntent(
      nutrition: all.contains(LabelPhotoRole.nutrition),
      package: all.contains(LabelPhotoRole.package),
    );
  }

  final bool nutrition;
  final bool package;

  /// A front-of-package read: no panel was sent, so no panel was read.
  bool get isPackageOnly => package && !nutrition;
}

/// [reading], narrowed to what the request it answers could possibly have
/// seen (spec R11).
///
/// Applied by the controller and by the adapter both, because they guard
/// different things: the controller covers any reader at all, including a
/// stub and a server too old to know about roles; the adapter covers a caller
/// that reaches past the controller. Applying it twice is harmless — the
/// second pass has nothing left to remove.
LabelReading gateLabelReadingToRequest(
  LabelReading reading,
  LabelRequestIntent intent,
) {
  if (!intent.isPackageOnly || reading.servings.isEmpty) return reading;
  final LabelReading gated = reading.withoutPanelNutrition();
  // Everything that reply had to say was nutrition nobody asked for, so once
  // it is gone there is nothing left to merge at all. Saying so beats the
  // sheet closing on a draft that did not change, with only a snackbar to
  // explain it: the controller keeps both photos through a failure, so
  // trying again is one tap rather than another trip to the cupboard.
  if (gated.isEmpty) {
    throw const RecipeAiException(
      'No package size came off that photo. Try again with the net weight '
      'filling the frame, or add the nutrition panel photo too.',
    );
  }
  return gated;
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
