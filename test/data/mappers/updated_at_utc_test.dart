import 'dart:io';

import 'package:hearth/data/mappers/food_mapper.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/data/mappers/recipe_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:test/test.dart';

/// What time a record says it was written (spec §7.1).
///
/// `updated_at` is the whole of last-write-wins and the whole of the pull
/// watermark, and it is compared against timestamps the *server* set. So it
/// has to be an instant, not a wall-clock reading with the zone left off.
///
/// `DateTime.toIso8601String()` on a **local** value emits no `Z`, and
/// Postgres reads a zoneless string in the session's zone — UTC. A device at
/// UTC−4 therefore stamps every record it creates four hours before it
/// happened. That is not a display problem: if the other device's watermark
/// has already passed that instant, the record is never pulled at all, and a
/// watermark only moves forward.
void main() {
  // 14:00 wherever this test runs. The bug is invisible at UTC+0, which is
  // one reason it survived.
  final DateTime localAfternoon = DateTime(2026, 9, 5, 14);

  /// Every `updated_at` a payload carries, however deeply nested.
  Iterable<String> stampsIn(Object? node) sync* {
    if (node is Map) {
      for (final MapEntry<Object?, Object?> entry in node.entries) {
        if (entry.key == 'updated_at' && entry.value is String) {
          yield entry.value! as String;
        }
        yield* stampsIn(entry.value);
      }
    } else if (node is List) {
      for (final Object? child in node) {
        yield* stampsIn(child);
      }
    }
  }

  void expectInstant(Object? payload, {required String what}) {
    final List<String> stamps = stampsIn(payload).toList();
    expect(stamps, isNotEmpty, reason: '$what carries no updated_at at all');

    for (final String stamp in stamps) {
      expect(
        stamp,
        endsWith('Z'),
        reason:
            '$what wrote "$stamp" — a wall-clock reading with no zone. '
            'Postgres reads that as UTC, so it lands '
            '${localAfternoon.timeZoneOffset.inHours.abs()} hours from when '
            'it happened, and a watermark already past it never asks again.',
      );
      expect(
        DateTime.parse(stamp).isAtSameMomentAs(localAfternoon),
        isTrue,
        reason: '$what moved the moment, not just its spelling',
      );
    }
  }

  test('a recipe says when it was really written', () {
    expectInstant(
      RecipeMapper.toJson(
        Recipe(
          id: 'r1',
          householdId: 'h1',
          title: 'Guard stew',
          servings: 2,
          sections: const <RecipeSection>[],
          updatedAt: localAfternoon,
        ),
        updatedAt: localAfternoon,
      ),
      what: 'RecipeMapper',
    );
  });

  test('and so does a food', () {
    expectInstant(
      FoodMapper.toJson(
        Food(
          id: 'f1',
          name: 'Oats',
          source: FoodSource.manual,
          servingOptions: const <ServingOption>[],
          updatedAt: localAfternoon,
        ),
        updatedAt: localAfternoon,
      ),
      what: 'FoodMapper',
    );
  });

  test('and a logged meal, whose stamp is also its history', () {
    expectInstant(
      PlanMapper.entryToJson(
        const MealPlanEntry(
          id: 'e1',
          dayId: 'd1',
          slot: MealSlot.dinner,
          refType: PlanRefType.food,
          refId: 'f1',
          servings: 1,
        ).log(
          liveMacros: const Macros(kcal: 100),
          at: localAfternoon,
          label: 'Oats',
          coverage: const NutrientCoverage.notRecorded(),
        ),
        updatedAt: localAfternoon,
      ),
      what: 'PlanMapper.entryToJson',
    );
  });

  test('and the mappers cannot quietly forget again', () {
    // A behaviour test can only cover the mappers it can construct. This one
    // covers the rest: every `updated_at` this app sends is serialised in
    // `lib/data`, and none of them may spell an instant without its zone.
    final List<String> offenders = <String>[];
    for (final FileSystemEntity file in Directory(
      'lib/data',
    ).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (!line.contains("'updated_at':")) continue;
        if (line.contains('toIso8601String()') &&
            !line.contains('toUtc().toIso8601String()')) {
          offenders.add('${file.path}:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A local DateTime serialises without a zone, and Postgres reads '
          'that in the session zone — so the record lands hours from when it '
          'happened and a watermark already past it never asks again:\n'
          '${offenders.join('\n')}',
    );
  });
}
