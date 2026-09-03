import 'package:drift/drift.dart';

import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
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
    gramsPerMillilitre: food.gramsPerMillilitre,
    source: sourceFromSql(food.source),
    macrosOverridden: food.macrosOverridden,
    isDefault: food.isDefault,
    isZeroCalorie: food.isZeroCalorie,
    isDeleted: food.isDeleted,
    updatedAt: food.updatedAt,
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
        gramsPerMillilitre: Value<double?>(food.gramsPerMillilitre),
        source: Value<String>(sourceToSql(food.source)),
        macrosOverridden: Value<bool>(food.macrosOverridden),
        isDefault: Value<bool>(food.isDefault),
        isZeroCalorie: Value<bool>(food.isZeroCalorie),
        isDeleted: Value<bool>(food.isDeleted),
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
    'grams_per_millilitre': food.gramsPerMillilitre,
    'source': sourceToSql(food.source),
    'macros_overridden': food.macrosOverridden,
    'is_default': food.isDefault,
    'is_zero_calorie': food.isZeroCalorie,
    'is_deleted': food.isDeleted,
    'updated_at': updatedAt.toIso8601String(),
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
