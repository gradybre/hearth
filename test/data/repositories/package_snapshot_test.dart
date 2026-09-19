import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/data/mappers/sync_payload.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';

/// The approximate-package qualifier, frozen with the meal (spec R10, R12).
///
/// It has to travel with the numbers rather than be looked up later: the
/// relationship it came from can be re-reviewed, corrected or removed
/// tomorrow, and none of that may change what a meal eaten today says.
void main() {
  late HearthDatabase db;
  late PlanRepository repository;
  final DateTime clock = DateTime.utc(2026, 8, 27, 18, 30);
  final DateTime today = DateTime(2026, 8, 27);
  int nextId = 0;

  setUp(() {
    nextId = 0;
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    repository = PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: PendingWriteStore(db),
      userId: 'user-1',
      clock: () => clock,
      idFactory: () => 'id-${nextId++}',
    );
  });

  tearDown(() => db.close());

  Future<MealPlanEntry> logCheese({bool approximate = true}) => repository.add(
    date: today,
    slot: MealSlot.dinner,
    refType: PlanRefType.food,
    refId: 'food-cheese',
    servings: 6,
    loggedMacros: const Macros(kcal: 100, proteinG: 6),
    loggedCoverage: const NutrientCoverage.notRecorded(),
    usesApproximatePackage: approximate,
    label: 'Shredded cheddar',
  );

  group('logging', () {
    test('freezes the qualifier beside the macros', () async {
      final MealPlanEntry entry = await logCheese();

      expect(entry.macroSnapshot!.macros.kcal, 600);
      expect(entry.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
    });

    test('and an ordinary meal claims nothing', () async {
      final MealPlanEntry entry = await logCheese(approximate: false);
      expect(entry.macroSnapshot!.usesApproximatePackageNutrition, isFalse);
    });

    test('it survives a reload from the database', () async {
      await logCheese();
      final MealPlanEntry reloaded = (await repository.entriesFor(today))
          .single;

      expect(reloaded.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
    });

    test('correcting the portion later keeps it', () async {
      // The portion is a correction to this meal, not a new statement about
      // how it was costed — and scaling cannot make an approximate basis
      // exact.
      final MealPlanEntry entry = await logCheese();
      final MealPlanEntry? corrected = await repository.logEntry(
        entry.id,
        liveMacros: const Macros(kcal: 100, proteinG: 6),
        liveCoverage: const NutrientCoverage.notRecorded(),
        label: 'Shredded cheddar',
        portion: 3,
      );

      expect(corrected!.macroSnapshot!.macros.kcal, 300);
      expect(corrected.macroSnapshot!.usesApproximatePackageNutrition, isTrue);
    });
  });

  group('the serving a portion counts', () {
    test('is stored and read back', () async {
      final MealPlanEntry entry = await repository.add(
        date: today,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'food-cheese',
        servings: 6,
        servingOptionId: 'cup-b',
      );

      expect(entry.servingOptionId, 'cup-b');
      expect(
        (await repository.entriesFor(today)).single.servingOptionId,
        'cup-b',
      );
    });

    test('and survives being logged and corrected', () async {
      final MealPlanEntry entry = await repository.add(
        date: today,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'food-cheese',
        servings: 6,
        servingOptionId: 'cup-b',
      );
      final MealPlanEntry? logged = await repository.logEntry(
        entry.id,
        liveMacros: const Macros(kcal: 100, proteinG: 6),
        liveCoverage: const NutrientCoverage.notRecorded(),
        label: 'Shredded cheddar',
        portion: 3,
      );

      // Correcting a portion says nothing about which row it is in.
      expect(logged!.servingOptionId, 'cup-b');
      expect(logged.macroSnapshot!.macros.kcal, 300);
    });

    test('and an entry naming none says so explicitly on the wire', () async {
      final MealPlanEntry entry = await repository.add(
        date: today,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'food-cheese',
        servings: 1,
      );

      // '' rather than a missing key: a server preserves what it holds when
      // the column is absent, so a clear has to be said out loud.
      expect(
        PlanMapper.entryToJson(entry, updatedAt: clock)['serving_option_id'],
        '',
      );
    });

    test('and the empty sentinel reads back as none', () {
      expect(SyncPayload.servingOptionId(''), isNull);
      expect(SyncPayload.servingOptionId('cup-b'), 'cup-b');
      expect(PlanMapper.servingOptionIdFromSql(''), isNull);
      expect(PlanMapper.servingOptionIdFromSql('cup-b'), 'cup-b');
      // Omission is a different answer from a clear, and only the caller can
      // act on it.
      expect(
        SyncPayload.hasServingOptionId(const <String, Object?>{}),
        isFalse,
      );
      expect(
        SyncPayload.hasServingOptionId(<String, Object?>{
          'serving_option_id': '',
        }),
        isTrue,
      );
    });
  });

  group('stored JSON', () {
    MacroSnapshot snapshot({required bool approximate}) => MacroSnapshot(
      macros: const Macros(kcal: 600, proteinG: 36),
      servings: 6,
      capturedAt: clock,
      label: 'Shredded cheddar',
      usesApproximatePackageNutrition: approximate,
      unreadFields: const <String, Object?>{'from_a_newer_client': 1},
    );

    test('round-trips, unread fields and all', () {
      final MacroSnapshot original = snapshot(approximate: true);
      final MacroSnapshot? read = PlanMapper.snapshotFromJson(
        jsonEncode(PlanMapper.snapshotToJson(original)),
      );

      expect(read, original);
      expect(read!.usesApproximatePackageNutrition, isTrue);
      expect(read.unreadFields['from_a_newer_client'], 1);
    });

    test('an old snapshot without the key claims nothing', () {
      final MacroSnapshot? read = PlanMapper.snapshotFromJson(
        jsonEncode(<String, Object?>{
          'kcal': 600,
          'protein_g': 36,
          'servings': 6,
          'captured_at': clock.toIso8601String(),
          'label': 'Shredded cheddar',
        }),
      );

      expect(read!.usesApproximatePackageNutrition, isFalse);
      expect(
        read.unreadFields,
        isEmpty,
        reason: 'the new key is ours to write, not an unread one',
      );
    });
  });
}
