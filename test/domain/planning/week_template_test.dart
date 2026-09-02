import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/week_template.dart';

/// Saving a good week so you can have it again (spec §5.6).
void main() {
  MealPlanEntry entry({
    String id = 'e1',
    String dayId = 'day-1',
    MealSlot slot = MealSlot.dinner,
    String refId = 'recipe-1',
    double servings = 2,
    bool logged = false,
  }) => MealPlanEntry(
    id: id,
    dayId: dayId,
    slot: slot,
    refType: PlanRefType.recipe,
    refId: refId,
    servings: servings,
    isPlanned: !logged,
    isLogged: logged,
  );

  // A Monday and the Wednesday after it.
  final DateTime monday = DateTime(2026, 8, 31);
  final DateTime wednesday = DateTime(2026, 9, 2);

  group('reducing a week', () {
    test('a meal is placed by weekday, never by date', () {
      // A date would pin the template to the week it was saved from.
      final List<TemplateEntry> out = WeekTemplate.from(
        <DateTime, List<MealPlanEntry>>{
          wednesday: <MealPlanEntry>[entry()],
        },
      );

      expect(out.single.weekday, DateTime.wednesday);
      expect(out.single.refId, 'recipe-1');
      expect(out.single.servings, 2);
    });

    test('meals you already ate come across as intentions', () {
      // A week worth saving is usually one you have eaten. Dropping the logged
      // ones would save an empty template.
      final List<TemplateEntry> out = WeekTemplate.from(
        <DateTime, List<MealPlanEntry>>{
          monday: <MealPlanEntry>[entry(logged: true)],
        },
      );

      expect(out, hasLength(1));
    });

    test('two of the same lunch is a real thing to have planned', () {
      final List<TemplateEntry> out = WeekTemplate.from(
        <DateTime, List<MealPlanEntry>>{
          monday: <MealPlanEntry>[
            entry(id: 'a', slot: MealSlot.lunch),
            entry(id: 'b', slot: MealSlot.lunch),
          ],
        },
      );

      expect(out, hasLength(2));
    });

    test('and it comes out in the order a week is read', () {
      final List<TemplateEntry> out = WeekTemplate.from(
        <DateTime, List<MealPlanEntry>>{
          wednesday: <MealPlanEntry>[entry(id: 'c', slot: MealSlot.dinner)],
          monday: <MealPlanEntry>[
            entry(id: 'b', slot: MealSlot.lunch),
            entry(id: 'a', slot: MealSlot.breakfast),
          ],
        },
      );

      expect(
        out.map((TemplateEntry e) => (e.weekday, e.slot)),
        <(int, MealSlot)>[
          (DateTime.monday, MealSlot.breakfast),
          (DateTime.monday, MealSlot.lunch),
          (DateTime.wednesday, MealSlot.dinner),
        ],
      );
    });
  });

  group('applying it to a week', () {
    WeekTemplate template(List<TemplateEntry> entries) =>
        WeekTemplate(id: 't1', name: 'A good week', entries: entries);

    test('a Wednesday meal lands on the next week\'s Wednesday', () {
      final WeekTemplate saved = template(<TemplateEntry>[
        const TemplateEntry(
          weekday: DateTime.wednesday,
          slot: MealSlot.dinner,
          refType: PlanRefType.recipe,
          refId: 'recipe-1',
          servings: 2,
        ),
      ]);

      final List<({DateTime date, TemplateEntry entry})> placed = saved
          .onWeekOf(DateTime(2026, 9, 10));

      expect(placed.single.date, DateTime(2026, 9, 9));
      expect(placed.single.date.weekday, DateTime.wednesday);
    });

    test('the week is Monday-first, whichever day you ask from', () {
      // Asking from a Sunday must not land the template on the week after.
      final WeekTemplate saved = template(<TemplateEntry>[
        const TemplateEntry(
          weekday: DateTime.monday,
          slot: MealSlot.breakfast,
          refType: PlanRefType.recipe,
          refId: 'r',
          servings: 1,
        ),
      ]);

      for (final DateTime anyDay in <DateTime>[
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 10),
        DateTime(2026, 9, 13),
      ]) {
        expect(saved.onWeekOf(anyDay).single.date, DateTime(2026, 9, 7));
      }
    });
  });

  group('storing it', () {
    test('round-trips', () {
      final List<TemplateEntry> entries = WeekTemplate.from(
        <DateTime, List<MealPlanEntry>>{
          monday: <MealPlanEntry>[entry(servings: 1.5)],
        },
      );
      final WeekTemplate saved = WeekTemplate(
        id: 't1',
        name: 'A good week',
        entries: entries,
      );

      final List<TemplateEntry> back = WeekTemplate.decodeEntries(
        saved.encodeEntries(),
      );

      expect(back, hasLength(1));
      expect(back.single.weekday, DateTime.monday);
      expect(back.single.servings, 1.5);
      expect(back.single.slot, MealSlot.dinner);
    });

    test('one unreadable meal loses that meal, not the week', () {
      // Tolerance, because the alternative is an unopenable template.
      final List<TemplateEntry> back = WeekTemplate.decodeEntries('''
        [
          {"weekday": 1, "slot": "dinner", "ref_type": "recipe",
           "ref_id": "r1", "servings": 2},
          {"weekday": 99, "slot": "dinner", "ref_type": "recipe",
           "ref_id": "r2", "servings": 2},
          {"weekday": 2, "slot": "brunch", "ref_type": "recipe",
           "ref_id": "r3", "servings": 2},
          {"weekday": 3, "slot": "dinner", "ref_type": "recipe",
           "ref_id": "", "servings": 2}
        ]
      ''');

      expect(back.map((TemplateEntry e) => e.refId), <String>['r1']);
    });

    test('nonsense decodes to nothing rather than throwing', () {
      expect(WeekTemplate.decodeEntries(''), isEmpty);
      expect(WeekTemplate.decodeEntries('{}'), isEmpty);
    });
  });
}
