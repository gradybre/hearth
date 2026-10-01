import 'dart:convert';

import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// What a frozen log entry remembers (spec §5.6, CLAUDE.md rule 3).
///
/// A snapshot is the whole of an entry's history: once logged, an entry
/// answers from this and never from the food again. So anything the writer
/// leaves out is not merely absent from the display — it is gone, and rule 3
/// forbids going back to put it in.
void main() {
  final MacroSnapshot logged = MacroSnapshot(
    macros: const Macros(
      kcal: 380,
      proteinG: 24,
      carbG: 30,
      fatG: 12,
      fiberG: 4,
      sodiumMg: 870,
      cholesterolMg: 70,
    ),
    servings: 1,
    capturedAt: DateTime.utc(2026, 9, 4, 19),
    label: 'Single Steakburger',
  );

  MacroSnapshot roundTrip(MacroSnapshot snapshot) =>
      PlanMapper.snapshotFromJson(
        jsonEncode(PlanMapper.snapshotToJson(snapshot)),
      )!;

  test('the minor three survive being logged', () {
    // Dropped here, they are unknown for ever on every day already logged —
    // which is every day, which is why the bars never appeared.
    final MacroSnapshot back = roundTrip(logged);

    expect(back.macros.fiberG, 4);
    expect(back.macros.sodiumMg, 870);
    expect(back.macros.cholesterolMg, 70);
  });

  test('and unknown still comes back unknown, not zero', () {
    // The distinction the whole of §5.6 rests on, at the one seam where it is
    // written to disk. A 0 here would be a claim the food never made.
    final MacroSnapshot back = roundTrip(
      MacroSnapshot(
        macros: const Macros(kcal: 90, fiberG: 2),
        servings: 1,
        capturedAt: DateTime.utc(2026, 9, 4, 19),
        label: 'Yogurt',
      ),
    );

    expect(back.macros.fiberG, 2);
    expect(back.macros.sodiumMg, isNull);
    expect(back.macros.cholesterolMg, isNull);
  });

  test('and the four still come back as before', () {
    final MacroSnapshot back = roundTrip(logged);

    expect(back.macros.kcal, 380);
    expect(back.macros.fatG, 12);
    expect(back.servings, 1);
    expect(back.label, 'Single Steakburger');
  });

  group('a field a newer version wrote', () {
    test('survives being read and written by this one', () {
      // Sync and export pass the stored JSON across verbatim, but a local
      // edit — a portion change, a drag to another slot — reads the row into
      // the domain and writes it back. Without somewhere to put them, that
      // round trip would silently delete a newer client's record of a frozen
      // meal, permanently and for both people (§4).
      final Map<String, Object?> fromTheFuture = <String, Object?>{
        'kcal': 380.0,
        'protein_g': 12.0,
        'carb_g': 60.0,
        'fat_g': 6.0,
        'servings': 1.0,
        'captured_at': '2026-09-05T08:00:00.000Z',
        'label': 'Porridge',
        'confidence': 'measured',
        'weighed_grams': 240,
      };

      final Map<String, Object?> back = PlanMapper.snapshotToJson(
        PlanMapper.snapshotFromJson(jsonEncode(fromTheFuture))!,
      );

      expect(back['confidence'], 'measured');
      expect(back['weighed_grams'], 240);
      // And nothing this version does understand was disturbed.
      expect(back['kcal'], 380.0);
      expect(back['label'], 'Porridge');
    });

    test('and cannot shadow a field this version owns', () {
      // Carried first so a stale copy of a known key loses to the real one.
      final MacroSnapshot snapshot = PlanMapper.snapshotFromJson(
        jsonEncode(<String, Object?>{
          'kcal': 100.0,
          'servings': 1.0,
          'captured_at': '2026-09-05T08:00:00.000Z',
          'label': 'Guard',
        }),
      )!;

      expect(PlanMapper.snapshotToJson(snapshot)['kcal'], 100.0);
    });
  });

  group('frozen entered portions', () {
    final LoggedPortion portion = LoggedPortion.tryCapture(
      amount: 125,
      unit: const PortionUnit.raw(Units.gram),
      servings: 125 / 170,
      standard: ServingOption(
        id: 'pot',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 170),
      ),
    )!;
    MacroSnapshot snapshotWith(Object? evidence, {double? count}) =>
        PlanMapper.snapshotFromJson(
          jsonEncode(<String, Object?>{
            ...PlanMapper.snapshotToJson(logged),
            'servings': count ?? portion.servings,
            'logged_portion': evidence,
            'future_snapshot': <String, Object?>{'keep': true},
          }),
        )!;
    MacroSnapshot correct(MacroSnapshot snapshot, double count) =>
        MealPlanEntry(
              id: 'entry',
              dayId: 'day',
              slot: MealSlot.lunch,
              refType: PlanRefType.food,
              refId: 'food',
              servings: snapshot.servings,
              isLogged: true,
              loggedAt: snapshot.capturedAt,
              macroSnapshot: snapshot,
            )
            .log(
              liveMacros: const Macros(kcal: 999),
              at: DateTime.utc(2026, 10, 1),
              label: 'Today',
              portion: count,
              coverage: const NutrientCoverage.allComplete(),
            )
            .macroSnapshot!;

    test('a new receipt survives JSON with exact amount and no duplicate opaque key', () {
      final MacroSnapshot saved = snapshotWith(portion.toJson());
      final MacroSnapshot back = roundTrip(saved);
      expect(back, saved);
      expect(back.hashCode, saved.hashCode);
      expect(back.usableLoggedPortion!.enteredAmount, 125);
      expect(back.usableLoggedPortion!.enteredUnit.id, 'unit:g');
      expect(back.unreadFields.containsKey('logged_portion'), isFalse);
    });

    test('legacy snapshots do not gain an amount or an optional JSON key', () {
      final MacroSnapshot back = roundTrip(logged);
      expect(back.usableLoggedPortion, isNull);
      expect(
        PlanMapper.snapshotToJson(back).containsKey('logged_portion'),
        isFalse,
      );
    });

    test(
      'unsupported and malformed evidence stays opaque through correction',
      () {
        final List<Object?> values = <Object?>[
          <String, Object?>{
            ...portion.toJson(),
            'version': 99,
            'future': <int>[1, 2],
          },
          <String, Object?>{...portion.toJson(), 'entered_amount': '125'},
          <String, Object?>{...portion.toJson(), 'associated_servings': 99},
          <String, Object?>{...portion.toJson(), 'conversion': null},
          <String, Object?>{...portion.toJson(), 'invalidated': true},
          <Object?>['unexpected', 42],
          'unreadable',
          null,
        ];
        for (final Object? raw in values) {
          final MacroSnapshot saved = snapshotWith(raw);
          expect(saved.usableLoggedPortion, isNull);
          final MacroSnapshot corrected = roundTrip(correct(saved, 0.5));
          expect(corrected.usableLoggedPortion, isNull);
          expect(PlanMapper.snapshotToJson(corrected)['logged_portion'], raw);
          expect(corrected.unreadFields['future_snapshot'], <String, Object?>{
            'keep': true,
          });
        }
      },
    );

    test('nested future evidence survives a recognized amount correction', () {
      final Map<String, Object?> raw = portion.toJson();
      raw['future'] = <String, Object?>{'source': 'scale'};
      (raw['conversion']! as Map<String, Object?>)['future_ratio'] = <int>[
        1,
        2,
      ];
      final MacroSnapshot corrected = roundTrip(
        correct(snapshotWith(raw), 0.5),
      );
      expect(corrected.usableLoggedPortion!.enteredAmount, closeTo(85, 1e-12));
      final Map<String, Object?> output =
          PlanMapper.snapshotToJson(corrected)['logged_portion']!
              as Map<String, Object?>;
      expect(output['future'], <String, Object?>{'source': 'scale'});
      expect(
        (output['conversion']! as Map<String, Object?>)['future_ratio'],
        <int>[1, 2],
      );
      expect(output['associated_servings'], 0.5);
    });

    test('an older client count mismatch never regains a guessed amount after correction', () {
      final Map<String, Object?> raw = portion.toJson();
      raw['future'] = 'retained';
      final MacroSnapshot stale = snapshotWith(raw, count: 2);
      expect(stale.loggedPortion, isNotNull);
      expect(stale.usableLoggedPortion, isNull);
      expect(
        PlanMapper.snapshotToJson(roundTrip(stale))['logged_portion'],
        raw,
      );

      final MacroSnapshot corrected = roundTrip(
        correct(stale, portion.servings),
      );
      expect(corrected.usableLoggedPortion, isNull);
      final Map<String, Object?> output =
          PlanMapper.snapshotToJson(corrected)['logged_portion']!
              as Map<String, Object?>;
      expect(output, <String, Object?>{...raw, 'invalidated': true});
      expect(roundTrip(correct(corrected, 1)).usableLoggedPortion, isNull);
    });
  });
}
