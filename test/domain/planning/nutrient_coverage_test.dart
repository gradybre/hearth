import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:test/test.dart';

/// How much of a total a nutrient's number speaks for (spec §5.6, R06).
///
/// Five grams of fibre from a recipe whose every ingredient stated its fibre,
/// and five grams from one whose second ingredient never said, are the same
/// number and a different fact. Only one of them supports "you have had five
/// grams of fibre today".
void main() {
  const NutrientCoverage nothingRecorded = NutrientCoverage.notRecorded();

  NutrientCoverage one({double? fiber, double? sodium}) =>
      NutrientCoverage.ofOne(
        Macros(kcal: 100, fiberG: fiber, sodiumMg: sodium),
      );

  group('what one food covers', () {
    test('a stated nutrient is complete and an unstated one is unknown', () {
      final NutrientCoverage coverage = one(fiber: 4);

      expect(coverage.of(MinorNutrient.fiber), MinorCoverage.complete);
      expect(coverage.of(MinorNutrient.sodium), MinorCoverage.unknown);
    });

    test('and a stated zero is complete, because it is an answer', () {
      // Water really does have no sodium. That is knowledge, not a gap.
      expect(one(sodium: 0).of(MinorNutrient.sodium), MinorCoverage.complete);
    });

    test(
      'but one food is never partial — there is nothing to be partial of',
      () {
        expect(
          one(fiber: 4).of(MinorNutrient.fiber),
          isNot(MinorCoverage.partial),
        );
      },
    );
  });

  group('what a sum covers', () {
    test('everything stated is complete', () {
      expect(
        NutrientCoverage.sum(<NutrientCoverage>[one(fiber: 4), one(fiber: 1)])
            .of(MinorNutrient.fiber),
        MinorCoverage.complete,
      );
    });

    test('something stated beside something silent is partial', () {
      // The case R06 is about: 5 g known, one ingredient that never said. The
      // number is a floor, and calling it a total is the lie.
      expect(
        NutrientCoverage.sum(<NutrientCoverage>[one(fiber: 5), one()])
            .of(MinorNutrient.fiber),
        MinorCoverage.partial,
      );
    });

    test('nothing stated at all is unknown, not zero', () {
      expect(
        NutrientCoverage.sum(<NutrientCoverage>[one(), one()])
            .of(MinorNutrient.fiber),
        MinorCoverage.unknown,
      );
    });

    test('and partial is contagious across a second sum', () {
      // A day is a sum of meals, each of which is a sum of ingredients.
      // Partway up that tree the qualification must not quietly drop off.
      final NutrientCoverage meal = NutrientCoverage.sum(<NutrientCoverage>[
        one(fiber: 5),
        one(),
      ]);
      final NutrientCoverage day = NutrientCoverage.sum(<NutrientCoverage>[
        meal,
        one(fiber: 2),
      ]);

      expect(day.of(MinorNutrient.fiber), MinorCoverage.partial);
    });

    test('nothing summed at all records nothing', () {
      expect(
        NutrientCoverage.sum(const <NutrientCoverage>[])
            .of(MinorNutrient.fiber),
        MinorCoverage.notRecorded,
      );
    });
  });

  group('history that never recorded coverage', () {
    test('reads as not recorded, never as complete', () {
      // The whole point: completeness has to be earned. A snapshot frozen
      // before this existed cannot earn it retroactively (rule 3).
      expect(
        nothingRecorded.of(MinorNutrient.fiber),
        MinorCoverage.notRecorded,
      );
    });

    test('and it poisons a sum rather than being ignored', () {
      // A day containing one old meal cannot claim its fibre is complete,
      // however well the newer meals are covered.
      expect(
        NutrientCoverage.sum(<NutrientCoverage>[one(fiber: 4), nothingRecorded])
            .of(MinorNutrient.fiber),
        MinorCoverage.notRecorded,
      );
    });
  });

  group('storage', () {
    test('round-trips what it knows', () {
      final NutrientCoverage coverage = NutrientCoverage.sum(<NutrientCoverage>[
        one(fiber: 5),
        one(),
      ]);

      final NutrientCoverage back = NutrientCoverage.fromJson(
        coverage.toJson(),
      );

      expect(back, coverage);
      expect(back.of(MinorNutrient.fiber), MinorCoverage.partial);
    });

    test('and an absent, malformed or unfamiliar record is not recorded', () {
      // Tolerant on purpose. A newer writer's vocabulary, a null, a string, a
      // truncated map — none of them may read as "complete".
      expect(NutrientCoverage.fromJson(null), nothingRecorded);
      expect(NutrientCoverage.fromJson('complete'), nothingRecorded);
      expect(
        NutrientCoverage.fromJson(<String, Object?>{'fiber': 'immaculate'}),
        nothingRecorded,
      );
      expect(
        NutrientCoverage.fromJson(<String, Object?>{'fiber': 'partial'})
            .of(MinorNutrient.sodium),
        MinorCoverage.notRecorded,
      );
    });
  });

  group('coverage a newer version wrote', () {
    test('survives a word this one does not know', () {
      // Reading tolerantly and then writing `{}` back would be a slower way
      // of destroying the same thing: the unreadable fibre *and* a sodium
      // this version can read would both be gone (§4).
      final NutrientCoverage read = NutrientCoverage.fromJson(<String, Object?>{
        'fiber': 'estimated',
        'sodium': 'complete',
      });

      expect(read.of(MinorNutrient.fiber), MinorCoverage.notRecorded);
      expect(read.of(MinorNutrient.sodium), MinorCoverage.complete);

      final Map<String, Object?> back = read.toJson();
      expect(back['fiber'], 'estimated', reason: 'not this version\'s to lose');
      expect(back['sodium'], 'complete');
    });

    test('and a sub-key it has never heard of', () {
      final Map<String, Object?> back = NutrientCoverage.fromJson(
        <String, Object?>{'sodium': 'complete', 'potassium': 'partial'},
      ).toJson();

      expect(back['potassium'], 'partial');
    });

    test('but what this version understands still wins', () {
      // Written after the carried keys, so a stale copy cannot shadow it.
      final NutrientCoverage summed = NutrientCoverage.sum(<NutrientCoverage>[
        NutrientCoverage.fromJson(<String, Object?>{'fiber': 'estimated'}),
        NutrientCoverage.ofOne(const Macros(kcal: 1, fiberG: 2)),
      ]);

      expect(summed.of(MinorNutrient.fiber), MinorCoverage.notRecorded);
    });
  });
}
