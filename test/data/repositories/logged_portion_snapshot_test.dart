import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/plan_store.dart';
import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

void main() {
  late HearthDatabase db;
  late PlanRepository repository;
  late PendingWriteStore queue;
  final DateTime recorded = DateTime.utc(2026, 9, 30, 12, 15);
  final DateTime originalDay = DateTime(2026, 9, 30);
  late DateTime clock;
  int nextId = 0;

  final ServingOption pot = ServingOption(
    id: 'pot',
    label: '170 g pot',
    amount: Quantity.of(170, Units.gram),
    macros: const Macros(kcal: 170, proteinG: 17, fiberG: 3, sodiumMg: 85),
  );
  LoggedPortion grams([double amount = 125]) => LoggedPortion.tryCapture(
    amount: amount,
    unit: const PortionUnit.raw(Units.gram),
    servings: amount / 170,
    standard: pot,
  )!;
  Future<MealPlanEntry> addPortion({LoggedPortion? evidence}) => repository.add(
    date: originalDay,
    slot: MealSlot.lunch,
    refType: PlanRefType.food,
    refId: 'yogurt',
    servingOptionId: pot.id,
    servings: (evidence ?? grams()).servings,
    loggedMacros: pot.macros,
    label: 'Original yogurt',
    loggedPortion: evidence ?? grams(),
    usesApproximatePackage: true,
    loggedCoverage: const NutrientCoverage(<MinorNutrient, MinorCoverage>{
      MinorNutrient.fiber: MinorCoverage.partial,
      MinorNutrient.sodium: MinorCoverage.complete,
      MinorNutrient.cholesterol: MinorCoverage.unknown,
    }),
  );
  MealPlanEntry replaceSnapshot(MealPlanEntry entry, MacroSnapshot snapshot) =>
      MealPlanEntry(
        id: entry.id,
        dayId: entry.dayId,
        slot: entry.slot,
        refType: entry.refType,
        refId: entry.refId,
        servings: snapshot.servings,
        servingOptionId: entry.servingOptionId,
        isPlanned: entry.isPlanned,
        isLogged: entry.isLogged,
        loggedAt: entry.loggedAt,
        macroSnapshot: snapshot,
      );
  Future<Map<String, Object?>> queuedSnapshot(String entryId) async =>
      (await queue.pending())
              .singleWhere((PendingWrite write) => write.entityId == entryId)
              .payload['macro_snapshot']!
          as Map<String, Object?>;

  setUp(() {
    nextId = 0;
    clock = recorded;
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    queue = PendingWriteStore(db);
    repository = PlanRepository(
      database: db,
      store: PlanStore(db),
      queue: queue,
      userId: 'user-1',
      clock: () => clock,
      idFactory: () => 'portion-${nextId++}',
    );
  });
  tearDown(() => db.close());

  test(
    'Move then correct retains the original snapshot capture time',
    () async {
      final MealPlanEntry original = await repository.add(
        date: originalDay,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'yogurt',
        servings: 1,
        loggedMacros: const Macros(kcal: 170),
        label: 'Original yogurt',
      );
      final MealPlanEntry moved = await repository.move(
        original,
        date: DateTime(2026, 9, 28),
        slot: MealSlot.breakfast,
      );
      expect(moved.loggedAt, isNot(recorded));
      final MealPlanEntry corrected = (await repository.logEntry(
        moved.id,
        liveMacros: const Macros(kcal: 170),
        label: 'Original yogurt',
        portion: 0.5,
        liveCoverage: const NutrientCoverage.notRecorded(),
      ))!;

      expect(corrected.macroSnapshot!.capturedAt, recorded);
      expect(corrected.loggedAt, moved.loggedAt);
      expect(corrected.macroSnapshot!.macros.kcal, 85);
    },
  );

  test(
    'new input survives local reload and the queued whole snapshot',
    () async {
      final MealPlanEntry original = await addPortion();
      final MealPlanEntry loaded = (await repository.entriesFor(originalDay))
          .single;
      expect(loaded.macroSnapshot, original.macroSnapshot);
      expect(loaded.macroSnapshot!.usableLoggedPortion!.enteredAmount, 125);
      expect(
        loaded.macroSnapshot!.usableLoggedPortion!.enteredUnit.id,
        'unit:g',
      );
      expect(loaded.macroSnapshot!.macros.kcal, closeTo(125, 1e-10));
      expect(
        (await queuedSnapshot(original.id))['logged_portion'],
        grams().toJson(),
      );
    },
  );

  test('correction ignores today\'s serving nutrition and keeps every frozen qualifier', () async {
    final MealPlanEntry original = await addPortion();
    final LoggedPortion half = original.macroSnapshot!.usableLoggedPortion!
        .corrected(amount: 62.5, unit: const PortionUnit.raw(Units.gram))!;
    clock = recorded.add(const Duration(days: 2));
    final MealPlanEntry corrected = (await repository.logEntry(
      original.id,
      liveMacros: const Macros(kcal: 900, fiberG: 99),
      label: 'Changed yogurt',
      portion: half.servings,
      liveCoverage: const NutrientCoverage.allComplete(),
      usesApproximatePackage: false,
      servingOptionId: 'changed-standard',
      loggedPortion: half,
    ))!;
    final MacroSnapshot snapshot = corrected.macroSnapshot!;
    expect(snapshot.macros, original.macroSnapshot!.macros.scaledBy(0.5));
    expect(snapshot.label, 'Original yogurt');
    expect(snapshot.coverage.of(MinorNutrient.fiber), MinorCoverage.partial);
    expect(
      snapshot.coverage.of(MinorNutrient.cholesterol),
      MinorCoverage.unknown,
    );
    expect(snapshot.macros.cholesterolMg, isNull);
    expect(snapshot.usesApproximatePackageNutrition, isTrue);
    expect(snapshot.capturedAt, recorded);
    expect(corrected.loggedAt!.isAtSameMomentAs(recorded), isTrue);
    expect(corrected.servingOptionId, pot.id);
    expect(snapshot.usableLoggedPortion!.enteredAmount, 62.5);
    expect(snapshot.usableLoggedPortion!.nutritionServing.amount, pot.amount);
    expect(
      (await repository.entriesFor(originalDay)).single.macroSnapshot,
      snapshot,
    );
  });

  test('Move, correct, delete and Undo preserve frozen evidence and unknown nested data', () async {
    final Map<String, Object?> raw = grams().toJson();
    raw['future_receipt'] = <String, Object?>{'source': 'scale'};
    (raw['conversion']! as Map<String, Object?>)['future_conversion'] = <int>[
      1,
      2,
    ];
    final MealPlanEntry original = await addPortion(
      evidence: LoggedPortion.fromJson(raw)!,
    );
    final MacroSnapshot enriched = PlanMapper.snapshotFromJson(
      jsonEncode(<String, Object?>{
        ...PlanMapper.snapshotToJson(original.macroSnapshot!),
        'future_snapshot': <String, Object?>{'confidence': 'measured'},
      }),
    )!;
    await repository.restore(replaceSnapshot(original, enriched));
    final DateTime destination = DateTime(2026, 9, 28);
    final MealPlanEntry moved = await repository.move(
      replaceSnapshot(original, enriched),
      date: destination,
      slot: MealSlot.breakfast,
    );
    final MealPlanEntry corrected = (await repository.logEntry(
      moved.id,
      liveMacros: const Macros(kcal: 900),
      label: 'Today',
      portion: grams().servings / 2,
      liveCoverage: const NutrientCoverage.allComplete(),
    ))!;
    await repository.removeEntry(corrected.id);
    await repository.restore(corrected);
    final MacroSnapshot back = (await repository.entriesFor(destination))
        .single
        .macroSnapshot!;
    expect(back, corrected.macroSnapshot);
    expect(back.capturedAt, recorded);
    expect(back.usableLoggedPortion!.enteredAmount, closeTo(62.5, 1e-12));
    expect(back.unreadFields['future_snapshot'], <String, Object?>{
      'confidence': 'measured',
    });
    final Map<String, Object?> output =
        (await queuedSnapshot(corrected.id))['logged_portion']!
            as Map<String, Object?>;
    expect(output['future_receipt'], <String, Object?>{'source': 'scale'});
    expect(
      (output['conversion']! as Map<String, Object?>)['future_conversion'],
      <int>[1, 2],
    );
  });

  test(
    'legacy corrections keep generic servings even if passed today\'s evidence',
    () async {
      final MealPlanEntry legacy = await repository.add(
        date: originalDay,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'yogurt',
        servings: 1,
        loggedMacros: const Macros(kcal: 170),
        label: 'Old yogurt',
      );
      final MealPlanEntry corrected = (await repository.logEntry(
        legacy.id,
        liveMacros: const Macros(kcal: 900),
        label: 'New yogurt',
        portion: grams().servings,
        loggedPortion: grams(),
        liveCoverage: const NutrientCoverage.allComplete(),
      ))!;
      expect(corrected.macroSnapshot!.usableLoggedPortion, isNull);
      expect(
        (await queuedSnapshot(legacy.id)).containsKey('logged_portion'),
        isFalse,
      );
      expect(corrected.macroSnapshot!.label, 'Old yogurt');
      expect(corrected.macroSnapshot!.macros.kcal, closeTo(125, 1e-10));
    },
  );

  test('zero calorie package correction uses saved equivalence without calorie division', () async {
    final ServingOption cup = ServingOption(
      id: 'cup',
      label: '1 cup',
      amount: Quantity.of(1, Units.cup),
      macros: const Macros(sodiumMg: 60),
    );
    final LoggedPortion evidence = LoggedPortion.tryCapture(
      amount: 30,
      unit: const PortionUnit.raw(Units.ounce),
      servings: 6,
      standard: cup,
    )!;
    final MealPlanEntry original = await repository.add(
      date: originalDay,
      slot: MealSlot.snack,
      refType: PlanRefType.food,
      refId: 'drink',
      servings: 6,
      servingOptionId: cup.id,
      loggedMacros: cup.macros,
      loggedPortion: evidence,
      label: 'Drink',
    );
    final LoggedPortion half = evidence.corrected(
      amount: 15,
      unit: const PortionUnit.raw(Units.ounce),
    )!;
    final MealPlanEntry corrected = (await repository.logEntry(
      original.id,
      liveMacros: const Macros(kcal: 500),
      label: 'New drink',
      portion: half.servings,
      loggedPortion: half,
      liveCoverage: const NutrientCoverage.allComplete(),
    ))!;
    expect(corrected.macroSnapshot!.macros.kcal, 0);
    expect(corrected.macroSnapshot!.macros.sodiumMg, 180);
    expect(corrected.macroSnapshot!.usableLoggedPortion!.enteredAmount, 15);
    expect(corrected.macroSnapshot!.servings, 3);
  });

  test(
    'Log again uses today\'s name and macros at the remembered serving count',
    () async {
      final MealPlanEntry original = await addPortion();
      final RecentLog recent = (await repository.recentLogs()).single;
      clock = recorded.add(const Duration(days: 1));
      final MealPlanEntry repeated = await repository.logAgain(
        recent: recent,
        date: originalDay.add(const Duration(days: 1)),
        slot: MealSlot.breakfast,
        liveMacros: const Macros(kcal: 340),
        label: 'Today\'s yogurt',
      );
      expect(repeated.id, isNot(original.id));
      expect(repeated.servings, original.servings);
      expect(repeated.macroSnapshot!.macros.kcal, closeTo(250, 1e-10));
      expect(repeated.macroSnapshot!.label, 'Today\'s yogurt');
      expect(repeated.macroSnapshot!.capturedAt, clock);
      expect(repeated.macroSnapshot!.loggedPortion, isNull);
      expect(
        (await queuedSnapshot(repeated.id)).containsKey('logged_portion'),
        isFalse,
      );
      expect(
        (await repository.entriesFor(originalDay)).single.macroSnapshot,
        original.macroSnapshot,
      );
    },
  );

  test('Log again can capture today\'s serving definition without copying old grams', () async {
    await addPortion();
    final RecentLog recent = (await repository.recentLogs()).single;
    final ServingOption changed = ServingOption(
      id: pot.id,
      label: '200 g pot',
      amount: Quantity.of(200, Units.gram),
      macros: const Macros(kcal: 340),
    );
    final LoggedPortion current = LoggedPortion.tryCapture(
      amount: recent.servings,
      unit: PortionUnit.serving(changed),
      servings: recent.servings,
      standard: changed,
    )!;
    final MealPlanEntry repeated = await repository.logAgain(
      recent: recent,
      date: originalDay,
      slot: MealSlot.snack,
      liveMacros: changed.macros,
      loggedPortion: current,
    );
    expect(
      repeated.macroSnapshot!.usableLoggedPortion!.enteredUnit.id,
      'serving:pot',
    );
    expect(
      repeated.macroSnapshot!.usableLoggedPortion!.enteredAmount,
      recent.servings,
    );
    expect(
      repeated.macroSnapshot!.usableLoggedPortion!.nutritionServing.amount,
      changed.amount,
    );
    expect(repeated.macroSnapshot!.macros.kcal, closeTo(250, 1e-10));
  });

  test(
    'unlog removes evidence and re-log captures a fresh current snapshot',
    () async {
      final MealPlanEntry original = await addPortion();
      final MealPlanEntry unlogged = (await repository.unlogEntry(
        original.id,
      ))!;
      expect(unlogged.macroSnapshot, isNull);
      expect(
        (await queue.pending())
            .singleWhere((PendingWrite write) => write.entityId == original.id)
            .payload['macro_snapshot'],
        isNull,
      );
      clock = recorded.add(const Duration(days: 1));
      final MealPlanEntry relogged = (await repository.logEntry(
        original.id,
        liveMacros: const Macros(kcal: 340),
        label: 'Current yogurt',
        portion: 1,
        loggedPortion: grams(170),
        liveCoverage: const NutrientCoverage.allComplete(),
        usesApproximatePackage: false,
      ))!;
      expect(relogged.macroSnapshot!.macros.kcal, 340);
      expect(relogged.macroSnapshot!.label, 'Current yogurt');
      expect(relogged.macroSnapshot!.capturedAt, clock);
      expect(
        relogged.macroSnapshot!.coverage,
        const NutrientCoverage.allComplete(),
      );
      expect(relogged.macroSnapshot!.usesApproximatePackageNutrition, isFalse);
      expect(relogged.macroSnapshot!.usableLoggedPortion!.enteredAmount, 170);
    },
  );

  test(
    'plans remain snapshot-null even when an optional receipt is supplied',
    () async {
      final MealPlanEntry planned = await repository.add(
        date: originalDay,
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'yogurt',
        servings: grams().servings,
        loggedPortion: grams(),
      );
      expect(planned.macroSnapshot, isNull);
      expect(
        (await repository.entriesFor(originalDay)).single.macroSnapshot,
        isNull,
      );
      expect(
        (await queue.pending())
            .singleWhere((PendingWrite write) => write.entityId == planned.id)
            .payload['macro_snapshot'],
        isNull,
      );
    },
  );
}
