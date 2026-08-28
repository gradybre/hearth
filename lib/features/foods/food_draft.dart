import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
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

  double? get amountValue => double.tryParse(amount.trim());

  /// A serving is worth saving once it has a positive amount. Macros default
  /// to zero rather than blocking: a food with a known portion and unknown
  /// calories is still more useful than no food at all (spec §5.3's
  /// flag-never-block principle).
  bool get isUsable => (amountValue ?? 0) > 0;

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
    servings: <ServingDraft>[
      for (final ServingOption option in food.servingOptions)
        ServingDraft(
          id: option.id,
          amount: _trimNumber(
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

  final String name;
  final String brand;
  final String storeTag;
  final String barcode;
  final List<ServingDraft> servings;
  final String? existingId;
  final FoodSource source;

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
  }) => FoodDraft(
    name: name ?? this.name,
    brand: brand ?? this.brand,
    storeTag: storeTag ?? this.storeTag,
    barcode: barcode ?? this.barcode,
    servings: servings ?? this.servings,
    existingId: existingId,
    source: source,
  );

  static String _trimNumber(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  /// A zero macro reopens as an empty field, not a literal "0".
  ///
  /// Showing "0" made the field look filled in, and typing into it produced
  /// "0250" rather than "250" — the digits landed beside a value the user
  /// never entered. Empty also lets the hint do its job.
  static String _macroText(double value) =>
      value == 0 ? '' : _trimNumber(value);
}
