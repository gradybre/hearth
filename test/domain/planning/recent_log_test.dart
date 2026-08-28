import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/recent_log.dart';
import 'package:test/test.dart';

MealPlanEntry logged({
  required String id,
  required String refId,
  PlanRefType refType = PlanRefType.food,
  required DateTime at,
  double servings = 1,
  String label = 'Thing',
  double kcal = 100,
}) =>
    MealPlanEntry(
      id: id,
      dayId: 'day-1',
      slot: MealSlot.lunch,
      refType: refType,
      refId: refId,
      servings: servings,
    ).log(
      liveMacros: Macros(kcal: kcal),
      at: at,
      label: label,
    );

MealPlanEntry planned({required String id, required String refId}) =>
    MealPlanEntry(
      id: id,
      dayId: 'day-1',
      slot: MealSlot.lunch,
      refType: PlanRefType.food,
      refId: refId,
      servings: 1,
    );

void main() {
  final DateTime monday = DateTime.utc(2026, 8, 24, 12);
  final DateTime tuesday = DateTime.utc(2026, 8, 25, 12);
  final DateTime wednesday = DateTime.utc(2026, 8, 26, 12);

  group('collapsing to one row per thing', () {
    test('the same food logged repeatedly is a single row', () {
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        logged(id: 'a', refId: 'food-1', at: monday),
        logged(id: 'b', refId: 'food-1', at: tuesday),
        logged(id: 'c', refId: 'food-1', at: wednesday),
      ]);

      expect(recents, hasLength(1));
      expect(recents.single.timesLogged, 3);
    });

    test('a food and a recipe sharing an id are different things', () {
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        logged(id: 'a', refId: 'same-id', at: monday),
        logged(
          id: 'b',
          refId: 'same-id',
          refType: PlanRefType.recipe,
          at: tuesday,
        ),
      ]);
      expect(recents, hasLength(2));
    });

    test('planned entries never appear', () {
      // Recents is a list of things you have eaten, not things you meant to.
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        planned(id: 'a', refId: 'food-1'),
        logged(id: 'b', refId: 'food-2', at: monday),
      ]);

      expect(recents, hasLength(1));
      expect(recents.single.refId, 'food-2');
    });
  });

  group('what a one-tap repeat reuses', () {
    test('the most recent portion, not the first', () {
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        logged(id: 'a', refId: 'food-1', at: monday, servings: 1),
        logged(id: 'b', refId: 'food-1', at: wednesday, servings: 2.5),
      ]);
      expect(recents.single.servings, 2.5);
    });

    test('the most recent label, so a rename is reflected', () {
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        logged(id: 'a', refId: 'food-1', at: monday, label: 'Old name'),
        logged(id: 'b', refId: 'food-1', at: wednesday, label: 'New name'),
      ]);
      expect(recents.single.label, 'New name');
    });

    test('order of arrival does not matter', () {
      // Entries come back in insertion order, which is not necessarily log
      // order once a day has been edited.
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        logged(id: 'b', refId: 'food-1', at: wednesday, servings: 2.5),
        logged(id: 'a', refId: 'food-1', at: monday, servings: 1),
      ]);
      expect(recents.single.servings, 2.5);
      expect(recents.single.lastLoggedAt, wednesday);
    });
  });

  group('ordering', () {
    test('most recently logged first', () {
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        logged(id: 'a', refId: 'food-old', at: monday),
        logged(id: 'b', refId: 'food-new', at: wednesday),
        logged(id: 'c', refId: 'food-mid', at: tuesday),
      ]);

      expect(recents.map((RecentLog r) => r.refId), <String>[
        'food-new',
        'food-mid',
        'food-old',
      ]);
    });

    test('frequency is reported but does not reorder the list', () {
      // A ranking that reshuffles itself is worse than a predictable one you
      // can build muscle memory against.
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        logged(id: 'a', refId: 'often', at: monday),
        logged(id: 'b', refId: 'often', at: monday),
        logged(id: 'c', refId: 'often', at: monday),
        logged(id: 'd', refId: 'once', at: wednesday),
      ]);

      expect(recents.first.refId, 'once');
      expect(recents.last.timesLogged, 3);
    });

    test('the list is capped', () {
      final List<RecentLog> recents = RecentLogs.from(<MealPlanEntry>[
        for (int i = 0; i < 20; i++)
          logged(
            id: 'e$i',
            refId: 'food-$i',
            at: monday.add(Duration(minutes: i)),
          ),
      ], limit: 5);

      expect(recents, hasLength(5));
      // The five most recent, not the first five seen.
      expect(recents.first.refId, 'food-19');
    });
  });

  test('an empty history produces an empty list', () {
    expect(RecentLogs.from(const <MealPlanEntry>[]), isEmpty);
  });
}
