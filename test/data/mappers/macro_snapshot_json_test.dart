import 'dart:convert';

import 'package:hearth/data/mappers/plan_mapper.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
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
}
