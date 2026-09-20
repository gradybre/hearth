import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../data/adapters/label_reader.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/package_nutrition.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/parsing/pack_size.dart';
import '../../domain/shopping/walmart_product.dart';
import '../../domain/units/mass_display_mode.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';

/// Re-exported: this is where the food editor's callers have always found
/// it, and it now lives in the domain so the nutrition adapters can read the
/// same shape out of Open Food Facts.
export '../../domain/parsing/pack_size.dart';

/// Marks a `copyWith` parameter as "not passed", distinct from an explicit
/// `null` -- needed for the two nullable package/nutrition fields, where
/// "clear this" and "leave it alone" are different requests (spec R10, R13).
const Object _unset = Object();

Map<String, Object?>? _quantityToJsonOrNull(Quantity? q) => q == null
    ? null
    : <String, Object?>{
        'canonical_amount': q.canonicalAmount,
        'kind': q.kind.name,
        'unit': q.preferredUnit?.id,
      };

Quantity? _quantityFromJsonMap(Object? value) {
  if (value is! Map) return null;
  final Object? amountRaw = value['canonical_amount'];
  if (amountRaw is! num) return null;
  final UnitKind? kind = UnitKind.values.firstWhereOrNull(
    (UnitKind k) => k.name == value['kind'],
  );
  if (kind == null) return null;
  final Object? unitRaw = value['unit'];
  final Unit? unit = unitRaw is String ? Units.byId(unitRaw) : null;
  return Quantity.canonical(
    canonicalAmount: amountRaw.toDouble(),
    kind: kind,
    preferredUnit: unit,
  );
}

/// One serving row being edited.
@immutable
class ServingDraft {
  const ServingDraft({
    this.amount = '',
    this.unitId = 'g',
    this.kcal = '',
    this.protein = '',
    this.carbs = '',
    this.fat = '',
    this.fiber = '',
    this.sodium = '',
    this.cholesterol = '',
    this.sourceAmount,
    this.sourceAmountText,
    this.id,
  });

  final String amount;
  final String unitId;
  final String kcal;
  final String protein;
  final String carbs;
  final String fat;

  /// The three minor nutrients (spec §5.6). **Empty means unknown**, which is
  /// what an empty field already means to anyone looking at it — and it is
  /// how someone says "I do not know" as distinct from typing a 0 to say the
  /// food genuinely has none. The four above have no such distinction: they
  /// default to zero, because a food with no calories entered is being
  /// described as having none.
  final String fiber;
  final String sodium;
  final String cholesterol;

  /// Set when editing an existing serving, so a save updates it in place.
  final String? id;

  /// The exact quantity this row was loaded with, and the text that stood
  /// for it (spec R6). An untouched amount is saved back as [sourceAmount]
  /// rather than as a reparse of a formatted string, so 15.25 oz or 1/3 cup
  /// come back exactly as stored -- and a package relationship anchored to
  /// this row is not made stale by a rewrite nobody asked for.
  final Quantity? sourceAmount;
  final String? sourceAmountText;

  Unit get unit => Units.byId(unitId) ?? Units.gram;

  /// What a save should store: the original quantity while the field is
  /// untouched, a freshly parsed one once it has been edited.
  Quantity? get resolvedAmount {
    if (sourceAmount != null && amount == (sourceAmountText ?? '')) {
      return sourceAmount;
    }
    final double? value = amountValue;
    return value == null ? null : Quantity.of(value, unit);
  }

  /// Reads fractions as well as decimals: a measuring cup is marked ⅔, and
  /// a serving typed as "2/3" has to come back as a number rather than as
  /// nothing at all.
  double? get amountValue => parseAmount(amount);

  /// A serving is worth saving once it has a positive amount. Macros default
  /// to zero rather than blocking: a food with a known portion and unknown
  /// calories is still more useful than no food at all (spec §5.3's
  /// flag-never-block principle).
  bool get isUsable => (amountValue ?? 0) > 0;

  /// The row [FoodDraft.blank] opens with, still exactly as it opened.
  ///
  /// Not the same as [isBlank]: this one has "100" in it, which is a default
  /// rather than an answer. Anything typed into it — a macro, a different
  /// amount, another unit — makes it the user's and it is kept.
  /// A row that states a portion and nothing about what is in it.
  ///
  /// Not the same as [isUntouchedStarter], which is only ever Hearth's own
  /// opening row. This is what a source hands over when it knows the packet
  /// exists and nothing else — a real amount with four zeroes after it.
  bool get hasNoMacros => macros.isZero;

  bool get isUntouchedStarter =>
      id == null &&
      amount == '100' &&
      unitId == 'g' &&
      kcal.trim().isEmpty &&
      protein.trim().isEmpty &&
      carbs.trim().isEmpty &&
      fat.trim().isEmpty;

  /// Whether two rows describe the same portion, so one need not be added
  /// twice. Compared on the amount as displayed rather than as a double: a
  /// row typed "1/4" and one read as 0.25 are the same cup of cheese.
  bool isSamePortionAs(ServingDraft other) {
    if (unitId != other.unitId) return false;
    final double? mine = amountValue;
    final double? theirs = other.amountValue;
    if (mine == null || theirs == null) return false;
    return (mine - theirs).abs() < 1e-6;
  }

  bool get isBlank =>
      amount.trim().isEmpty &&
      kcal.trim().isEmpty &&
      protein.trim().isEmpty &&
      carbs.trim().isEmpty &&
      fat.trim().isEmpty;

  /// One field's number, or null for a field nobody filled in.
  ///
  /// **`parseAmount`, not `double.tryParse`** — and that is the whole of R02.
  /// These fields are written by `writeAmount`, which renders friendly
  /// fractions because that is what a person types into a measuring field:
  /// half a gram goes in as "1/2". `double.tryParse` cannot read its partner's
  /// output, so every value the fraction table can express came back as
  /// nothing at all — and the two ways that landed were both silent and
  /// neither looked wrong on screen. A major macro fell through `?? 0` and
  /// became a stated **zero**; a minor became **null**, a fact the food really
  /// did state demoted to "nobody said", which is the one distinction §5.6
  /// rests on. `parseAmount` is `writeAmount`'s documented inverse and reads
  /// fractions, mixed numbers and a leading sign.
  ///
  /// Non-finite is refused rather than carried: `parseAmount` will not produce
  /// one, but a paste could, and NaN in a nutrient poisons every total it
  /// reaches.
  static double? _field(String raw) {
    final double? value = parseAmount(raw);
    if (value == null || !value.isFinite) return null;
    return value;
  }

  Macros get macros => Macros(
    kcal: _field(kcal) ?? 0,
    proteinG: _field(protein) ?? 0,
    carbG: _field(carbs) ?? 0,
    fatG: _field(fat) ?? 0,
    // No `?? 0`: an empty field is a question nobody answered, and there is a
    // difference between a food with no fibre and a food nobody asked.
    fiberG: _field(fiber),
    sodiumMg: _field(sodium),
    cholesterolMg: _field(cholesterol),
  );

  /// Fields holding something that is not a number.
  ///
  /// Blank is not one of these — blank is a legitimate answer, and for the
  /// minor three it is the *only* way to say "unknown". This is for text that
  /// was typed and cannot be read, which would otherwise land as a silent zero
  /// on a major macro or a silent gap on a minor one.
  /// A number that has been started but not finished.
  static final RegExp _partial = RegExp(r'^[-−+]?\.?$');

  Iterable<String> get unreadableFields sync* {
    for (final (String name, String raw) in <(String, String)>[
      // "kcal" is what the field is labelled, so it is what the complaint
      // names — "the calories is not a number" sent people looking for a
      // field that is not on the screen.
      ('kcal', kcal),
      ('protein', protein),
      ('carbs', carbs),
      ('fat', fat),
      ('fibre', fiber),
      ('sodium', sodium),
      ('cholesterol', cholesterol),
    ]) {
      final String text = raw.trim();
      // A lone sign or a bare point is a number half-typed, not a mistake.
      // Complaining at the first keystroke of "-180" or ".5" would put a red
      // line under somebody mid-word.
      if (text.isEmpty || _partial.hasMatch(text)) continue;
      if (_field(raw) == null) yield name;
    }
  }

  /// How the portion reads in a picker: "100 g", "1 item".
  String get label {
    final double? value = amountValue;
    if (value == null) return unit.label;
    final String number = value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
    return unit.label.isEmpty ? number : '$number ${unit.label}';
  }

  ServingDraft copyWith({
    String? amount,
    String? unitId,
    String? kcal,
    String? protein,
    String? carbs,
    String? fat,
    String? fiber,
    String? sodium,
    String? cholesterol,
    String? id,
  }) => ServingDraft(
    amount: amount ?? this.amount,
    unitId: unitId ?? this.unitId,
    kcal: kcal ?? this.kcal,
    protein: protein ?? this.protein,
    carbs: carbs ?? this.carbs,
    fat: fat ?? this.fat,
    fiber: fiber ?? this.fiber,
    sodium: sodium ?? this.sodium,
    cholesterol: cholesterol ?? this.cholesterol,
    sourceAmount: sourceAmount,
    sourceAmountText: sourceAmountText,
    id: id ?? this.id,
  );

  /// Everything a person can change, for the unsaved-work guard (review F01).
  ///
  /// **Every field of this class belongs in this list.** A field missing from
  /// it is a field the editor will not notice you changed, which means Cancel
  /// throws that change away without asking — the exact defect the guard was
  /// built for, reintroduced quietly one field at a time.
  List<Object?> get _props => <Object?>[
    amount,
    unitId,
    kcal,
    protein,
    carbs,
    fat,
    fiber,
    sodium,
    cholesterol,
    sourceAmountText,
    sourceAmount?.canonicalAmount,
    id,
  ];

  /// For the local draft record (review N01).
  ///
  /// Hand-written, and held honest by the round-trip test: it rebuilds a
  /// serving with every field set to something other than its default and
  /// asserts the result is `==` to what went in. A field in [_props] and not
  /// here fails that test.
  Map<String, Object?> toJson() => <String, Object?>{
    'amount': amount,
    'unit_id': unitId,
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'sodium': sodium,
    'cholesterol': cholesterol,
    'source_amount': _quantityToJsonOrNull(sourceAmount),
    'source_amount_text': sourceAmountText,
    'id': id,
  };

  static ServingDraft fromJson(Map<String, Object?> json) => ServingDraft(
    amount: '${json['amount'] ?? ''}',
    unitId: '${json['unit_id'] ?? ''}',
    kcal: '${json['kcal'] ?? ''}',
    protein: '${json['protein'] ?? ''}',
    carbs: '${json['carbs'] ?? ''}',
    fat: '${json['fat'] ?? ''}',
    fiber: '${json['fiber'] ?? ''}',
    sodium: '${json['sodium'] ?? ''}',
    cholesterol: '${json['cholesterol'] ?? ''}',
    sourceAmount: _quantityFromJsonMap(json['source_amount']),
    sourceAmountText: json['source_amount_text'] as String?,
    id: json['id'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is ServingDraft &&
      const ListEquality<Object?>().equals(other._props, _props);

  @override
  int get hashCode => const ListEquality<Object?>().hash(_props);
}

/// A food being entered by hand (spec §5.5).
///
/// Manual entry is the fallback when a barcode misses — and until Phase 2
/// brings Open Food Facts and USDA, it is the *only* path. §12 names food-data
/// coverage as the biggest threat to the success bar, which makes this screen
/// load-bearing rather than a corner case.
@immutable
class FoodDraft {
  const FoodDraft({
    required this.name,
    required this.servings,
    this.brand = '',
    this.menuGroup = '',
    this.menuOrder,
    this.storeTag = '',
    this.walmartItemId = '',
    this.packSize = '',
    this.barcode = '',
    this.existingId,
    this.source = FoodSource.manual,
    this.isDefault = false,
    this.isZeroCalorie = false,
    this.isModifier = false,
    this.massDisplayMode = MassDisplayMode.automatic,
    this.servingsPerPackage = '',
    this.packageServingId,
    this.packageServingsApproximate = false,
    this.originalPackageNutrition,
    this.packageNutritionReviewed = false,
    this.originalPackSize,
    this.originalPackText,
    this.packageReviewNotes = const <String>[],
    this.packageBasisAcknowledged = false,
    this.packageNutritionSource = PackageNutritionSource.manual,
    this.packageLabelBasis,
    this.packageFieldSources = const <String, String>{},
    this.preservedDensity,
  });

  factory FoodDraft.blank() => FoodDraft(
    name: '',
    // One row to start, in grams: the unit almost every packet is labelled
    // in. Given a stable id immediately rather than only once `toFood`
    // runs -- a package/nutrition relationship (spec R9-R11) linked to this
    // row has to keep pointing at it through every rebuild between now and
    // Save.
    servings: <ServingDraft>[
      ServingDraft(amount: '100', id: const Uuid().v4()),
    ],
  );

  factory FoodDraft.fromFood(Food food) => FoodDraft(
    name: food.name,
    brand: food.brand ?? '',
    menuGroup: food.menuGroup ?? '',
    menuOrder: food.menuOrder,
    storeTag: food.storeTag ?? '',
    walmartItemId: food.walmartItemId ?? '',
    packSize: food.packSize == null
        ? ''
        : QuantityFormat.formatAsAuthored(food.packSize!),
    barcode: food.barcode ?? '',
    existingId: food.id,
    source: food.source,
    isDefault: food.isDefault,
    isZeroCalorie: food.isZeroCalorie,
    isModifier: food.isModifier,
    massDisplayMode: food.massDisplayMode,
    // The source's own stated density, carried through untouched. The editor
    // has no field for it, so without this an ordinary rename dropped a real
    // measured fact on the way back out (spec R12).
    preservedDensity: food.gramsPerMillilitre,
    servingsPerPackage: food.packageNutrition?.servingsPerPackage == null
        ? ''
        : _countText(food.packageNutrition!.servingsPerPackage!),
    packageServingId: food.packageNutrition?.servingOptionId,
    packageServingsApproximate: food.packageNutrition?.isApproximate ?? false,
    originalPackageNutrition: food.packageNutrition,
    packageNutritionReviewed: food.packageNutrition != null,
    originalPackSize: food.packSize,
    originalPackText: food.packSize == null
        ? null
        : QuantityFormat.formatAsAuthored(food.packSize!),
    // The capture evidence a scan left on the record, read back so a
    // reviewed prepared or drained label still says so after a reopen rather
    // than looking like an ordinary as-packaged reading (spec R9, R13).
    packageLabelBasis: _captureBasis(food.packageNutrition),
    packageFieldSources: _captureFieldSources(food.packageNutrition),
    packageBasisAcknowledged: _captureReviewed(food.packageNutrition),
    packageReviewNotes: _captureNotes(food.packageNutrition),
    packageNutritionSource:
        food.packageNutrition?.source ?? PackageNutritionSource.manual,
    servings: <ServingDraft>[
      for (final ServingOption option in food.servingOptions)
        servingFromOption(option),
    ],
  );

  /// A food that came back from a barcode lookup, ready to be reviewed.
  ///
  /// Every id is dropped on the way in. A match from Open Food Facts carries
  /// ids of its own — `off:5000157024671` — which are the *source's* identity,
  /// not this library's; saving one would put a non-uuid where the server
  /// types a uuid, and the row would be rejected on its first sync, long after
  /// the user thought they had saved it. The source and barcode are kept,
  /// because those are what the food actually is.
  /// One editable row from a stored serving, keeping its id and its exact
  /// quantity (spec R6).
  static ServingDraft servingFromOption(ServingOption option) {
    final Unit unit =
        option.amount.preferredUnit ?? Units.canonicalFor(option.amount.kind);
    final String text = writeAmount(option.amount.amountIn(unit));
    return ServingDraft(
      id: option.id,
      amount: text,
      unitId: unit.id,
      sourceAmount: option.amount,
      sourceAmountText: text,
      kcal: _macroText(option.macros.kcal),
      protein: _macroText(option.macros.proteinG),
      carbs: _macroText(option.macros.carbG),
      fat: _macroText(option.macros.fatG),
      // Empty for an unknown, so editing a food Hearth was never told
      // about does not silently record a zero on the way back out.
      fiber: _minorText(option.macros.fiberG),
      sodium: _minorText(option.macros.sodiumMg),
      cholesterol: _minorText(option.macros.cholesterolMg),
    );
  }

  factory FoodDraft.fromLookup(Food food) {
    final FoodDraft mapped = FoodDraft.fromFood(food);

    // Fresh ids, assigned here rather than at save time, so anything that
    // points at a row -- a package relationship above all -- can keep
    // pointing at it through every rebuild.
    final Map<String, String> remapped = <String, String>{};
    final List<ServingDraft> servings = <ServingDraft>[];
    for (final ServingDraft serving in mapped.servings) {
      final String id = const Uuid().v4();
      if (serving.id != null) remapped[serving.id!] = id;
      servings.add(
        serving.copyWith(
          id: id,
          kcal: _rounded(serving.kcal, decimals: 0),
          protein: _rounded(serving.protein),
          carbs: _rounded(serving.carbs),
          fat: _rounded(serving.fat),
          fiber: _rounded(serving.fiber),
          sodium: _rounded(serving.sodium, decimals: 0),
          cholesterol: _rounded(serving.cholesterol, decimals: 0),
        ),
      );
    }

    // A relationship crosses over only when the exact package and serving
    // facts it was reviewed against survived the copy, with the one id it
    // names remapped (spec R13). Anything else -- an unknown record version
    // included -- is left behind inactive rather than re-pointed at a
    // serving it was never measured against.
    final PackageNutrition? relation = food.packageNutrition;
    PackageNutrition? carried;
    if (relation != null &&
        relation.isValid &&
        food.activePackageServing != null &&
        remapped[relation.servingOptionId] != null) {
      final PackageNutrition base = PackageNutrition.manual(
        servingsPerPackage: relation.servingsPerPackage!,
        servingOptionId: remapped[relation.servingOptionId]!,
        servingAmount: relation.servingAmount!,
        packageAmount: relation.packageAmount!,
        isApproximate: relation.isApproximate,
        source: relation.source ?? PackageNutritionSource.manual,
      );
      // The capture evidence travels with the exact basis it describes: a
      // copy that kept the numbers but lost what the label actually said
      // would read as verified when nobody had verified it.
      final Object? capture = relation.rawJson['capture'];
      final PackageNutrition withCapture = capture is Map
          ? PackageNutrition.fromJson(<String, dynamic>{
              ...base.toJson(),
              'capture': capture,
            })
          : base;
      carried = withCapture.isValid ? withCapture : base;
    }

    return FoodDraft(
      name: mapped.name,
      brand: mapped.brand,
      menuGroup: mapped.menuGroup,
      storeTag: mapped.storeTag,
      barcode: mapped.barcode,
      source: food.source,
      isDefault: mapped.isDefault,
      isZeroCalorie: mapped.isZeroCalorie,
      isModifier: mapped.isModifier,
      // Carried through a lookup match: a display preference and a package
      // size the household already has are not things a fresh scan should
      // reset (spec R4, R8).
      massDisplayMode: food.massDisplayMode,
      packSize: mapped.packSize,
      originalPackSize: food.packSize,
      originalPackText: mapped.packSize.isEmpty ? null : mapped.packSize,
      preservedDensity: food.gramsPerMillilitre,
      servingsPerPackage: carried == null
          ? ''
          : _countText(carried.servingsPerPackage!),
      packageServingId: carried?.servingOptionId,
      packageServingsApproximate: carried?.isApproximate ?? false,
      originalPackageNutrition: carried,
      packageNutritionReviewed: carried != null,
      packageLabelBasis: _captureBasis(carried),
      packageFieldSources: _captureFieldSources(carried),
      packageBasisAcknowledged: _captureReviewed(carried),
      packageReviewNotes: _captureNotes(carried),
      packageNutritionSource: carried?.source ?? PackageNutritionSource.manual,
      servings: servings,
    );
  }

  /// Trims the precision a source's own arithmetic produced.
  ///
  /// A source quotes per 100 g and scales to its serving, so 207 g of beans
  /// arrives as 9.729 g of protein. The extra digits are a division, not a
  /// measurement, and this is a screen the user is being asked to *check* —
  /// numbers that look measured invite trust they have not earned. Rounding
  /// here and not in [fromFood] is deliberate: a food already in the library
  /// must reopen exactly as it was stored, or saving it again would quietly
  /// edit macros nobody touched.
  static String _rounded(String value, {int decimals = 1}) {
    // `parseAmount` and `_plain`, matching the fields this feeds. With
    // `double.tryParse` on the way in it silently no-opped on exactly the
    // values it exists for — a scanned 0.75 g arrived as "3/4", failed to
    // parse, and came back unrounded — and with `writeAmount` on the way out
    // it put a fraction into a field whose keyboard has no "/".
    final double? parsed = parseAmount(value);
    if (parsed == null || !parsed.isFinite) return value;
    return _plain(double.parse(parsed.toStringAsFixed(decimals)));
  }

  /// A food nobody had, carrying only the number that was scanned, so the next
  /// scan of the same packet finds it (spec §5.5).
  factory FoodDraft.forBarcode(String barcode) => FoodDraft(
    name: '',
    barcode: barcode,
    // A stable id from the moment the row exists, like every other path.
    servings: <ServingDraft>[
      ServingDraft(amount: '100', id: const Uuid().v4()),
    ],
  );

  /// This draft with everything a photographed label said, merged in
  /// (spec §5.5).
  ///
  /// Three rules, and each one is a way this could quietly lose the user's
  /// work:
  ///
  ///  * **Name and brand fill blanks only.** A photo is evidence, not an
  ///    authority; typing a name and having a picture overwrite it is the
  ///    worst kind of helpful.
  ///  * **Servings are appended, never replacing what is there.** The case
  ///    this exists for is a food that already has grams and needs a cup, so
  ///    dropping the grams to add the cup would be exactly backwards. A row
  ///    the draft already has — same unit, same amount — is skipped rather
  ///    than duplicated.
  ///  * **An untouched starter row is replaced.** [blank] opens on 100 g with
  ///    no macros; leaving it above two rows read off a packet is junk for
  ///    someone else to delete.
  ///
  /// Numbers are rounded the way [fromLookup] rounds them, and for the same
  /// reason: this lands on a screen the user is being asked to *check*, and
  /// digits that look measured invite trust they have not earned.
  FoodDraft withLabel(LabelReading reading) {
    if (reading.isEmpty) return this;
    // A row with a portion and no macros is a gap, not an answer — unless the
    // household has said this food really is zero, which is the one case where
    // four zeroes are the measurement. Only ever dropped when the label has
    // something to put in its place.
    final bool replaceEmptyRows = !isZeroCalorie && reading.servings.isNotEmpty;

    final List<ServingDraft> kept = <ServingDraft>[
      for (final ServingDraft serving in servings)
        if (reading.servings.isEmpty || !serving.isUntouchedStarter)
          if (!replaceEmptyRows || !serving.hasNoMacros) serving,
    ];

    final List<ServingDraft> added = <ServingDraft>[];
    for (final LabelServing read in reading.servings) {
      final ServingDraft candidate = ServingDraft(
        // A row read from a photo needs a stable id of its own the moment it
        // exists, not one invented later by `toFood`: a package/nutrition
        // relationship the user links to this row (spec R9–R11) has to keep
        // pointing at it through every rebuild between now and Save.
        id: const Uuid().v4(),
        amount: writeAmount(read.amount),
        unitId: read.unitId,
        kcal: _rounded('${read.kcal}', decimals: 0),
        protein: _rounded('${read.proteinG}'),
        carbs: _rounded('${read.carbG}'),
        fat: _rounded('${read.fatG}'),
        // Empty where the panel said nothing, which is the same sentence the
        // field itself makes when it is left blank (spec §5.6).
        fiber: read.fiberG == null ? '' : _rounded('${read.fiberG}'),
        sodium: read.sodiumMg == null
            ? ''
            : _rounded('${read.sodiumMg}', decimals: 0),
        cholesterol: read.cholesterolMg == null
            ? ''
            : _rounded('${read.cholesterolMg}', decimals: 0),
      );
      final bool alreadyHere = <ServingDraft>[
        ...kept,
        ...added,
      ].any((ServingDraft existing) => existing.isSamePortionAs(candidate));
      if (!alreadyHere) added.add(candidate);
    }

    // The front-of-pack net amount (spec R11) fills the package-size field
    // only when nobody has already typed one — a photo is evidence, not an
    // authority, the same rule this method already applies to name and brand.
    final bool tookPhotoPack =
        packSize.trim().isEmpty && reading.packageSize != null;
    final String mergedPackSize = tookPhotoPack
        ? QuantityFormat.formatAsAuthored(reading.packageSize!)
        : packSize;
    // The photo's own canonical amount is kept beside its text, so a pack
    // read as 14.5 oz stays 14.5 oz rather than becoming a reparse of the
    // string it happened to be formatted into (spec R6).
    final Quantity? mergedOriginalPack = tookPhotoPack
        ? reading.packageSize
        : originalPackSize;
    final String? mergedOriginalPackText = tookPhotoPack
        ? mergedPackSize
        : originalPackText;

    // Same rule for the servings-per-package count read off the back panel.
    final bool countAlreadyEntered = servingsPerPackage.trim().isNotEmpty;
    final String mergedServingsPerPackage =
        !countAlreadyEntered && reading.servingsPerContainer != null
        ? _countText(reading.servingsPerContainer!)
        : servingsPerPackage;
    final bool mergedApproximate = countAlreadyEntered
        ? packageServingsApproximate
        : reading.servingsApproximate;

    final List<String> notes = <String>[
      ...packageReviewNotes,
      for (final issue in reading.uncertain) '${issue.field}: ${issue.note}',
    ];
    if (packSize.trim().isNotEmpty &&
        reading.packageSize != null &&
        resolvedPackSize != reading.packageSize) {
      notes.add(
        'The photo suggests a package of '
        '${QuantityFormat.formatAsAuthored(reading.packageSize!)}. '
        'Your entered package amount has been kept.',
      );
    }
    // Whether *this* read needs the preparation question answered, judged on
    // the reading itself rather than on the accumulated notes: an old note
    // from an earlier scan must not re-ask a question already answered, and a
    // new unsafe scan must clear an answer given about different photos.
    final bool scanNeedsBasisReview =
        reading.packageBasis != 'as_packaged' &&
        (reading.packageSize != null || reading.servingsPerContainer != null);
    if (scanNeedsBasisReview) {
      notes.add(
        'The label describes a "${reading.packageBasis}" amount, which needs '
        'manual confirmation before it can be used to convert between '
        'weight and servings.',
      );
    }
    if (countAlreadyEntered &&
        reading.servingsPerContainer != null &&
        (parseAmount(servingsPerPackage) ?? -1) !=
            reading.servingsPerContainer) {
      notes.add(
        'The photo suggests ${writeAmount(reading.servingsPerContainer!)} '
        'servings per package, which differs from what is entered. Review '
        'before confirming.',
      );
    }

    // A single new volume row is offered as the likely nutrition serving for
    // a package relationship — never activated, only pre-selected, so the
    // user still has to review and confirm it (spec R10).
    String? suggestedServingId = packageServingId;
    if (suggestedServingId == null && !packageNutritionReviewed) {
      final List<ServingDraft> volumeAdded = <ServingDraft>[...kept, ...added]
          .where(
            (ServingDraft s) => Units.byId(s.unitId)?.kind == UnitKind.volume,
          )
          .toList(growable: false);
      if (volumeAdded.length == 1 &&
          (reading.packageSize != null ||
              reading.servingsPerContainer != null)) {
        suggestedServingId = volumeAdded.single.id;
      }
    }

    return FoodDraft(
      name: name.trim().isEmpty ? (reading.name ?? '') : name,
      brand: brand.trim().isEmpty ? (reading.brand ?? '') : brand,
      menuGroup: menuGroup,
      menuOrder: menuOrder,
      storeTag: storeTag,
      walmartItemId: walmartItemId,
      packSize: mergedPackSize,
      barcode: barcode,
      existingId: existingId,
      source: source,
      isDefault: isDefault,
      isZeroCalorie: isZeroCalorie,
      isModifier: isModifier,
      massDisplayMode: massDisplayMode,
      servingsPerPackage: mergedServingsPerPackage,
      packageServingId: suggestedServingId,
      packageServingsApproximate: mergedApproximate,
      originalPackageNutrition: originalPackageNutrition,
      packageNutritionReviewed: packageNutritionReviewed,
      originalPackSize: mergedOriginalPack,
      originalPackText: mergedOriginalPackText,
      packageReviewNotes: _boundedNotes(notes),
      // What this label actually said, kept for correction later. A scan that
      // supplied no package facts leaves whatever was already recorded.
      packageFieldSources: {...packageFieldSources, ...reading.fieldSources},
      packageLabelBasis:
          reading.packageSize != null || reading.servingsPerContainer != null
          ? reading.packageBasis
          : packageLabelBasis,
      preservedDensity: preservedDensity,
      // A fresh unsafe scan never inherits an earlier acknowledgement: a
      // basis warning on these photos has to be answered for these photos.
      packageBasisAcknowledged: scanNeedsBasisReview
          ? false
          : packageBasisAcknowledged,
      // Facts a photo supplied are recorded as having come from one. A second
      // slot read into a draft whose facts already came from photos is still
      // photos; only facts a person typed make it mixed (spec R13).
      packageNutritionSource: _sourceAfterPhotos(
        photoSuppliedFacts:
            tookPhotoPack || mergedServingsPerPackage != servingsPerPackage,
        hadPriorFacts: countAlreadyEntered || packSize.trim().isNotEmpty,
      ),
      servings: <ServingDraft>[...kept, ...added],
    );
  }

  final String name;
  final String brand;

  /// The section of a restaurant menu this sits in (spec §5.2). Empty for
  /// anything not off a menu, and for a menu item nobody sectioned.
  final String menuGroup;

  /// Its place on the sheet, carried through an edit untouched. Set by the
  /// menu importer, which is the only thing that knows what the sheet said.
  final int? menuOrder;
  final String storeTag;

  /// A pasted Walmart link or item id, and how much is in one pack — both
  /// free text until [toFood] turns them into something storable.
  final String walmartItemId;
  final String packSize;
  final String barcode;
  final List<ServingDraft> servings;
  final String? existingId;
  final FoodSource source;

  /// One of the household's standing choices (spec §5.3).
  final bool isDefault;

  /// Confirmed to carry no macros, rather than missing them (spec §5.5).
  final bool isZeroCalorie;

  /// A menu row published as a deduction (spec §5.2), which is what permits
  /// the negative macros the editor would otherwise refuse.
  final bool isModifier;

  /// How an imperial mass quantity for this food should display (spec R3–R4).
  final MassDisplayMode massDisplayMode;

  /// The editable "servings per package" field for a proposed package/
  /// nutrition relationship (spec R9–R10). Free text, like every other
  /// numeric field here, until [confirmPackageNutrition] turns it into a
  /// saved [PackageNutrition].
  final String servingsPerPackage;

  /// The id of the [ServingDraft] currently proposed as the nutrition anchor
  /// for a package relationship. A photo can suggest one; only
  /// [confirmPackageNutrition] activates it.
  final String? packageServingId;

  /// Whether the servings-per-package count is a printed "about" figure
  /// (spec R10), carried through to the confirmed relationship.
  final bool packageServingsApproximate;

  /// The last *confirmed* package/nutrition relationship — loaded from an
  /// existing food, or produced by [confirmPackageNutrition]. This is what
  /// [toFood] writes out; the editable fields above never reach a saved food
  /// on their own, so an unrelated edit can never silently activate or lose
  /// it (spec R10, R13).
  final PackageNutrition? originalPackageNutrition;

  /// True once [originalPackageNutrition] reflects an explicit confirm
  /// action rather than only whatever was loaded from an existing food.
  final bool packageNutritionReviewed;

  /// The exact package-size quantity this draft was opened with, kept
  /// alongside [originalPackText] so an untouched pack-size field can be
  /// saved back with its original canonical value rather than a reparse
  /// (spec R6).
  final Quantity? originalPackSize;

  /// The package-size field's text at the moment this draft was opened.
  final String? originalPackText;

  /// Notes surfaced by [withLabel] when a photo's package/nutrition facts
  /// need explicit review — a basis other than "as packaged", or a count
  /// that conflicts with what was already entered (spec R10–R11).
  final List<String> packageReviewNotes;

  /// Explicit acknowledgement that the package and the selected nutrition
  /// serving describe the same preparation, required before
  /// [confirmPackageNutrition] will activate a relationship flagged by
  /// [packageReviewNotes] (spec R9).
  final bool packageBasisAcknowledged;

  /// Where the package/nutrition facts on this draft came from (spec R13),
  /// carried through every copy so a confirmed record states the real
  /// provenance rather than one guessed at the moment it was saved.
  final PackageNutritionSource packageNutritionSource;

  /// What a photographed label actually said its amount was measured on --
  /// 'as_packaged', 'prepared', 'drained', or 'unknown' (spec R9, R11).
  ///
  /// Kept beside the relationship rather than folded into it. A person may
  /// legitimately correct a misread panel and confirm that the package and
  /// the serving describe the same contents, but the original reading and
  /// the notes that prompted the question have to survive that confirmation,
  /// or a reopened food shows a clean relation with nothing left to correct
  /// it from. Null when nothing was scanned.
  final String? packageLabelBasis;
  final Map<String, String> packageFieldSources;

  /// The density the food's own source stated, carried through the editor
  /// untouched.
  ///
  /// There is no field for it on the screen, so without this an ordinary
  /// rename dropped a measured fact on the way back out -- and a package
  /// relationship then answered a question the food had already answered
  /// better (spec R12).
  final double? preservedDensity;

  /// [preservedDensity] when it is a figure something can be divided by.
  double? get usablePreservedDensity =>
      preservedDensity != null &&
          preservedDensity!.isFinite &&
          preservedDensity! > 0
      ? preservedDensity
      : null;

  static const int _noteLimit = 6;
  static const int _noteLength = 200;

  /// Notes, de-duplicated and bounded.
  ///
  /// Repeated reads used to stack the same sentence, and these travel inside
  /// the saved record, which has a 4 KiB cap (spec R13) -- an unbounded list
  /// would eventually refuse the whole relationship rather than one note.
  static List<String> _boundedNotes(List<String> notes) {
    final List<String> kept = <String>[];
    for (final String note in notes) {
      final String trimmed = note.trim();
      if (trimmed.isEmpty) continue;
      // Bound encoded bytes, including escapes, without splitting a Unicode
      // character. Six notes leave room for the relation and capture facts.
      String bounded = '';
      for (final int rune in trimmed.runes.take(_noteLength)) {
        final String next = bounded + String.fromCharCode(rune);
        if (utf8.encode(jsonEncode(next)).length > 256) break;
        bounded = next;
      }
      if (kept.contains(bounded)) continue;
      kept.add(bounded);
      if (kept.length == _noteLimit) break;
    }
    return List<String>.unmodifiable(kept);
  }

  /// The optional capture evidence carried inside a version-1 record.
  static Map<String, dynamic>? _capture(PackageNutrition? relation) {
    final Object? capture = relation?.rawJson['capture'];
    return capture is Map ? capture.cast<String, dynamic>() : null;
  }

  static String? _captureBasis(PackageNutrition? relation) {
    final Object? basis = _capture(relation)?['basis'];
    return basis is String ? basis : null;
  }

  static Map<String, String> _captureFieldSources(PackageNutrition? relation) =>
      _sourcesFrom(_capture(relation)?['field_sources']);
  static Map<String, String> _sourcesFrom(Object? raw) => raw is Map
      ? {
          for (final entry in raw.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        }
      : const {};

  static bool _captureReviewed(PackageNutrition? relation) =>
      _capture(relation)?['reviewed_same_basis'] == true;

  static List<String> _captureNotes(PackageNutrition? relation) {
    final Object? notes = _capture(relation)?['notes'];
    if (notes is! List) return const <String>[];
    return _boundedNotes(<String>[
      for (final Object? note in notes)
        if (note is String) note,
    ]);
  }

  /// A servings count as field text that parses back to exactly the number
  /// it came from.
  ///
  /// Deliberately not `writeAmount`: that renders a kitchen fraction, and a
  /// stored 1.23456789 rounded into one reopened as a *different* count --
  /// which then read as a pending change and stood between somebody and an
  /// unrelated save.
  static String _countText(double value) =>
      value == value.roundToDouble() && value.abs() < 1e15
      ? value.toInt().toString()
      : value.toString();

  /// Provenance after a photo supplied one of these facts.
  PackageNutritionSource _sourceAfterPhotos({
    required bool photoSuppliedFacts,
    required bool hadPriorFacts,
  }) {
    if (!photoSuppliedFacts) return packageNutritionSource;
    if (!hadPriorFacts) return PackageNutritionSource.photos;
    return packageNutritionSource == PackageNutritionSource.photos
        ? PackageNutritionSource.photos
        : PackageNutritionSource.mixed;
  }

  /// Provenance after a person edited a package or serving fact by hand.
  PackageNutritionSource _sourceAfterEdit(
    String nextPackSize,
    List<ServingDraft> nextServings,
  ) {
    if (packageNutritionSource == PackageNutritionSource.manual) {
      return PackageNutritionSource.manual;
    }
    final bool touched =
        nextPackSize != packSize ||
        !const ListEquality<ServingDraft>().equals(nextServings, servings);
    return touched ? PackageNutritionSource.mixed : packageNutritionSource;
  }

  bool get isEditing => existingId != null;

  String? get nameError => name.trim().isEmpty ? 'A food needs a name.' : null;

  String? get servingsError =>
      usableServings.isEmpty ? 'Add at least one serving size.' : null;

  /// Why a negative was refused, or null.
  ///
  /// The hosted database refuses one outright — `check (kcal >= 0 or
  /// is_modifier)` — and nothing local does, so without this the save would
  /// succeed, sit in the queue, and fail silently on the way up. Better to say
  /// so on the screen where the number was typed (§5.2).
  String? get macrosError {
    // Before the sign check, because a field nobody can read has no sign to
    // judge. Named rather than counted: "check the numbers" makes somebody
    // re-read all seven.
    final List<String> unreadable = <String>[
      for (final ServingDraft serving in usableServings)
        ...serving.unreadableFields,
    ];
    if (unreadable.isNotEmpty) {
      final Set<String> named = unreadable.toSet();
      return named.length == 1
          ? 'The ${named.single} is not a number Hearth can read.'
          : 'These are not numbers Hearth can read: ${named.join(', ')}.';
    }

    if (isModifier) return null;
    final bool anyNegative = usableServings.any(
      (ServingDraft s) =>
          s.macros.kcal < 0 ||
          s.macros.proteinG < 0 ||
          s.macros.carbG < 0 ||
          s.macros.fatG < 0 ||
          (s.macros.fiberG ?? 0) < 0 ||
          (s.macros.sodiumMg ?? 0) < 0 ||
          (s.macros.cholesterolMg ?? 0) < 0,
    );
    if (!anyNegative) return null;
    return source == FoodSource.restaurant
        ? 'Only a deduction can be negative. Turn on "takes away rather '
              'than adds".'
        : 'A food cannot have a negative amount.';
  }

  /// Whether the food itself can be saved.
  ///
  /// Deliberately silent about the package/nutrition fields: they are
  /// optional, and a half-finished one must never stand between somebody
  /// and saving the food (spec R10). What an incomplete entry does is show
  /// its explanation and stay unconfirmed, so nothing is silently
  /// activated; what a *complete but unconfirmed change* does is ask for
  /// the inline confirm -- see [packageNutritionNeedsConfirmation].
  bool get isValid =>
      nameError == null && servingsError == null && macrosError == null;

  /// Whether this draft has servings and none of them carry a macro.
  ///
  /// The state where "is that zero, or is it missing?" is a real question —
  /// and the only state where asking it is worth the room.
  bool get looksZeroCalorie =>
      usableServings.isNotEmpty &&
      usableServings.every((ServingDraft s) => s.macros.isZero);

  List<ServingDraft> get usableServings =>
      servings.where((ServingDraft s) => s.isUsable).toList(growable: false);

  /// A serving row currently proposed as the nutrition anchor for a package
  /// relationship, if [packageServingId] still names one that exists.
  Quantity? get resolvedPackSize =>
      originalPackSize != null && packSize == originalPackText
      ? originalPackSize
      : parsePackSize(packSize);

  ServingDraft? get _selectedPackageServing => packageServingId == null
      ? null
      : servings.firstWhereOrNull((ServingDraft s) => s.id == packageServingId);

  /// Why the package/nutrition fields on this draft cannot yet be confirmed,
  /// or null when they are ready for [confirmPackageNutrition] (spec
  /// R9–R10). Silent while nobody has touched the section.
  String? get packageNutritionError {
    final bool anyEntered =
        servingsPerPackage.trim().isNotEmpty || packageServingId != null;
    if (!anyEntered) return null;

    final bool hasBasisWarning = packageReviewNotes.any(
      (String n) => n.contains('needs manual confirmation'),
    );
    if (hasBasisWarning && !packageBasisAcknowledged) {
      return 'Confirm the package and serving describe the same '
          'preparation before saving this relationship.';
    }

    final double? count = parseAmount(servingsPerPackage);
    if (count == null || !count.isFinite || count <= 0) {
      return 'Servings per package needs a positive number.';
    }
    final Quantity? pack = resolvedPackSize;
    if (pack == null ||
        !pack.canonicalAmount.isFinite ||
        pack.canonicalAmount <= 0 ||
        pack.kind != UnitKind.mass) {
      return 'Package amount needs a weight, like 10 oz.';
    }
    final ServingDraft? serving = _selectedPackageServing;
    if (serving == null) {
      return 'Choose which nutrition serving the package amount converts '
          'to.';
    }
    final double? servingAmount = serving.amountValue;
    if (servingAmount == null ||
        !servingAmount.isFinite ||
        servingAmount <= 0) {
      return 'The selected serving needs a positive amount.';
    }
    if (Units.byId(serving.unitId)?.kind != UnitKind.volume) {
      return 'The selected serving needs to be measured by volume, like '
          'cups.';
    }
    final double total = serving.resolvedAmount!.canonicalAmount * count;
    final double density = pack.canonicalAmount / total;
    if (!total.isFinite || total <= 0 || !density.isFinite || density <= 0) {
      return 'The package or serving count is too large or too small to '
          'convert. Correct the amounts or remove the link.';
    }
    return null;
  }

  /// The live review sentence (spec R10) — "1 package (10 oz) = 2 servings
  /// = 2 cups" — or null while the fields are incomplete or invalid.
  String? get packageNutritionPreview {
    if (servingsPerPackage.trim().isEmpty ||
        packageServingId == null ||
        packageNutritionError != null) {
      return null;
    }
    final double count = parseAmount(servingsPerPackage)!;
    final Quantity pack = resolvedPackSize!;
    final ServingDraft serving = _selectedPackageServing!;
    final double servingAmount = serving.amountValue!;
    final double totalVolume = count * servingAmount;
    // A count large enough to overflow the total states nothing anybody can
    // act on, so it is not previewed as though it did.
    if (!totalVolume.isFinite || totalVolume <= 0) return null;
    final String packText = QuantityFormat.formatAsAuthored(pack);
    final String countText = writeAmount(count);
    final String totalText = QuantityFormat.formatIn(
      Quantity.of(totalVolume, serving.unit),
      serving.unit,
    );
    return '1 package ($packText) = $countText servings = $totalText';
  }

  /// One selected nutrition serving expressed in the package's mass unit.
  String? get packageNutritionUnitPreview {
    if (packageNutritionPreview == null) return null;
    final count = parseAmount(servingsPerPackage)!;
    final serving = _selectedPackageServing?.resolvedAmount;
    if (serving == null) return null;
    return '${QuantityFormat.formatAsAuthored(serving)} = ${QuantityFormat.formatAsAuthored(resolvedPackSize!.scaledBy(1 / count))}';
  }

  /// True once a confirmed relationship no longer describes this draft's
  /// current package amount or the serving it was anchored to (spec R10) —
  /// checked against in-progress edits, ahead of what
  /// `Food.hasStalePackageNutrition` sees once actually saved.
  bool get hasStalePackageNutrition {
    final PackageNutrition? relation = originalPackageNutrition;
    if (relation == null || !relation.isValid) return false;
    final Quantity? pack = resolvedPackSize;
    final ServingDraft? serving = servings.firstWhereOrNull(
      (ServingDraft s) => s.id == relation.servingOptionId,
    );
    if (pack == null || serving == null || serving.amountValue == null) {
      return true;
    }
    return !relation.matches(
      pack: pack,
      servingId: serving.id,
      servingAmount: serving.resolvedAmount,
    );
  }

  /// True once the package/nutrition fields hold anything at all.
  bool get hasEnteredPackageFields =>
      servingsPerPackage.trim().isNotEmpty || packageServingId != null;

  /// True when the entered fields describe a different relationship from
  /// the one last confirmed -- a changed count, a different serving, a
  /// newly qualified 'about' (spec R10).
  ///
  /// Deliberately blind to the package amount. Editing that makes an
  /// existing record *stale*, which is a different thing said differently
  /// by [hasStalePackageNutrition], and it must never stand between
  /// somebody and saving an unrelated edit.
  bool get packageNutritionPendingChange {
    final PackageNutrition? relation = originalPackageNutrition;
    if (relation == null || !relation.isValid) return hasEnteredPackageFields;
    final double? count = parseAmount(servingsPerPackage);
    return count != relation.servingsPerPackage ||
        packageServingId != relation.servingOptionId ||
        packageServingsApproximate != relation.isApproximate;
  }

  /// True when a complete, valid change is waiting on the inline confirm.
  ///
  /// Incomplete or invalid entry never reaches this: the food saves without
  /// the link and the explanation stays on the field. A changed count that
  /// *would* work is the one case worth stopping for, because saving it
  /// silently under the old number is the defect this exists to prevent.
  bool get packageNutritionNeedsConfirmation =>
      packageNutritionPendingChange &&
      hasEnteredPackageFields &&
      packageNutritionError == null;

  /// This draft's own density: the explicit figure its source stated first,
  /// then the one implied by its servings (spec R12).
  double? get ownGramsPerMillilitre =>
      usablePreservedDensity ?? _densityFromServings();

  /// Density implied by this food's own servings, when it states both a
  /// volume and a mass with something to scale between them.
  double? _densityFromServings() {
    final ({double amount, double scale})? volume = _bridge(UnitKind.volume);
    final ({double amount, double scale})? mass = _bridge(UnitKind.mass);
    if (volume == null || mass == null) return null;
    final double grams = mass.amount * (volume.scale / mass.scale);
    final double density = grams / volume.amount;
    return density.isFinite && density > 0 ? density : null;
  }

  ({double amount, double scale})? _bridge(UnitKind kind) {
    for (final ServingDraft serving in usableServings) {
      if (serving.unit.kind != kind) continue;
      final Quantity? amount = serving.resolvedAmount;
      if (amount == null || amount.canonicalAmount <= 0) continue;
      final Macros m = serving.macros;
      final double scale = m.kcal != 0 ? m.kcal : m.proteinG + m.carbG + m.fatG;
      if (scale <= 0) continue;
      return (amount: amount.canonicalAmount, scale: scale);
    }
    return null;
  }

  /// Grams per millilitre the entered package fields imply, or null while
  /// they are incomplete.
  double? get packageGramsPerMillilitre {
    if (packageNutritionError != null || !hasEnteredPackageFields) return null;
    final double? count = parseAmount(servingsPerPackage);
    final Quantity? pack = resolvedPackSize;
    final Quantity? serving = _selectedPackageServing?.resolvedAmount;
    if (count == null || pack == null || serving == null) return null;
    final double volume = serving.canonicalAmount * count;
    if (volume <= 0) return null;
    final double density = pack.canonicalAmount / volume;
    return density.isFinite && density > 0 ? density : null;
  }

  /// A note when the package relationship disagrees with what this food
  /// already says about itself by more than 5% (spec R12).
  ///
  /// Only ever a note. Nothing here changes which figure a conversion
  /// uses: the food's own always wins, and both facts stay as entered.
  String? get packageDensityConflictNote {
    final double? own = ownGramsPerMillilitre;
    final double? fromPackage = packageGramsPerMillilitre;
    if (own == null || fromPackage == null || own == 0) return null;
    if ((fromPackage - own).abs() / own.abs() <= 0.05) return null;
    return 'This package works out to a different weight per serving than '
        "this food's own serving sizes do. Both are kept as entered, and "
        "the food's own sizes are still what nutrition uses.";
  }

  /// Sets one of the package/nutrition fields, recording that a person
  /// typed it: a draft whose facts came off a photo becomes mixed rather
  /// than going on claiming the whole record was read (spec R13).
  FoodDraft withPackageField({
    String? servingsPerPackage,
    Object? packageServingId = _unset,
    bool? packageServingsApproximate,
  }) => copyWith(
    servingsPerPackage: servingsPerPackage,
    packageServingId: packageServingId,
    packageServingsApproximate: packageServingsApproximate,
    packageNutritionSource:
        packageNutritionSource == PackageNutritionSource.manual
        ? PackageNutritionSource.manual
        : PackageNutritionSource.mixed,
  );

  /// Freezes the currently entered package/nutrition fields into a saved
  /// relationship — the explicit confirm action spec R10 requires. A no-op,
  /// returning this draft unchanged, while [packageNutritionError] still
  /// names something wrong.
  FoodDraft confirmPackageNutrition() {
    if (servingsPerPackage.trim().isEmpty ||
        packageServingId == null ||
        packageNutritionError != null) {
      return this;
    }
    final double count = parseAmount(servingsPerPackage)!;
    final Quantity pack = resolvedPackSize!;
    final ServingDraft serving = _selectedPackageServing!;
    final PackageNutrition relation = PackageNutrition.manual(
      servingsPerPackage: count,
      servingOptionId: serving.id!,
      servingAmount: serving.resolvedAmount!,
      packageAmount: pack,
      isApproximate: packageServingsApproximate,
      source: packageNutritionSource,
    );
    if (!relation.isValid) return this;

    // The capture evidence rides along inside the same version-1 record as
    // additive keys (spec R13): what the label actually said, that a person
    // reviewed it and confirmed the package and the serving describe the
    // same contents, and the notes that prompted the question. Without it a
    // corrected prepared or drained panel reopened looking like an ordinary
    // as-packaged reading, with the facts needed to correct it thrown away.
    //
    // The notes are kept rather than cleared for the same reason -- they are
    // the original facts, and R10 asks for those to be preserved for
    // correction -- but bounded and de-duplicated so they stay inside the
    // record's size cap.
    final List<String> notes = _boundedNotes(packageReviewNotes);
    final bool hasEvidence = packageLabelBasis != null || notes.isNotEmpty;
    final PackageNutrition captured = hasEvidence
        ? PackageNutrition.fromJson(<String, dynamic>{
            ...relation.toJson(),
            'capture': <String, dynamic>{
              if (packageLabelBasis != null) 'basis': packageLabelBasis,
              if (packageFieldSources.isNotEmpty)
                'field_sources': packageFieldSources,
              'reviewed_same_basis': packageBasisAcknowledged,
              if (notes.isNotEmpty) 'notes': notes,
            },
          })
        : relation;

    // Do not activate a record by silently dropping its capture evidence.
    if (!captured.isValid) return this;
    return copyWith(
      originalPackageNutrition: captured,
      packageNutritionReviewed: true,
      packageReviewNotes: notes,
    );
  }

  /// Explicitly removes any package/nutrition relationship — reviewed or
  /// stale — from this draft. Nothing else clears it: a source refresh or an
  /// unrelated field edit must never do so on its own (spec R10, R13).
  FoodDraft clearPackageNutrition() => copyWith(
    originalPackageNutrition: null,
    packageNutritionReviewed: false,
    servingsPerPackage: '',
    packageServingId: null,
    packageServingsApproximate: false,
    packageReviewNotes: const <String>[],
    packageBasisAcknowledged: false,
    packageLabelBasis: null,
    packageFieldSources: const {},
    packageNutritionSource: PackageNutritionSource.manual,
  );

  Food toFood({String Function()? idFactory}) {
    final String Function() newId = idFactory ?? const Uuid().v4;
    // An untouched pack-size field is saved back with the exact quantity this
    // draft was opened with, not a reparse of its formatted text -- the same
    // precision rule R6 already applies to every other saved amount here.
    final Quantity? resolvedPackSize =
        originalPackSize != null && packSize == (originalPackText ?? '')
        ? originalPackSize
        : parsePackSize(packSize);
    return Food(
      id: existingId ?? newId(),
      name: name.trim(),
      brand: brand.trim().isEmpty ? null : brand.trim(),
      menuGroup: menuGroup.trim().isEmpty ? null : menuGroup.trim(),
      menuOrder: menuOrder,
      storeTag: storeTag.trim().isEmpty ? null : storeTag.trim(),
      // Stored as the id, never as whatever was pasted: a link that no longer
      // parses is a link nothing can use.
      walmartItemId: WalmartProduct.idFrom(walmartItemId),
      packSize: resolvedPackSize,
      // The source's own stated density, put back exactly as it arrived: the
      // editor cannot change it, so it must not be able to lose it either.
      gramsPerMillilitre: usablePreservedDensity,
      barcode: barcode.trim().isEmpty ? null : barcode.trim(),
      source: source,
      isDefault: isDefault,
      isZeroCalorie: isZeroCalorie,
      isModifier: isModifier,
      massDisplayMode: massDisplayMode,
      // Frozen at the last explicit confirm (spec R10, R13): the editable
      // package/nutrition fields above never reach a saved food on their
      // own, so an edit to an unrelated field can never activate or clear
      // this relationship as a side effect.
      packageNutrition: originalPackageNutrition,
      servingOptions: <ServingOption>[
        for (final ServingDraft serving in usableServings)
          ServingOption(
            id: serving.id ?? newId(),
            label: serving.label,
            // The exact amount this row was loaded with while the field is
            // untouched (spec R6).
            amount: serving.resolvedAmount!,
            macros: serving.macros,
          ),
      ],
    );
  }

  FoodDraft copyWith({
    String? name,
    String? brand,
    String? menuGroup,
    String? storeTag,
    String? walmartItemId,
    String? packSize,
    String? barcode,
    List<ServingDraft>? servings,
    bool? isDefault,
    bool? isZeroCalorie,
    bool? isModifier,

    /// Only the restaurant switch sets this. Everything else keeps the
    /// provenance the food arrived with — a food saved from Open Food Facts
    /// stays Open Food Facts however much of it is edited (spec §5.5).
    FoodSource? source,
    MassDisplayMode? massDisplayMode,
    String? servingsPerPackage,

    /// Pass `null` explicitly to clear the current proposed serving; omit
    /// entirely to leave it as-is.
    Object? packageServingId = _unset,
    bool? packageServingsApproximate,

    /// Pass `null` explicitly to clear the confirmed relationship; omit
    /// entirely to leave it as-is (spec R10, R13).
    Object? originalPackageNutrition = _unset,
    bool? packageNutritionReviewed,
    List<String>? packageReviewNotes,
    bool? packageBasisAcknowledged,

    /// Pass `null` explicitly to forget what a label said; omit entirely to
    /// leave it as-is.
    Object? packageLabelBasis = _unset,
    Map<String, String>? packageFieldSources,
    double? preservedDensity,
    PackageNutritionSource? packageNutritionSource,
  }) => FoodDraft(
    name: name ?? this.name,
    brand: brand ?? this.brand,
    menuGroup: menuGroup ?? this.menuGroup,
    menuOrder: menuOrder,
    storeTag: storeTag ?? this.storeTag,
    walmartItemId: walmartItemId ?? this.walmartItemId,
    packSize: packSize ?? this.packSize,
    barcode: barcode ?? this.barcode,
    servings: servings ?? this.servings,
    existingId: existingId,
    source: source ?? this.source,
    isDefault: isDefault ?? this.isDefault,
    isZeroCalorie: isZeroCalorie ?? this.isZeroCalorie,
    isModifier: isModifier ?? this.isModifier,
    massDisplayMode: massDisplayMode ?? this.massDisplayMode,
    servingsPerPackage: servingsPerPackage ?? this.servingsPerPackage,
    packageServingId: identical(packageServingId, _unset)
        ? this.packageServingId
        : packageServingId as String?,
    packageServingsApproximate:
        packageServingsApproximate ?? this.packageServingsApproximate,
    originalPackageNutrition: identical(originalPackageNutrition, _unset)
        ? this.originalPackageNutrition
        : originalPackageNutrition as PackageNutrition?,
    packageNutritionReviewed:
        packageNutritionReviewed ?? this.packageNutritionReviewed,
    originalPackSize: originalPackSize,
    originalPackText: originalPackText,
    packageReviewNotes: packageReviewNotes ?? this.packageReviewNotes,
    packageBasisAcknowledged:
        packageBasisAcknowledged ?? this.packageBasisAcknowledged,
    packageFieldSources: packageFieldSources ?? this.packageFieldSources,
    packageLabelBasis: identical(packageLabelBasis, _unset)
        ? this.packageLabelBasis
        : packageLabelBasis as String?,
    preservedDensity: preservedDensity ?? this.preservedDensity,
    // A hand edit to a package amount or a serving makes a photographed
    // record mixed, rather than leaving it claiming a photo said so (spec
    // R13). An explicit source passed by a caller still wins.
    packageNutritionSource:
        packageNutritionSource ??
        _sourceAfterEdit(packSize ?? this.packSize, servings ?? this.servings),
  );

  /// A nutrient as a field's text: a plain decimal, never a kitchen fraction.
  ///
  /// `writeAmount` renders "1 1/2", which is right for a measuring amount —
  /// two thirds of a cup is how a recipe is written and how a jug is marked.
  /// A nutrient is not that. Nobody writes a gram and a half of protein as
  /// "1 1/2 g", and the seven nutrient fields carry a **decimal keyboard**,
  /// which has no "/" on it. So a stored 1.5 reopened as "1 1/2", one
  /// backspace made it "1 1/", and there was no key on the pad that could put
  /// it back — a value the user could see, could break, and could not repair.
  ///
  /// The Amount field above is the opposite case and keeps `writeAmount`: it
  /// takes `TextInputType.text` precisely so a fraction can be typed there.
  static String _plain(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();

  /// A zero macro reopens as an empty field, not a literal "0".
  ///
  /// Showing "0" made the field look filled in, and typing into it produced
  /// "0250" rather than "250" — the digits landed beside a value the user
  /// never entered. Empty also lets the hint do its job.
  static String _macroText(double value) => value == 0 ? '' : _plain(value);

  /// A minor nutrient as a field's text: empty for unknown, **"0" for a
  /// stated zero** (spec §5.6).
  ///
  /// Deliberately not [_macroText]. That one blanks a zero, which is right for
  /// the four — an empty calorie field parses back to the zero it came from,
  /// and nothing is lost. Here a blank field means "nobody said", so blanking
  /// a stated zero would turn a fact into a gap on every edit. Water really
  /// does have no sodium.
  static String _minorText(double? value) => value == null ? '' : _plain(value);

  /// Everything a person can change, for the unsaved-work guard (review F01).
  ///
  /// **Every field of this class belongs in this list**, for the reason given
  /// on [ServingDraft._props].
  List<Object?> get _props => <Object?>[
    name,
    brand,
    menuGroup,
    menuOrder,
    storeTag,
    walmartItemId,
    packSize,
    barcode,
    servings,
    existingId,
    source,
    isDefault,
    isZeroCalorie,
    isModifier,
    massDisplayMode,
    servingsPerPackage,
    packageServingId,
    packageServingsApproximate,
    originalPackageNutrition?.toJson(),
    packageNutritionReviewed,
    originalPackSize,
    originalPackText,
    packageReviewNotes,
    packageBasisAcknowledged,
    packageLabelBasis,
    packageFieldSources,
    preservedDensity,
    packageNutritionSource,
  ];

  /// For the local draft record (review N01). See [ServingDraft.toJson].
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'brand': brand,
    'menu_group': menuGroup,
    'menu_order': menuOrder,
    'store_tag': storeTag,
    'walmart_item_id': walmartItemId,
    'pack_size': packSize,
    'barcode': barcode,
    'servings': <Map<String, Object?>>[
      for (final ServingDraft serving in servings) serving.toJson(),
    ],
    'existing_id': existingId,
    'source': source.name,
    'is_default': isDefault,
    'is_zero_calorie': isZeroCalorie,
    'is_modifier': isModifier,
    'mass_display_mode': massDisplayMode.toStorage(),
    'servings_per_package': servingsPerPackage,
    'package_serving_id': packageServingId,
    'package_servings_approximate': packageServingsApproximate,
    'original_package_nutrition': originalPackageNutrition?.toJson(),
    'package_nutrition_reviewed': packageNutritionReviewed,
    'original_pack_size': _quantityToJsonOrNull(originalPackSize),
    'original_pack_text': originalPackText,
    'package_review_notes': packageReviewNotes,
    'package_basis_acknowledged': packageBasisAcknowledged,
    'package_label_basis': packageLabelBasis,
    'package_field_sources': packageFieldSources,
    'preserved_density': preservedDensity,
    'package_nutrition_source': packageNutritionSource.name,
  };

  static FoodDraft fromJson(Map<String, Object?> json) => FoodDraft(
    name: '${json['name'] ?? ''}',
    brand: '${json['brand'] ?? ''}',
    menuGroup: '${json['menu_group'] ?? ''}',
    menuOrder: (json['menu_order'] as num?)?.toInt(),
    storeTag: '${json['store_tag'] ?? ''}',
    walmartItemId: '${json['walmart_item_id'] ?? ''}',
    packSize: '${json['pack_size'] ?? ''}',
    barcode: '${json['barcode'] ?? ''}',
    servings: <ServingDraft>[
      for (final Object? serving
          in json['servings'] as List<Object?>? ?? const <Object?>[])
        if (serving is Map<String, Object?>) ServingDraft.fromJson(serving),
    ],
    existingId: json['existing_id'] as String?,
    source: FoodSource.values.firstWhere(
      (FoodSource s) => s.name == json['source'],
      orElse: () => FoodSource.manual,
    ),
    isDefault: json['is_default'] == true,
    isZeroCalorie: json['is_zero_calorie'] == true,
    isModifier: json['is_modifier'] == true,
    massDisplayMode: MassDisplayMode.fromStorage(
      json['mass_display_mode'] as String?,
    ),
    servingsPerPackage: '${json['servings_per_package'] ?? ''}',
    packageServingId: json['package_serving_id'] as String?,
    packageServingsApproximate: json['package_servings_approximate'] == true,
    originalPackageNutrition: json['original_package_nutrition'] is Map
        ? PackageNutrition.fromJson(
            (json['original_package_nutrition'] as Map).cast<String, dynamic>(),
          )
        : null,
    packageNutritionReviewed: json['package_nutrition_reviewed'] == true,
    originalPackSize: _quantityFromJsonMap(json['original_pack_size']),
    originalPackText: json['original_pack_text'] as String?,
    packageReviewNotes: <String>[
      for (final Object? note
          in json['package_review_notes'] as List<Object?>? ??
              const <Object?>[])
        if (note is String) note,
    ],
    packageBasisAcknowledged: json['package_basis_acknowledged'] == true,
    packageLabelBasis: json['package_label_basis'] as String?,
    packageFieldSources: _sourcesFrom(json['package_field_sources']),
    preservedDensity: (json['preserved_density'] as num?)?.toDouble(),
    packageNutritionSource: PackageNutritionSource.values.firstWhere(
      (PackageNutritionSource s) => s.name == json['package_nutrition_source'],
      orElse: () => PackageNutritionSource.manual,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is FoodDraft &&
      const DeepCollectionEquality().equals(other._props, _props);

  @override
  int get hashCode => const DeepCollectionEquality().hash(_props);
}
