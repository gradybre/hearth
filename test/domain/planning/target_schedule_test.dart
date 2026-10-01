import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/planning/target_schedule.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:test/test.dart';

const MacroTargets firstTargets = MacroTargets(
  kcal: 2100.5,
  proteinG: 145.25,
  carbG: 250.75,
  fatG: 67.5,
  fiberG: 31.5,
  sodiumMg: 1900.25,
  cholesterolMg: 225.75,
);

const MacroTargets changedTargets = MacroTargets(
  kcal: 2200,
  proteinG: 150,
  carbG: 275,
  fatG: 65,
  fiberG: 0,
  sodiumMg: null,
  cholesterolMg: 0,
);

const MacroTargets exceptionTargets = MacroTargets(
  kcal: 2000,
  proteinG: 125,
  carbG: 225,
  fatG: 70,
);

void main() {
  final DateTime firstMonday = DateTime(2026, 9, 21);
  final DateTime currentMonday = DateTime(2026, 9, 28);

  ExactWeekTarget exact(
    DateTime date, {
    String userId = 'alice',
    MacroTargets targets = exceptionTargets,
  }) => ExactWeekTarget(userId: userId, weekStart: date, targets: targets);

  OngoingTargetBoundary active(
    DateTime date, {
    String userId = 'alice',
    MacroTargets targets = firstTargets,
  }) => OngoingTargetBoundary.active(
    userId: userId,
    weekStart: date,
    targets: targets,
  );

  OngoingTargetBoundary stopped(DateTime date, {String userId = 'alice'}) =>
      OngoingTargetBoundary.stopped(userId: userId, weekStart: date);

  ResolvedTargets resolve(
    DateTime date, {
    String userId = 'alice',
    Iterable<ExactWeekTarget> exactWeeks = const <ExactWeekTarget>[],
    Iterable<OngoingTargetBoundary> boundaries =
        const <OngoingTargetBoundary>[],
  }) => resolveTargetsForWeek(
    userId: userId,
    date: date,
    exactWeeks: exactWeeks,
    boundaries: boundaries,
  );

  group('target schedule records', () {
    test('normalizes every record to its Monday calendar date', () {
      final DateTime sunday = DateTime(2026, 10, 4, 23, 59);

      expect(exact(sunday).weekStart, currentMonday);
      expect(active(sunday).weekStart, currentMonday);
      expect(stopped(sunday).weekStart, currentMonday);
    });

    test('an explicit stop is distinct from seven zero targets', () {
      const MacroTargets zeros = MacroTargets(
        kcal: 0,
        proteinG: 0,
        carbG: 0,
        fatG: 0,
        fiberG: 0,
        sodiumMg: 0,
        cholesterolMg: 0,
      );
      final OngoingTargetBoundary zeroBoundary = active(
        currentMonday,
        targets: zeros,
      );

      expect(zeroBoundary.isStopped, isFalse);
      expect(zeroBoundary.targets, same(zeros));
      expect(stopped(currentMonday).isStopped, isTrue);
      expect(stopped(currentMonday).targets, isNull);
      expect(
        resolve(
          currentMonday,
          boundaries: <OngoingTargetBoundary>[zeroBoundary],
        ).source,
        TargetSource.ongoing,
      );
    });
  });

  group('effective dates and exact-week priority', () {
    test('an empty schedule has no targets or implicit nutrition defaults', () {
      final ResolvedTargets result = resolve(DateTime(2026, 10, 1, 12));

      expect(result.userId, 'alice');
      expect(result.weekStart, currentMonday);
      expect(result.source, TargetSource.none);
      expect(result.targets, isNull);
      expect(result.ongoingBoundary, isNull);
    });

    test('an old exact-week row never silently becomes ongoing', () {
      final List<ExactWeekTarget> rows = <ExactWeekTarget>[exact(firstMonday)];

      final ResolvedTargets original = resolve(firstMonday, exactWeeks: rows);
      expect(original.source, TargetSource.exactWeek);
      expect(original.targets, same(exceptionTargets));
      expect(original.ongoingBoundary, isNull);
      expect(resolve(currentMonday, exactWeeks: rows).targets, isNull);
      expect(
        resolve(currentMonday, exactWeeks: rows).source,
        TargetSource.none,
      );
    });

    test('ongoing targets start on Monday and do not fill earlier weeks', () {
      final OngoingTargetBoundary start = active(currentMonday);
      final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
        start,
      ];

      expect(
        resolve(DateTime(2026, 9, 27, 23, 59), boundaries: boundaries).targets,
        isNull,
      );
      for (final DateTime date in <DateTime>[
        currentMonday,
        DateTime(2026, 10, 4, 23, 59),
        DateTime(2027, 6, 7),
      ]) {
        final ResolvedTargets result = resolve(date, boundaries: boundaries);
        expect(result.source, TargetSource.ongoing);
        expect(result.targets, same(firstTargets));
        expect(result.ongoingBoundary, same(start));
      }
    });

    test('uses the latest eligible boundary regardless of input order', () {
      final OngoingTargetBoundary first = active(firstMonday);
      final OngoingTargetBoundary change = active(
        currentMonday,
        targets: changedTargets,
      );
      final OngoingTargetBoundary future = active(
        DateTime(2026, 10, 12),
        targets: exceptionTargets,
      );
      final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
        future,
        first,
        change,
      ];

      expect(
        resolve(firstMonday, boundaries: boundaries).targets,
        same(firstTargets),
      );
      expect(
        resolve(currentMonday, boundaries: boundaries).targets,
        same(changedTargets),
      );
      expect(
        resolve(DateTime(2026, 10, 11), boundaries: boundaries).targets,
        same(changedTargets),
      );
      expect(
        resolve(DateTime(2026, 10, 12), boundaries: boundaries).targets,
        same(exceptionTargets),
      );
      expect(
        resolve(currentMonday, boundaries: boundaries.reversed).targets,
        same(changedTargets),
      );
    });

    test('a weekly exception wins and ongoing targets resume afterwards', () {
      final OngoingTargetBoundary start = active(firstMonday);
      final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
        start,
      ];
      final List<ExactWeekTarget> weeks = <ExactWeekTarget>[
        exact(currentMonday),
      ];

      final ResolvedTargets result = resolve(
        DateTime(2026, 10, 1),
        exactWeeks: weeks,
        boundaries: boundaries,
      );
      expect(result.source, TargetSource.exactWeek);
      expect(result.targets, same(exceptionTargets));
      expect(result.ongoingBoundary, same(start));
      expect(
        resolve(
          DateTime(2026, 10, 5),
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        same(firstTargets),
      );
    });

    test('an existing exact week wins even when an ongoing change starts', () {
      final OngoingTargetBoundary change = active(
        currentMonday,
        targets: changedTargets,
      );
      final ResolvedTargets result = resolve(
        currentMonday,
        exactWeeks: <ExactWeekTarget>[exact(currentMonday)],
        boundaries: <OngoingTargetBoundary>[active(firstMonday), change],
      );

      expect(result.source, TargetSource.exactWeek);
      expect(result.targets, same(exceptionTargets));
      expect(result.ongoingBoundary, same(change));
    });

    test('past and future week exceptions never revise the ongoing set', () {
      final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
        active(firstMonday),
      ];
      final List<ExactWeekTarget> weeks = <ExactWeekTarget>[
        exact(DateTime(2026, 9, 14)),
        exact(DateTime(2026, 10, 12), targets: changedTargets),
      ];

      expect(
        resolve(
          DateTime(2026, 9, 14),
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        same(exceptionTargets),
      );
      expect(
        resolve(
          currentMonday,
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        same(firstTargets),
      );
      expect(
        resolve(
          DateTime(2026, 10, 12),
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        same(changedTargets),
      );
      expect(
        resolve(
          DateTime(2026, 10, 19),
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        same(firstTargets),
      );
    });

    test('later changes and stops leave every earlier answer unchanged', () {
      final List<OngoingTargetBoundary> original = <OngoingTargetBoundary>[
        active(firstMonday),
      ];
      final List<OngoingTargetBoundary> revised = <OngoingTargetBoundary>[
        ...original,
        active(currentMonday, targets: changedTargets),
        stopped(DateTime(2026, 10, 5)),
        active(DateTime(2026, 10, 19), targets: exceptionTargets),
      ];

      for (final DateTime date in <DateTime>[
        DateTime(2026, 9, 14),
        firstMonday,
        DateTime(2026, 9, 27, 23, 59),
      ]) {
        final ResolvedTargets before = resolve(date, boundaries: original);
        final ResolvedTargets after = resolve(date, boundaries: revised);
        expect(after.targets, before.targets);
        expect(after.source, before.source);
        expect(after.ongoingBoundary, same(before.ongoingBoundary));
      }
    });

    test('the source describes the saved intent even when values match', () {
      final ResolvedTargets result = resolve(
        currentMonday,
        exactWeeks: <ExactWeekTarget>[
          exact(currentMonday, targets: firstTargets),
        ],
        boundaries: <OngoingTargetBoundary>[active(firstMonday)],
      );

      expect(result.source, TargetSource.exactWeek);
    });
  });

  group('stopping and restarting', () {
    test('a stop does not fall back to an older active boundary', () {
      final OngoingTargetBoundary stop = stopped(currentMonday);
      final ResolvedTargets result = resolve(
        DateTime(2026, 10, 5),
        boundaries: <OngoingTargetBoundary>[stop, active(firstMonday)],
      );

      expect(result.source, TargetSource.none);
      expect(result.targets, isNull);
      expect(result.ongoingBoundary, same(stop));
    });

    test(
      'stop keeps the preserved week and future exceptions, then restart',
      () {
        final OngoingTargetBoundary stop = stopped(currentMonday);
        final OngoingTargetBoundary restart = active(
          DateTime(2026, 10, 26),
          targets: changedTargets,
        );
        // The repository preserves the current values as an exact-week row
        // while writing the stop. Already saved future exceptions stay put.
        final List<ExactWeekTarget> weeks = <ExactWeekTarget>[
          exact(currentMonday, targets: firstTargets),
          exact(DateTime(2026, 10, 12)),
        ];
        final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
          active(firstMonday),
          stop,
          restart,
        ];

        final ResolvedTargets preserved = resolve(
          DateTime(2026, 10, 4),
          exactWeeks: weeks,
          boundaries: boundaries,
        );
        expect(preserved.source, TargetSource.exactWeek);
        expect(preserved.targets, same(firstTargets));
        expect(preserved.ongoingBoundary, same(stop));
        for (final DateTime gap in <DateTime>[
          DateTime(2026, 10, 5),
          DateTime(2026, 10, 19),
        ]) {
          final ResolvedTargets result = resolve(
            gap,
            exactWeeks: weeks,
            boundaries: boundaries,
          );
          expect(result.source, TargetSource.none);
          expect(result.targets, isNull);
          expect(result.ongoingBoundary, same(stop));
        }
        final ResolvedTargets futureException = resolve(
          DateTime(2026, 10, 12),
          exactWeeks: weeks,
          boundaries: boundaries,
        );
        expect(futureException.source, TargetSource.exactWeek);
        expect(futureException.targets, same(exceptionTargets));
        expect(futureException.ongoingBoundary, same(stop));
        for (final DateTime resumed in <DateTime>[
          DateTime(2026, 10, 26),
          DateTime(2026, 11, 2),
        ]) {
          final ResolvedTargets result = resolve(
            resumed,
            exactWeeks: weeks,
            boundaries: boundaries,
          );
          expect(result.source, TargetSource.ongoing);
          expect(result.targets, same(changedTargets));
          expect(result.ongoingBoundary, same(restart));
        }
        expect(
          resolve(
            firstMonday,
            exactWeeks: weeks,
            boundaries: boundaries,
          ).targets,
          same(firstTargets),
        );
      },
    );
  });

  group('personal scope and unique keys', () {
    test('one schedule can contain the same weeks for different users', () {
      final List<ExactWeekTarget> weeks = <ExactWeekTarget>[
        exact(currentMonday),
        exact(currentMonday, userId: 'bob', targets: changedTargets),
      ];
      final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
        active(firstMonday),
        active(firstMonday, userId: 'bob', targets: exceptionTargets),
        stopped(currentMonday),
      ];

      expect(
        resolve(
          currentMonday,
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        same(exceptionTargets),
      );
      expect(
        resolve(
          currentMonday,
          userId: 'bob',
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        same(changedTargets),
      );
      expect(
        resolve(
          DateTime(2026, 10, 5),
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        isNull,
      );
      expect(
        resolve(
          DateTime(2026, 10, 5),
          userId: 'bob',
          exactWeeks: weeks,
          boundaries: boundaries,
        ).targets,
        same(exceptionTargets),
      );
    });

    test('another user supplies neither an exact match nor an ongoing set', () {
      final ResolvedTargets result = resolve(
        currentMonday,
        exactWeeks: <ExactWeekTarget>[exact(currentMonday, userId: 'bob')],
        boundaries: <OngoingTargetBoundary>[active(firstMonday, userId: 'bob')],
      );

      expect(result.source, TargetSource.none);
      expect(result.targets, isNull);
      expect(result.ongoingBoundary, isNull);
    });

    test('duplicate rows belonging to another user are ignored first', () {
      final ResolvedTargets result = resolve(
        currentMonday,
        exactWeeks: <ExactWeekTarget>[
          exact(currentMonday, userId: 'bob'),
          exact(currentMonday, userId: 'bob', targets: changedTargets),
        ],
        boundaries: <OngoingTargetBoundary>[
          active(firstMonday),
          active(firstMonday, userId: 'bob'),
          stopped(firstMonday, userId: 'bob'),
        ],
      );

      expect(result.targets, same(firstTargets));
      expect(result.source, TargetSource.ongoing);
    });

    test('conflicting exact rows in one normalized week fail explicitly', () {
      final List<ExactWeekTarget> weeks = <ExactWeekTarget>[
        exact(currentMonday),
        exact(DateTime(2026, 10, 1, 12), targets: changedTargets),
      ];

      expect(() => resolve(currentMonday, exactWeeks: weeks), throwsStateError);
      expect(
        () => resolve(currentMonday, exactWeeks: weeks.reversed),
        throwsStateError,
      );
    });

    test('conflicting boundaries in one normalized week fail explicitly', () {
      final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
        active(firstMonday),
        stopped(DateTime(2026, 9, 25, 12)),
      ];

      expect(
        () => resolve(currentMonday, boundaries: boundaries),
        throwsStateError,
      );
      expect(
        () => resolve(currentMonday, boundaries: boundaries.reversed),
        throwsStateError,
      );
    });

    test('even identical duplicate keys expose a broken storage invariant', () {
      final OngoingTargetBoundary boundary = active(firstMonday);
      final ExactWeekTarget week = exact(currentMonday);

      expect(
        () => resolve(currentMonday, exactWeeks: <ExactWeekTarget>[week, week]),
        throwsStateError,
      );
      expect(
        () => resolve(
          currentMonday,
          boundaries: <OngoingTargetBoundary>[boundary, boundary],
        ),
        throwsStateError,
      );
    });

    test('later duplicate records cannot invalidate a historical answer', () {
      final ResolvedTargets result = resolve(
        firstMonday,
        exactWeeks: <ExactWeekTarget>[
          exact(currentMonday),
          exact(currentMonday, targets: changedTargets),
        ],
        boundaries: <OngoingTargetBoundary>[
          active(firstMonday),
          active(currentMonday),
          stopped(currentMonday),
        ],
      );

      expect(result.source, TargetSource.ongoing);
      expect(result.targets, same(firstTargets));
    });
  });

  group('calendar boundaries', () {
    test('a Sunday and New Year remain in the preceding Monday week', () {
      final OngoingTargetBoundary previous = active(DateTime(2026, 12, 28));
      final OngoingTargetBoundary next = active(
        DateTime(2027, 1, 4),
        targets: changedTargets,
      );
      final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
        next,
        previous,
      ];

      for (final DateTime date in <DateTime>[
        DateTime(2027, 1, 1, 12),
        DateTime(2027, 1, 3, 23, 59),
      ]) {
        final ResolvedTargets result = resolve(date, boundaries: boundaries);
        expect(result.weekStart, DateTime(2026, 12, 28));
        expect(result.targets, same(firstTargets));
      }
      final ResolvedTargets monday = resolve(
        DateTime(2027, 1, 4),
        boundaries: boundaries,
      );
      expect(monday.weekStart, DateTime(2027, 1, 4));
      expect(monday.targets, same(changedTargets));
    });

    test('UTC date-only inputs keep their calendar date when normalized', () {
      final OngoingTargetBoundary boundary = active(DateTime.utc(2026, 9, 28));
      final ResolvedTargets result = resolve(
        DateTime.utc(2026, 9, 28),
        boundaries: <OngoingTargetBoundary>[boundary],
      );

      expect(boundary.weekStart, currentMonday);
      expect(result.weekStart, currentMonday);
      expect(result.targets, same(firstTargets));
    });

    for (final ({DateTime sunday, DateTime monday}) transition
        in <({DateTime sunday, DateTime monday})>[
          (sunday: DateTime(2026, 3, 8, 23, 59), monday: DateTime(2026, 3, 9)),
          (
            sunday: DateTime(2026, 11, 1, 23, 59),
            monday: DateTime(2026, 11, 2),
          ),
        ]) {
      test('DST Sunday ${transition.sunday.month} stays in its own week', () {
        final DateTime previousMonday = startOfWeek(transition.sunday);
        final List<OngoingTargetBoundary> boundaries = <OngoingTargetBoundary>[
          active(previousMonday),
          active(transition.monday, targets: changedTargets),
        ];

        final ResolvedTargets sunday = resolve(
          transition.sunday,
          boundaries: boundaries,
        );
        expect(sunday.weekStart, previousMonday);
        expect(sunday.targets, same(firstTargets));
        final ResolvedTargets monday = resolve(
          transition.monday,
          boundaries: boundaries,
        );
        expect(monday.weekStart, transition.monday);
        expect(monday.targets, same(changedTargets));
        expect(exact(transition.sunday).weekStart, previousMonday);
        expect(stopped(transition.sunday).weekStart, previousMonday);
      });
    }
  });

  group('value preservation and reads', () {
    test('all seven authored values keep their precision', () {
      final ResolvedTargets result = resolve(
        currentMonday,
        boundaries: <OngoingTargetBoundary>[active(firstMonday)],
      );

      expect(result.targets, same(firstTargets));
      expect(result.targets!.kcal, 2100.5);
      expect(result.targets!.proteinG, 145.25);
      expect(result.targets!.carbG, 250.75);
      expect(result.targets!.fatG, 67.5);
      expect(result.targets!.fiberG, 31.5);
      expect(result.targets!.sodiumMg, 1900.25);
      expect(result.targets!.cholesterolMg, 225.75);
    });

    test('each optional nutrient preserves null and explicit zero', () {
      for (final double? optional in <double?>[null, 0]) {
        final MacroTargets authored = MacroTargets(
          kcal: 1800,
          proteinG: 100,
          carbG: 200,
          fatG: 60,
          fiberG: optional,
          sodiumMg: optional,
          cholesterolMg: optional,
        );
        for (final bool override in <bool>[false, true]) {
          final ResolvedTargets result = resolve(
            currentMonday,
            exactWeeks: <ExactWeekTarget>[
              if (override) exact(currentMonday, targets: authored),
            ],
            boundaries: <OngoingTargetBoundary>[
              active(firstMonday, targets: override ? firstTargets : authored),
            ],
          );

          expect(result.targets, same(authored));
          expect(result.targets!.fiberG, optional);
          expect(result.targets!.sodiumMg, optional);
          expect(result.targets!.cholesterolMg, optional);
        }
      }
    });

    test(
      'a year of reads never adds weekly copies or reorders the schedule',
      () {
        final List<ExactWeekTarget> weeks = List<ExactWeekTarget>.unmodifiable(
          <ExactWeekTarget>[exact(currentMonday)],
        );
        final OngoingTargetBoundary last = active(
          DateTime(2027, 1, 4),
          targets: changedTargets,
        );
        final OngoingTargetBoundary first = active(firstMonday);
        final List<OngoingTargetBoundary> boundaries =
            List<OngoingTargetBoundary>.unmodifiable(<OngoingTargetBoundary>[
              last,
              first,
            ]);

        for (int week = 0; week < 53; week++) {
          resolve(
            addDays(firstMonday, 7 * week),
            exactWeeks: weeks,
            boundaries: boundaries,
          );
        }

        expect(weeks, hasLength(1));
        expect(weeks.single.weekStart, currentMonday);
        expect(boundaries, <OngoingTargetBoundary>[last, first]);
      },
    );
  });
}
