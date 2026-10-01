import 'dart:convert';

import '../../domain/models/macros.dart';
import '../../domain/planning/logged_portion.dart';
import '../../domain/planning/meal_plan.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import '../mappers/plan_mapper.dart';
import 'data_export.dart';

/// Readable projections of the exact snapshot, with no live food lookup.
class ReadableArchiveRows {
  ReadableArchiveRows(this.snapshot)
    : _data = jsonDecode(snapshot.file.contents) as Map<String, Object?>;

  final ExportSnapshot snapshot;
  final Map<String, Object?> _data;

  bool containsRecipe(String id) => _rows(_data['recipes']).any(
    (Map<String, Object?> r) =>
        r['id'] == id && r['household_id'] == snapshot.householdId,
  );

  Iterable<String> meals({required bool logged}) =>
      archiveCsv(_mealRows(logged));

  Iterable<List<Object?>> _mealRows(bool logged) sync* {
    yield <Object?>[
      'entry_id',
      'diary_date',
      'meal_slot',
      'is_deleted',
      'is_logged',
      'is_planned',
      'source_type',
      'source_id',
      'name',
      'name_basis',
      'entry_servings',
      'entry_serving_option_id',
      'planned_serving_basis',
      'planned_serving_label',
      'planned_serving_amount',
      'planned_serving_unit',
      'frozen_servings',
      'entered_amount',
      'entered_unit',
      'entered_unit_id',
      'portion_evidence',
      'nutrition_serving_label',
      'nutrition_serving_amount',
      'nutrition_serving_unit',
      'logged_at_utc',
      'snapshot_captured_at_as_recorded',
      ..._nutrients,
      'fiber_coverage',
      'sodium_coverage',
      'cholesterol_coverage',
      'uses_approximate_package_nutrition',
    ];
    final Map<Object?, Map<String, Object?>> days =
        <Object?, Map<String, Object?>>{
          for (final Map<String, Object?> day in _rows(_data['meal_plan_days']))
            day['id']: day,
        };
    final Map<String, Object?> names = <String, Object?>{
      for (final Map<String, Object?> r in _rows(_data['recipes']))
        'recipe:${r['id']}': r['title'],
      for (final Map<String, Object?> f in _rows(_data['foods']))
        'food:${f['id']}': f['name'],
    };
    final Map<Object?, Map<String, Object?>> foods =
        <Object?, Map<String, Object?>>{
          for (final Map<String, Object?> food in _rows(_data['foods']))
            food['id']: food,
        };
    for (final Map<String, Object?> entry in _rows(
      _data['meal_plan_entries'],
    )) {
      if (logged ? entry['is_logged'] != true : entry['is_planned'] != true) {
        continue;
      }
      final Map<String, Object?> raw = _map(entry['macro_snapshot']);
      final MacroSnapshot? frozen = raw.isEmpty
          ? null
          : PlanMapper.snapshotFromJson(jsonEncode(raw));
      final LoggedPortion? portion = frozen?.usableLoggedPortion;
      final bool historical = entry['is_logged'] == true;
      final bool plannedFood = !historical && entry['ref_type'] == 'food';
      final bool basisRecorded = snapshot.entryServingOptionIds.containsKey(
        entry['id'],
      );
      final String? servingId = snapshot.entryServingOptionIds[entry['id']];
      final Map<String, Object?>? food = foods[entry['ref_id']];
      final List<Map<String, Object?>> options = food?['is_deleted'] == true
          ? <Map<String, Object?>>[]
          : _rows(food?['serving_options']).toList();
      final Map<String, Object?>? plannedServing =
          !plannedFood || !basisRecorded
          ? null
          : servingId == null
          ? options.firstOrNull
          : options
                .where(
                  (Map<String, Object?> option) => option['id'] == servingId,
                )
                .firstOrNull;
      final plannedAmount = _storedQuantity(
        plannedServing?['amount_canonical'],
        plannedServing?['amount_kind'],
        plannedServing?['amount_unit'],
      );
      final Object? name = historical
          ? raw['label']
          : names['${entry['ref_type']}:${entry['ref_id']}'];
      final ({Object? amount, String? unit}) serving = portion == null
          ? (amount: null, unit: null)
          : _quantity(portion.nutritionServing.amount);
      yield <Object?>[
        entry['id'],
        days[entry['meal_plan_day_id']]?['day'],
        entry['meal_slot'],
        snapshot.entryDeletionStates[entry['id']] ?? 'not recorded',
        entry['is_logged'],
        entry['is_planned'],
        entry['ref_type'],
        entry['ref_id'],
        name,
        historical
            ? (name == null ? 'not recorded' : 'frozen at logging')
            : 'definition at export',
        _number(entry['servings']),
        servingId,
        !plannedFood
            ? null
            : !basisRecorded
            ? 'not recorded'
            : plannedServing == null
            ? '${servingId == null ? 'first' : 'selected'} serving unavailable at export'
            : '${servingId == null ? 'first' : 'selected'} serving at export',
        plannedServing?['label'],
        plannedAmount.amount,
        plannedAmount.unit,
        _number(raw['servings']),
        portion?.enteredAmount,
        portion?.enteredUnit.label,
        portion?.enteredUnit.id,
        portion != null
            ? 'recorded'
            : raw.containsKey('logged_portion')
            ? 'unavailable; see original JSON'
            : 'not recorded',
        portion?.nutritionServing.label,
        serving.amount,
        serving.unit,
        entry['logged_at'],
        raw['captured_at'],
        for (final String key in _nutrients) _number(raw[key]),
        for (final MinorNutrient nutrient in MinorNutrient.values)
          frozen?.coverage.of(nutrient).name ?? 'notRecorded',
        raw['uses_approximate_package_nutrition'] is bool
            ? raw['uses_approximate_package_nutrition']
            : null,
      ];
    }
  }

  Iterable<String> targets() => archiveCsv(_targetRows());

  Iterable<List<Object?>> _targetRows() sync* {
    yield <Object?>[
      'record_type',
      'id',
      'week_start_date',
      ..._nutrients,
      'updated_at_utc',
    ];
    for (final Map<String, Object?> row in _rows(_data['macro_targets'])) {
      yield <Object?>[
        'exact week',
        row['id'],
        row['week_start_date'],
        for (final String key in _nutrients) _number(row[key]),
        null,
      ];
    }
    for (final Map<String, Object?> row in _rows(
      _data['ongoing_macro_targets'],
    )) {
      yield <Object?>[
        row['is_stopped'] == true
            ? 'stop carrying forward'
            : 'from this week onward',
        row['id'],
        row['week_start_date'],
        for (final String key in _nutrients) _number(row[key]),
        row['updated_at'],
      ];
    }
  }

  Iterable<String> foods() => archiveCsv(_foodRows());

  Iterable<List<Object?>> _foodRows() sync* {
    yield <Object?>[
      'food_id',
      'name',
      'brand',
      'scope',
      'is_deleted',
      'source',
      'barcode',
      'serving_id',
      'serving_label',
      'serving_amount',
      'serving_unit',
      'serving_amount_canonical',
      'serving_kind',
      ..._nutrients,
      'pack_amount',
      'pack_unit',
      'updated_at_utc',
    ];
    for (final Map<String, Object?> food in _rows(_data['foods'])) {
      final List<Map<String, Object?>> servings = _rows(food['serving_options'])
          .toList();
      final ({Object? amount, String? unit}) pack = _storedQuantity(
        food['pack_canonical'],
        food['pack_kind'],
        food['pack_unit'],
      );
      for (final Map<String, Object?> serving
          in servings.isEmpty ? <Map<String, Object?>>[{}] : servings) {
        final ({Object? amount, String? unit}) quantity = _storedQuantity(
          serving['amount_canonical'],
          serving['amount_kind'],
          serving['amount_unit'],
        );
        yield <Object?>[
          food['id'],
          food['name'],
          food['brand'],
          food['is_global'] == true
              ? 'referenced global definition'
              : 'household shared',
          food['is_deleted'],
          food['source'],
          food['barcode'],
          serving['id'],
          serving['label'],
          quantity.amount,
          quantity.unit,
          _number(serving['amount_canonical']),
          serving['amount_kind'],
          for (final String key in _nutrients) _number(serving[key]),
          pack.amount,
          pack.unit,
          food['updated_at'],
        ];
      }
    }
  }

  Iterable<MapEntry<String, String>> recipes() sync* {
    int index = 0;
    for (final Map<String, Object?> recipe in _rows(_data['recipes'])) {
      final String title = recipe['title']?.toString() ?? 'Untitled recipe';
      final StringBuffer text = StringBuffer()
        ..writeln(title)
        ..writeln()
        ..writeln('Recipe ID: ${recipe['id']}')
        ..writeln('Household shared recipe; captured at export.')
        ..writeln('Deleted: ${recipe['is_deleted'] ?? 'not recorded'}')
        ..writeln('Yield: ${recipe['servings']} servings')
        ..writeln(
          'Preparation seconds: ${recipe['prep_seconds'] ?? 'not recorded'}',
        )
        ..writeln(
          'Cooking seconds: ${recipe['cook_seconds'] ?? 'not recorded'}',
        )
        ..writeln('Cuisine: ${recipe['cuisine'] ?? 'not recorded'}')
        ..writeln('Source: ${recipe['source'] ?? 'not recorded'}')
        ..writeln(
          'Tags: ${(recipe['tags'] as List<Object?>? ?? <Object?>[]).join(', ')}',
        )
        ..writeln();
      for (final Map<String, Object?> section in _rows(recipe['sections'])) {
        text
          ..writeln(section['name'] ?? 'Ingredients and directions')
          ..writeln();
        for (final Map<String, Object?> ingredient in _rows(
          recipe['ingredients'],
        )) {
          if (ingredient['section_id'] != section['id']) continue;
          final ({Object? amount, String? unit}) quantity = _storedQuantity(
            ingredient['quantity_canonical'],
            ingredient['quantity_kind'],
            ingredient['quantity_unit'],
          );
          text.writeln(
            '- ${quantity.amount ?? ''} ${quantity.unit ?? ''} ${ingredient['name'] ?? ''}'
            '${ingredient['is_optional'] == true ? ' (optional)' : ''}'
            '${ingredient['prep_note'] == null ? '' : ' — ${ingredient['prep_note']}'}',
          );
          if (ingredient['raw_text'] case final String raw
              when raw.isNotEmpty) {
            text.writeln('  Original wording: $raw');
          }
        }
        text.writeln();
        for (final Map<String, Object?> step in _rows(recipe['steps'])) {
          if (step['section_id'] != section['id']) continue;
          text.writeln('${step['step_number']}. ${step['body'] ?? ''}');
          if (step['timer_seconds'] != null) {
            text.writeln('   Timer: ${step['timer_seconds']} seconds');
          }
        }
        text.writeln();
      }
      if (recipe['notes'] != null) {
        text
          ..writeln('Notes')
          ..writeln(recipe['notes'])
          ..writeln();
      }
      text.writeln(
        'The original JSON retains every recipe field and reference. Photos, when requested and available, are listed by recipe ID in archive-manifest.json.',
      );
      yield MapEntry<String, String>(
        'recipes/${safeArchiveStem(++index, title)}.txt',
        text.toString(),
      );
    }
  }

  String guide({
    required bool photosRequested,
    required int includedPhotos,
    required int unavailablePhotos,
  }) =>
      '''Hearth readable food-data archive

Captured: ${snapshot.capturedAt.toUtc().toIso8601String()}
Personal data for user: ${snapshot.userId}
Shared data for household: ${snapshot.householdId}

This is a readable local copy, not an import or restore feature and not proof of a complete cloud backup. Pending changes on this device: ${snapshot.pendingChanges}. This count is device-wide and may include work outside this export. Another device or the cloud may hold more data.

WHAT IS HERE
original/${snapshot.file.name} is byte-for-byte the existing versioned JSON export. Its manifest names section counts, missing local references and exclusions. Its statement that photos are excluded describes that JSON file; optional photo attachments in this ZIP are listed separately.
logs.csv contains locally present logged records. plans.csv contains locally present planned records (a record may be in both). Neither file is a daily total. is_deleted describes this local snapshot only. This app removes deleted plan entries from its cache; server tombstones and already-deleted meals are not recovered by this archive. A false value does not rule out a newer deletion on another device. "not recorded" means deletion evidence was unavailable, not active. Any true value marks a removed record and must not be counted as current intake. That alongside-JSON evidence was captured in the same database transaction.
targets.csv contains authored exact-week decisions, ongoing boundaries and explicit stops, not invented weekly copies. Exact-week records override ongoing decisions. Blank minor targets in a target set mean the app's Daily Value defaults; zero is an explicitly recorded zero. A stop has no targets.
foods.csv has one row per serving option, or an empty serving row for a food without one. These are definitions at export time, not historical logged nutrition. Household shared foods and referenced global definitions are labelled separately.
recipes/ contains readable recipe files, with recorded ingredient units, original wording, sections, directions and notes. Other sections, saved weeks, favourites, shopping data and any fields without a readable column remain in the original JSON.

READING LOGS HONESTLY
Logged names, portions and nutrition come only from the frozen snapshot, never today's food definition. Numeric nutrition is already for the whole logged portion. Blank means unknown or not recorded; it does not mean zero. Coverage states distinguish complete, partial, unknown and notRecorded. Partial is a known subtotal. Unsupported future coverage is notRecorded here and remains untouched in JSON.
entered_amount and entered_unit appear only when the saved portion evidence is valid for the frozen serving count. Legacy, stale or future evidence never invents grams or ounces. Nutrition-serving columns describe that recorded basis. Exact parsed numeric amounts are retained without display rounding. Blank approximate-package evidence means no qualifier was recorded; true retains the approximate claim.
For unlogged food plans, entry_servings counts the stored entry_serving_option_id, or the first serving when that reference is empty. planned_serving_basis says whether this reference was captured and can still be resolved. The planned serving label, amount and unit are definitions at export time, never a historical raw input amount. An unavailable selected serving is not replaced by the first serving. These extra serving references were captured alongside the unchanged JSON in the same transaction.
diary_date is a calendar date and must not be timezone-converted. logged_at_utc is an instant. snapshot_captured_at_as_recorded keeps the separate stored snapshot timestamp, including its original offset if present.

SPREADSHEETS
CSVs are UTF-8 with a byte-order mark, quoted fields and CRLF records. Formula-like text cells are prefixed with an apostrophe so titles, identifiers and notes cannot run spreadsheet formulas. The exact original text is retained in JSON. Numeric columns remain numbers, including explicit zeroes. Use a text column when importing identifiers or barcodes to preserve leading zeroes.

PHOTOS
Requested: $photosRequested
Included: $includedPhotos
Unavailable: $unavailablePhotos
${photosRequested ? 'photos-unavailable.csv and archive-manifest.json name every omission. Missing or offline photos do not remove the food-data export.' : 'Photos were not requested. No photo downloads were attempted.'}
Photos are captured recipe identities, not arbitrary source URLs. A local replacement that disappeared is not substituted with an older remote image.

LOCAL GAPS
${snapshot.missingReferences.isEmpty ? 'No missing local references were recorded.' : snapshot.missingReferences.join('\n')}
The global catalogue is not copied, apart from referenced definitions. Other people's plans, logs, targets, favourites and food profiles are excluded.
''';

  static const List<String> _nutrients = <String>[
    'kcal',
    'protein_g',
    'carb_g',
    'fat_g',
    'fiber_g',
    'sodium_mg',
    'cholesterol_mg',
  ];
  static num? _number(Object? value) =>
      value is num && value.isFinite ? value : null;
  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};
  static Iterable<Map<String, Object?>> _rows(Object? value) => value is List
      ? value.whereType<Map<String, Object?>>()
      : const <Map<String, Object?>>[];
  static ({Object? amount, String? unit}) _quantity(Quantity quantity) {
    final Unit unit =
        quantity.preferredUnit ?? Units.canonicalFor(quantity.kind);
    return (amount: quantity.amountIn(unit), unit: unit.label);
  }

  static ({Object? amount, String? unit}) _storedQuantity(
    Object? amount,
    Object? kind,
    Object? unitId,
  ) {
    final num? number = _number(amount);
    if (number == null) return (amount: null, unit: null);
    final Unit? preferred = unitId is String ? Units.byId(unitId) : null;
    if (preferred != null && preferred.kind.name == kind) {
      return (amount: number / preferred.toCanonical, unit: preferred.label);
    }
    final UnitKind? knownKind = UnitKind.values
        .where((UnitKind k) => k.name == kind)
        .firstOrNull;
    return (
      amount: number,
      unit: knownKind == null
          ? 'canonical ${kind ?? 'unit not recorded'}'
          : Units.canonicalFor(knownKind).label,
    );
  }
}

/// Indexes avoid collisions and platform-reserved names such as CON.
String safeArchiveStem(int index, String title) {
  final String stem = title
      .replaceAll(RegExp('[^a-zA-Z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final String short = stem.isEmpty
      ? 'recipe'
      : stem.substring(0, stem.length > 64 ? 64 : stem.length);
  return '${index.toString().padLeft(4, '0')}-$short';
}

Iterable<String> archiveCsv(Iterable<List<Object?>> rows) sync* {
  yield '\uFEFF';
  for (final List<Object?> row in rows) {
    yield '${row.map(_csvCell).join(',')}\r\n';
  }
}

String _csvCell(Object? value) {
  String text = value?.toString() ?? '';
  if (value is String && RegExp(r'^[\s\x00-\x20]*[=+@\-]').hasMatch(text)) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}
