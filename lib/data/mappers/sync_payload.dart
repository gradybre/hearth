import '../../domain/models/food.dart';
import '../../domain/models/macros.dart';
import '../../domain/models/recipe.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import 'food_mapper.dart';
import 'quantity_mapper.dart';
import 'recipe_mapper.dart';

/// Reads the JSON a record arrives as (spec §7.1).
///
/// The shape is the same one the client pushes, so the two directions cannot
/// drift apart: a field added to the payload without a reader here shows up as
/// a lost value on the next device rather than as a compile error, which is
/// why the push shape and these functions live next to each other.
///
/// Every read is defensive. A record from the server is not something this
/// device wrote, and a null where a number was expected must not take down a
/// sync that is otherwise fine.
abstract final class SyncPayload {
  static Recipe recipe(Map<String, Object?> json) {
    final List<Map<String, Object?>> sections = _list(json['sections']);
    final List<Map<String, Object?>> ingredients = _list(json['ingredients']);
    final List<Map<String, Object?>> steps = _list(json['steps']);

    return Recipe(
      id: '${json['id']}',
      householdId: json['household_id'] as String?,
      title: '${json['title'] ?? ''}',
      servings: _double(json['servings']) ?? 1,
      prepTime: _duration(json['prep_seconds']),
      cookTime: _duration(json['cook_seconds']),
      cuisine: json['cuisine'] as String?,
      tags: <String>[
        for (final Object? tag in (json['tags'] as List<Object?>?) ?? const [])
          '$tag',
      ],
      source: RecipeMapper.sourceFromSql('${json['source'] ?? 'manual'}'),
      photoUrl: json['photo_url'] as String?,
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      isDeleted: json['is_deleted'] == true,
      updatedAt: updatedAt(json),
      sections: <RecipeSection>[
        for (final Map<String, Object?> section in sections)
          RecipeSection(
            id: '${section['id']}',
            name: '${section['name'] ?? Recipe.defaultSectionName}',
            sortOrder: _int(section['sort_order']) ?? 0,
            ingredients: <RecipeIngredient>[
              for (final Map<String, Object?> i in ingredients)
                if ('${i['section_id']}' == '${section['id']}')
                  RecipeIngredient(
                    id: '${i['id']}',
                    sectionId: '${section['id']}',
                    name: '${i['name'] ?? ''}',
                    quantity: _quantity(
                      i['quantity_canonical'],
                      i['quantity_kind'],
                      i['quantity_unit'],
                    ),
                    rawText: i['raw_text'] as String?,
                    prepNote: i['prep_note'] as String?,
                    foodId: i['food_id'] as String?,
                    isOptional: i['is_optional'] == true,
                    needsNoMatch: i['needs_no_match'] == true,
                    sortOrder: _int(i['sort_order']) ?? 0,
                  ),
            ],
            steps: <RecipeStep>[
              for (final Map<String, Object?> s in steps)
                if ('${s['section_id']}' == '${section['id']}')
                  RecipeStep(
                    id: '${s['id']}',
                    sectionId: '${section['id']}',
                    stepNumber: _int(s['step_number']) ?? 0,
                    text: '${s['body'] ?? ''}',
                    timerSeconds: _int(s['timer_seconds']),
                  ),
            ],
          ),
      ],
    );
  }

  static Food food(Map<String, Object?> json) => Food(
    id: '${json['id']}',
    householdId: json['household_id'] as String?,
    name: '${json['name'] ?? ''}',
    brand: json['brand'] as String?,
    storeTag: json['store_tag'] as String?,
    barcode: json['barcode'] as String?,
    gramsPerMillilitre: _double(json['grams_per_millilitre']),
    source: FoodMapper.sourceFromSql('${json['source'] ?? 'manual'}'),
    macrosOverridden: json['macros_overridden'] == true,
    isDefault: json['is_default'] == true,
    isDeleted: json['is_deleted'] == true,
    updatedAt: updatedAt(json),
    servingOptions: <ServingOption>[
      for (final Map<String, Object?> o in _list(json['serving_options']))
        ServingOption(
          id: '${o['id']}',
          label: '${o['label'] ?? ''}',
          amount:
              _quantity(
                o['amount_canonical'],
                o['amount_kind'],
                o['amount_unit'],
              ) ??
              Quantity.of(1, Units.item),
          macros: Macros(
            kcal: _double(o['kcal']) ?? 0,
            proteinG: _double(o['protein_g']) ?? 0,
            carbG: _double(o['carb_g']) ?? 0,
            fatG: _double(o['fat_g']) ?? 0,
          ),
        ),
    ],
  );

  /// When the server last changed this record, for last-write-wins.
  static DateTime? updatedAt(Map<String, Object?> json) =>
      DateTime.tryParse('${json['updated_at']}')?.toUtc();

  static List<Map<String, Object?>> _list(Object? value) =>
      <Map<String, Object?>>[
        for (final Object? item in (value as List<Object?>?) ?? const [])
          if (item is Map<String, Object?>) item,
      ];

  /// Postgres numerics arrive as num, as a string, or not at all.
  static double? _double(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static int? _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  static Duration? _duration(Object? seconds) {
    final int? value = _int(seconds);
    return value == null ? null : Duration(seconds: value);
  }

  static Quantity? _quantity(Object? amount, Object? kind, Object? unit) {
    final double? canonical = _double(amount);
    if (canonical == null) return null;
    return QuantityMapper.fromSql(
      canonicalAmount: canonical,
      kind: kind as String?,
      unitId: unit as String?,
    );
  }
}
