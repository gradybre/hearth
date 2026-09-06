import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../data/adapters/label_reader.dart';
import '../../domain/format/quantity_format.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/parsing/amount_parser.dart';
import '../../domain/shopping/walmart_product.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';

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

  Unit get unit => Units.byId(unitId) ?? Units.gram;

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
  Iterable<String> get unreadableFields sync* {
    for (final (String name, String raw) in <(String, String)>[
      ('calories', kcal),
      ('protein', protein),
      ('carbs', carbs),
      ('fat', fat),
      ('fibre', fiber),
      ('sodium', sodium),
      ('cholesterol', cholesterol),
    ]) {
      if (raw.trim().isNotEmpty && _field(raw) == null) yield name;
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
    id: id,
  );
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
  });

  factory FoodDraft.blank() => const FoodDraft(
    name: '',
    // One row to start, in grams: the unit almost every packet is labelled in.
    servings: <ServingDraft>[ServingDraft(amount: '100')],
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
        : QuantityFormat.format(food.packSize!),
    barcode: food.barcode ?? '',
    existingId: food.id,
    source: food.source,
    isDefault: food.isDefault,
    isZeroCalorie: food.isZeroCalorie,
    isModifier: food.isModifier,
    servings: <ServingDraft>[
      for (final ServingOption option in food.servingOptions)
        ServingDraft(
          id: option.id,
          amount: writeAmount(
            option.amount.amountIn(
              option.amount.preferredUnit ??
                  Units.canonicalFor(option.amount.kind),
            ),
          ),
          unitId:
              (option.amount.preferredUnit ??
                      Units.canonicalFor(option.amount.kind))
                  .id,
          kcal: _macroText(option.macros.kcal),
          protein: _macroText(option.macros.proteinG),
          carbs: _macroText(option.macros.carbG),
          fat: _macroText(option.macros.fatG),
          // Empty for an unknown, so editing a food Hearth was never told
          // about does not silently record a zero on the way back out.
          fiber: _minorText(option.macros.fiberG),
          sodium: _minorText(option.macros.sodiumMg),
          cholesterol: _minorText(option.macros.cholesterolMg),
        ),
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
  factory FoodDraft.fromLookup(Food food) {
    final FoodDraft mapped = FoodDraft.fromFood(food);
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
      servings: <ServingDraft>[
        for (final ServingDraft serving in mapped.servings)
          ServingDraft(
            amount: serving.amount,
            unitId: serving.unitId,
            kcal: _rounded(serving.kcal, decimals: 0),
            protein: _rounded(serving.protein),
            carbs: _rounded(serving.carbs),
            fat: _rounded(serving.fat),
            fiber: _rounded(serving.fiber),
            sodium: _rounded(serving.sodium, decimals: 0),
            cholesterol: _rounded(serving.cholesterol, decimals: 0),
          ),
      ],
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
    final double? parsed = double.tryParse(value);
    if (parsed == null) return value;
    return writeAmount(double.parse(parsed.toStringAsFixed(decimals)));
  }

  /// A food nobody had, carrying only the number that was scanned, so the next
  /// scan of the same packet finds it (spec §5.5).
  factory FoodDraft.forBarcode(String barcode) => FoodDraft(
    name: '',
    barcode: barcode,
    servings: const <ServingDraft>[ServingDraft(amount: '100')],
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
    // A row with a portion and no macros is a gap, not an answer — unless the
    // household has said this food really is zero, which is the one case where
    // four zeroes are the measurement. Only ever dropped when the label has
    // something to put in its place.
    final bool replaceEmptyRows = !isZeroCalorie && reading.servings.isNotEmpty;

    final List<ServingDraft> kept = <ServingDraft>[
      for (final ServingDraft serving in servings)
        if (!serving.isUntouchedStarter)
          if (!replaceEmptyRows || !serving.hasNoMacros) serving,
    ];

    final List<ServingDraft> added = <ServingDraft>[];
    for (final LabelServing read in reading.servings) {
      final ServingDraft candidate = ServingDraft(
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

    return FoodDraft(
      name: name.trim().isEmpty ? (reading.name ?? '') : name,
      brand: brand.trim().isEmpty ? (reading.brand ?? '') : brand,
      storeTag: storeTag,
      barcode: barcode,
      existingId: existingId,
      source: source,
      isDefault: isDefault,
      isZeroCalorie: isZeroCalorie,
      isModifier: isModifier,
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

  Food toFood({String Function()? idFactory}) {
    final String Function() newId = idFactory ?? const Uuid().v4;
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
      packSize: parsePackSize(packSize),
      barcode: barcode.trim().isEmpty ? null : barcode.trim(),
      source: source,
      isDefault: isDefault,
      isZeroCalorie: isZeroCalorie,
      isModifier: isModifier,
      servingOptions: <ServingOption>[
        for (final ServingDraft serving in usableServings)
          ServingOption(
            id: serving.id ?? newId(),
            label: serving.label,
            amount: Quantity.of(serving.amountValue!, serving.unit),
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
  );

  /// A zero macro reopens as an empty field, not a literal "0".
  ///
  /// Showing "0" made the field look filled in, and typing into it produced
  /// "0250" rather than "250" — the digits landed beside a value the user
  /// never entered. Empty also lets the hint do its job.
  static String _macroText(double value) =>
      value == 0 ? '' : writeAmount(value);

  /// A minor nutrient as a field's text: empty for unknown, **"0" for a
  /// stated zero** (spec §5.6).
  ///
  /// Deliberately not [_macroText]. That one blanks a zero, which is right for
  /// the four — an empty calorie field parses back to the zero it came from,
  /// and nothing is lost. Here a blank field means "nobody said", so blanking
  /// a stated zero would turn a fact into a gap on every edit. Water really
  /// does have no sodium.
  static String _minorText(double? value) =>
      value == null ? '' : writeAmount(value);
}

/// A typed pack size — "1 lb", "7.2 oz" — as a quantity, or null.
///
/// Reuses the pieces already here rather than a new parser: [parseAmount] for
/// the number, [Units.parse] for the unit, which is the pair the ingredient
/// parser uses. Null when either half is missing, because half a pack size
/// silently orders the wrong amount.
Quantity? parsePackSize(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return null;

  final Match? split = RegExp(r'^([^a-zA-Z]+)\s*(.*)$').firstMatch(text);
  if (split == null) return null;
  final double? amount = parseAmount(split.group(1)!);
  if (amount == null || amount <= 0) return null;

  final String unitWord = split.group(2)!.trim();
  final Unit? unit = unitWord.isEmpty ? Units.item : Units.parse(unitWord);
  return unit == null ? null : Quantity.of(amount, unit);
}
