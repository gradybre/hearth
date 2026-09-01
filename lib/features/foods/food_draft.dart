import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../data/adapters/label_reader.dart';
import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/parsing/amount_parser.dart';
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
    this.id,
  });

  final String amount;
  final String unitId;
  final String kcal;
  final String protein;
  final String carbs;
  final String fat;

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

  Macros get macros => Macros(
    kcal: double.tryParse(kcal.trim()) ?? 0,
    proteinG: double.tryParse(protein.trim()) ?? 0,
    carbG: double.tryParse(carbs.trim()) ?? 0,
    fatG: double.tryParse(fat.trim()) ?? 0,
  );

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
  }) => ServingDraft(
    amount: amount ?? this.amount,
    unitId: unitId ?? this.unitId,
    kcal: kcal ?? this.kcal,
    protein: protein ?? this.protein,
    carbs: carbs ?? this.carbs,
    fat: fat ?? this.fat,
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
    this.storeTag = '',
    this.barcode = '',
    this.existingId,
    this.source = FoodSource.manual,
    this.isDefault = false,
  });

  factory FoodDraft.blank() => const FoodDraft(
    name: '',
    // One row to start, in grams: the unit almost every packet is labelled in.
    servings: <ServingDraft>[ServingDraft(amount: '100')],
  );

  factory FoodDraft.fromFood(Food food) => FoodDraft(
    name: food.name,
    brand: food.brand ?? '',
    storeTag: food.storeTag ?? '',
    barcode: food.barcode ?? '',
    existingId: food.id,
    source: food.source,
    isDefault: food.isDefault,
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
      storeTag: mapped.storeTag,
      barcode: mapped.barcode,
      source: food.source,
      isDefault: mapped.isDefault,
      servings: <ServingDraft>[
        for (final ServingDraft serving in mapped.servings)
          ServingDraft(
            amount: serving.amount,
            unitId: serving.unitId,
            kcal: _rounded(serving.kcal, decimals: 0),
            protein: _rounded(serving.protein),
            carbs: _rounded(serving.carbs),
            fat: _rounded(serving.fat),
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
    final List<ServingDraft> kept = <ServingDraft>[
      for (final ServingDraft serving in servings)
        if (!serving.isUntouchedStarter) serving,
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
      servings: <ServingDraft>[...kept, ...added],
    );
  }

  final String name;
  final String brand;
  final String storeTag;
  final String barcode;
  final List<ServingDraft> servings;
  final String? existingId;
  final FoodSource source;

  /// One of the household's standing choices (spec §5.3).
  final bool isDefault;

  bool get isEditing => existingId != null;

  String? get nameError => name.trim().isEmpty ? 'A food needs a name.' : null;

  String? get servingsError =>
      usableServings.isEmpty ? 'Add at least one serving size.' : null;

  bool get isValid => nameError == null && servingsError == null;

  List<ServingDraft> get usableServings =>
      servings.where((ServingDraft s) => s.isUsable).toList(growable: false);

  Food toFood({String Function()? idFactory}) {
    final String Function() newId = idFactory ?? const Uuid().v4;
    return Food(
      id: existingId ?? newId(),
      name: name.trim(),
      brand: brand.trim().isEmpty ? null : brand.trim(),
      storeTag: storeTag.trim().isEmpty ? null : storeTag.trim(),
      barcode: barcode.trim().isEmpty ? null : barcode.trim(),
      source: source,
      isDefault: isDefault,
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
    String? storeTag,
    String? barcode,
    List<ServingDraft>? servings,
    bool? isDefault,
  }) => FoodDraft(
    name: name ?? this.name,
    brand: brand ?? this.brand,
    storeTag: storeTag ?? this.storeTag,
    barcode: barcode ?? this.barcode,
    servings: servings ?? this.servings,
    existingId: existingId,
    source: source,
    isDefault: isDefault ?? this.isDefault,
  );

  /// A zero macro reopens as an empty field, not a literal "0".
  ///
  /// Showing "0" made the field look filled in, and typing into it produced
  /// "0250" rather than "250" — the digits landed beside a value the user
  /// never entered. Empty also lets the hint do its job.
  static String _macroText(double value) =>
      value == 0 ? '' : writeAmount(value);
}
