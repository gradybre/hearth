import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/package_nutrition.dart';
import '../../domain/units/mass_display_mode.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import '../local/hearth_database.dart';
import 'quantity_mapper.dart';

/// Maps foods between the domain model and the two tables that store them.
abstract final class FoodMapper {
  static const Map<String, FoodSource> _sourceFromSql = <String, FoodSource>{
    'open_food_facts': FoodSource.openFoodFacts,
    'usda': FoodSource.usda,
    'manual': FoodSource.manual,
    'ai_estimate': FoodSource.aiEstimate,
    'restaurant': FoodSource.restaurant,
  };

  static String sourceToSql(FoodSource source) => switch (source) {
    FoodSource.openFoodFacts => 'open_food_facts',
    FoodSource.usda => 'usda',
    FoodSource.manual => 'manual',
    FoodSource.aiEstimate => 'ai_estimate',
    FoodSource.restaurant => 'restaurant',
  };

  static FoodSource sourceFromSql(String value) =>
      _sourceFromSql[value] ?? FoodSource.manual;

  static Food toDomain({
    required FoodRow food,
    required List<FoodServingOptionRow> servings,
  }) => Food(
    id: food.id,
    householdId: food.householdId,
    name: food.name,
    brand: food.brand,
    storeTag: food.storeTag,
    walmartItemId: food.walmartItemId,
    packSize: _packFrom(food),
    barcode: food.barcode,
    menuGroup: food.menuGroup,
    menuOrder: food.menuOrder,
    gramsPerMillilitre: food.gramsPerMillilitre,
    source: sourceFromSql(food.source),
    macrosOverridden: food.macrosOverridden,
    isDefault: food.isDefault,
    isZeroCalorie: food.isZeroCalorie,
    isModifier: food.isModifier,
    isDeleted: food.isDeleted,
    updatedAt: food.updatedAt,
    massDisplayMode: MassDisplayMode.fromStorage(food.massDisplayMode),
    packageNutrition: decodePackageNutrition(food.packageNutrition),
    servingOptions: <ServingOption>[
      for (final FoodServingOptionRow row in servings)
        ServingOption(
          id: row.id,
          label: row.label,
          amount:
              QuantityMapper.fromSql(
                canonicalAmount: row.amountCanonical,
                kind: row.amountKind,
                unitId: row.amountUnit,
              ) ??
              Quantity.canonical(
                canonicalAmount: row.amountCanonical,
                kind: UnitKind.mass,
              ),
          macros: Macros(
            kcal: row.kcal,
            proteinG: row.proteinG,
            carbG: row.carbG,
            fatG: row.fatG,
            // No `?? 0`. A serving that has never been told its fibre says so
            // by staying null all the way back out (spec §5.6).
            fiberG: row.fiberG,
            sodiumMg: row.sodiumMg,
            cholesterolMg: row.cholesterolMg,
          ),
        ),
    ],
  );

  static FoodsCompanion toCompanion(Food food, DateTime updatedAt) =>
      FoodsCompanion.insert(
        id: food.id,
        householdId: Value<String?>(food.householdId),
        name: food.name,
        brand: Value<String?>(food.brand),
        storeTag: Value<String?>(food.storeTag),
        walmartItemId: Value<String?>(food.walmartItemId),
        packCanonical: Value<double?>(food.packSize?.canonicalAmount),
        packKind: Value<String?>(food.packSize?.kind.name),
        packUnit: Value<String?>(food.packSize?.preferredUnit?.id),
        barcode: Value<String?>(food.barcode),
        menuGroup: Value<String?>(food.menuGroup),
        menuOrder: Value<int?>(food.menuOrder),
        gramsPerMillilitre: Value<double?>(food.gramsPerMillilitre),
        source: Value<String>(sourceToSql(food.source)),
        macrosOverridden: Value<bool>(food.macrosOverridden),
        isDefault: Value<bool>(food.isDefault),
        isZeroCalorie: Value<bool>(food.isZeroCalorie),
        isModifier: Value<bool>(food.isModifier),
        isDeleted: Value<bool>(food.isDeleted),
        massDisplayMode: Value<String>(food.massDisplayMode.toStorage()),
        packageNutrition: Value<String?>(
          encodePackageNutrition(food.packageNutrition),
        ),
        updatedAt: updatedAt,
      );

  static List<FoodServingOptionsCompanion> servingCompanions(Food food) =>
      <FoodServingOptionsCompanion>[
        for (int i = 0; i < food.servingOptions.length; i++)
          FoodServingOptionsCompanion.insert(
            id: food.servingOptions[i].id,
            foodId: food.id,
            label: food.servingOptions[i].label,
            amountCanonical: food.servingOptions[i].amount.canonicalAmount,
            amountKind: QuantityMapper.kindToSql(
              food.servingOptions[i].amount.kind,
            ),
            amountUnit: Value<String?>(
              food.servingOptions[i].amount.preferredUnit?.id,
            ),
            kcal: Value<double>(food.servingOptions[i].macros.kcal),
            proteinG: Value<double>(food.servingOptions[i].macros.proteinG),
            carbG: Value<double>(food.servingOptions[i].macros.carbG),
            fatG: Value<double>(food.servingOptions[i].macros.fatG),
            fiberG: Value<double?>(food.servingOptions[i].macros.fiberG),
            sodiumMg: Value<double?>(food.servingOptions[i].macros.sodiumMg),
            cholesterolMg: Value<double?>(
              food.servingOptions[i].macros.cholesterolMg,
            ),
            // From the food, never from the serving. The column exists to
            // carry the food's answer to where a hosted check constraint can
            // see it, and a serving that disagreed would be refused by the
            // composite foreign key anyway.
            isModifier: Value<bool>(food.isModifier),
            sortOrder: Value<int>(i),
          ),
      ];

  /// The food as a sync payload, matching the shape the remote gateway writes
  /// across the two Supabase tables.
  static Map<String, Object?> toJson(
    Food food, {
    required DateTime updatedAt,
  }) => <String, Object?>{
    'id': food.id,
    'household_id': food.householdId,
    'name': food.name,
    'brand': food.brand,
    'store_tag': food.storeTag,
    'walmart_item_id': food.walmartItemId,
    'pack_canonical': food.packSize?.canonicalAmount,
    'pack_kind': food.packSize?.kind.name,
    'pack_unit': food.packSize?.preferredUnit?.id,
    'barcode': food.barcode,
    'menu_group': food.menuGroup,
    'menu_order': food.menuOrder,
    'grams_per_millilitre': food.gramsPerMillilitre,
    'source': sourceToSql(food.source),
    'macros_overridden': food.macrosOverridden,
    'is_default': food.isDefault,
    'is_zero_calorie': food.isZeroCalorie,
    'is_modifier': food.isModifier,
    'is_deleted': food.isDeleted,
    // Both keys are always stated by this build, and the null matters: the
    // upsert function tells an omitted key (an older client saying nothing,
    // so leave the stored relationship alone) apart from an explicit null
    // (the user having removed it). Writing the key is how this build says
    // which of the two it means (spec R13).
    'mass_display_mode': food.massDisplayMode.toStorage(),
    // A record this build already knows the server would refuse is left out
    // rather than pushed. An absent key means 'nothing to say about this', so
    // the stored relationship is preserved server-side and the rest of the
    // food -- its name, its macros, its servings -- still syncs instead of
    // being retried to the attempt cap behind it. The malformed record stays
    // in the local column, which is what the editor offers for correction
    // (review B4, spec R10, R13).
    if (food.packageNutrition == null || food.packageNutrition!.isSendable)
      'package_nutrition': food.packageNutrition?.toJson(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'serving_options': <Map<String, Object?>>[
      for (int i = 0; i < food.servingOptions.length; i++)
        <String, Object?>{
          'id': food.servingOptions[i].id,
          'food_id': food.id,
          'label': food.servingOptions[i].label,
          'amount_canonical': food.servingOptions[i].amount.canonicalAmount,
          'amount_kind': QuantityMapper.kindToSql(
            food.servingOptions[i].amount.kind,
          ),
          'amount_unit': food.servingOptions[i].amount.preferredUnit?.id,
          'kcal': food.servingOptions[i].macros.kcal,
          'protein_g': food.servingOptions[i].macros.proteinG,
          'carb_g': food.servingOptions[i].macros.carbG,
          'fat_g': food.servingOptions[i].macros.fatG,
          'fiber_g': food.servingOptions[i].macros.fiberG,
          'sodium_mg': food.servingOptions[i].macros.sodiumMg,
          'cholesterol_mg': food.servingOptions[i].macros.cholesterolMg,
          'sort_order': i,
        },
    ],
  };

  /// The pack size as stored, or null when the row carries none.
  ///
  /// Shared with [SyncPayload.food] rather than written twice — the two
  /// directions drifting apart is exactly how a column goes quietly missing.
  static Quantity? _packFrom(FoodRow food) =>
      packSizeFrom(food.packCanonical, food.packKind, food.packUnit);

  /// A reviewed package relationship as the text the local column holds, or
  /// null when there is none (spec R13).
  ///
  /// An unrecognised version encodes back to exactly the JSON it arrived as,
  /// because `PackageNutrition.toJson` hands back its raw map -- so a build
  /// that re-saves a food carrying a format it does not understand does not
  /// quietly discard it.
  static String? encodePackageNutrition(PackageNutrition? relation) =>
      relation == null ? null : jsonEncode(relation.toJson());

  /// Reads a relationship from either place it is stored: the local column's
  /// JSON text, or a server payload's already-decoded map.
  ///
  /// Tolerant on purpose. Anything unreadable answers null rather than
  /// throwing, because one malformed record must not be able to stop a
  /// library loading or a sync pass finishing -- and `PackageNutrition`
  /// itself reports whether what was read is usable.
  static PackageNutrition? decodePackageNutrition(Object? value) {
    if (value == null) return null;
    if (value is Map) return PackageNutrition.fromJson(_asStringKeyed(value));
    if (value is! String) return null;
    final String text = value.trim();
    if (text.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return PackageNutrition.fromJson(_asStringKeyed(decoded));
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic> _asStringKeyed(Map<Object?, Object?> map) =>
      map.map(
        (Object? key, Object? value) =>
            MapEntry<String, dynamic>('$key', value),
      );

  /// The display mode a payload states, or [fallback] when it says nothing.
  ///
  /// Key presence decides, never the value. A build that has never heard of
  /// this field omits the key entirely, and its ordinary edits must leave
  /// whatever the household chose alone -- reading an absent key as
  /// `automatic` would reset the preference on every write such a device
  /// made (spec R4, R8).
  static MassDisplayMode massDisplayModeFrom(
    Map<String, Object?> json, {
    MassDisplayMode fallback = MassDisplayMode.automatic,
  }) {
    if (!json.containsKey('mass_display_mode')) return fallback;
    final Object? value = json['mass_display_mode'];
    // An unknown future value reads as automatic rather than failing, and is
    // never written back over a known explicit setting by this path.
    return MassDisplayMode.fromStorage(value is String ? value : null);
  }

  /// The relationship a payload states, or [fallback] when it says nothing.
  ///
  /// The same presence rule, and the distinction R13 turns on: an omitted key
  /// is silence and preserves what is stored, while an explicit null is the
  /// user having removed the relationship and clears it.
  static PackageNutrition? packageNutritionFrom(
    Map<String, Object?> json, {
    PackageNutrition? fallback,
  }) => json.containsKey('package_nutrition')
      ? decodePackageNutrition(json['package_nutrition'])
      : fallback;
}

/// Rebuilds a pack size from the three columns it is stored in.
Quantity? packSizeFrom(double? canonical, String? kind, String? unit) {
  if (canonical == null || kind == null) return null;
  final UnitKind? parsed = switch (kind) {
    'volume' => UnitKind.volume,
    'mass' => UnitKind.mass,
    'count' => UnitKind.count,
    _ => null,
  };
  if (parsed == null) return null;
  return Quantity.canonical(
    canonicalAmount: canonical,
    kind: parsed,
    preferredUnit: unit == null ? null : Units.byId(unit),
  );
}
