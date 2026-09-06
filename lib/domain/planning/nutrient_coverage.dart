import 'package:meta/meta.dart';

import '../models/macros.dart';

/// How much of a total a nutrient's number actually speaks for (spec §5.6).
///
/// A subtotal looks the same however much of the meal it covers. Five grams
/// of fibre from a recipe whose every ingredient stated its fibre, and five
/// grams from one whose second ingredient never said, are the same number and
/// a different fact — and only one of them supports "you have had five grams".
///
/// This is deliberately not a count. A count invites arithmetic across
/// entries, and the honest thing to carry is weaker: whether anything was
/// missing, not how much.
enum MinorCoverage {
  /// Everything that contributed stated this nutrient.
  complete,

  /// Some of it did. The number is a floor, not a total.
  partial,

  /// Nothing did. There is no number, and a zero would be a claim.
  unknown,

  /// Frozen before coverage was recorded, so it cannot be established.
  ///
  /// Distinct from [unknown]: that one means everything was asked and none of
  /// it knew. This means nobody wrote down whether they asked. Old snapshots
  /// default here and never to [complete] — the whole point is that
  /// completeness has to be *earned*, and history that never recorded it
  /// cannot earn it retroactively (CLAUDE.md rule 3).
  notRecorded,
}

/// The three minor nutrients' coverage, carried together.
@immutable
class NutrientCoverage {
  const NutrientCoverage(this._byNutrient);

  /// What a frozen record says when it predates coverage entirely.
  const NutrientCoverage.notRecorded()
    : _byNutrient = const <MinorNutrient, MinorCoverage>{};

  /// One food's own answer: it stated a nutrient, or it did not.
  ///
  /// A single food is never [MinorCoverage.partial] — there is nothing for it
  /// to be partial *of*. Partial is what appears when several contributors are
  /// summed and they disagree about whether they know.
  factory NutrientCoverage.ofOne(Macros macros) =>
      NutrientCoverage(<MinorNutrient, MinorCoverage>{
        for (final MinorNutrient nutrient in MinorNutrient.values)
          nutrient: macros.knows(nutrient)
              ? MinorCoverage.complete
              : MinorCoverage.unknown,
      });

  /// Every nutrient unknown: asked, and nothing knew.
  ///
  /// Distinct from [NutrientCoverage.notRecorded], which absorbs a sum. This
  /// is an answer, so it combines like one.
  const NutrientCoverage.allUnknown()
    : _byNutrient = const <MinorNutrient, MinorCoverage>{
        MinorNutrient.fiber: MinorCoverage.unknown,
        MinorNutrient.sodium: MinorCoverage.unknown,
        MinorNutrient.cholesterol: MinorCoverage.unknown,
      };

  /// A stand-in contributor that knows nothing, used to make a sum partial.
  ///
  /// What a data gap adds: an ingredient nobody could cost is a hole in every
  /// nutrient at once, so summing this beside the ingredients that did resolve
  /// turns a complete total into the floor it really is.
  const NutrientCoverage.someUnknown() : this.allUnknown();

  final Map<MinorNutrient, MinorCoverage> _byNutrient;

  MinorCoverage of(MinorNutrient nutrient) =>
      _byNutrient[nutrient] ?? MinorCoverage.notRecorded;

  /// Coverage for a sum, given what each part covered.
  ///
  /// The rules are the ones a careful person would use out loud:
  ///
  ///  * everything complete → complete;
  ///  * nothing known at all → unknown, and the sum has no number either;
  ///  * anything missing beside anything known → **partial**, which is the
  ///    case this whole type exists for;
  ///  * any part that never recorded its coverage → the sum cannot claim more
  ///    than [MinorCoverage.notRecorded], because completeness it cannot see
  ///    is completeness it has not earned.
  static NutrientCoverage sum(Iterable<NutrientCoverage> parts) {
    final List<NutrientCoverage> all = parts.toList(growable: false);
    if (all.isEmpty) return const NutrientCoverage.notRecorded();

    return NutrientCoverage(<MinorNutrient, MinorCoverage>{
      for (final MinorNutrient nutrient in MinorNutrient.values)
        nutrient: _combine(<MinorCoverage>[
          for (final NutrientCoverage part in all) part.of(nutrient),
        ]),
    });
  }

  static MinorCoverage _combine(List<MinorCoverage> states) {
    if (states.contains(MinorCoverage.notRecorded)) {
      return MinorCoverage.notRecorded;
    }
    final bool anyKnown = states.any(
      (MinorCoverage s) =>
          s == MinorCoverage.complete || s == MinorCoverage.partial,
    );
    if (!anyKnown) return MinorCoverage.unknown;

    final bool allComplete = states.every(
      (MinorCoverage s) => s == MinorCoverage.complete,
    );
    return allComplete ? MinorCoverage.complete : MinorCoverage.partial;
  }

  /// Only the nutrients that have something to say, for storage. An empty map
  /// reads back as [MinorCoverage.notRecorded], which is what it means.
  Map<String, String> toJson() => <String, String>{
    for (final MapEntry<MinorNutrient, MinorCoverage> entry
        in _byNutrient.entries)
      entry.key.name: entry.value.name,
  };

  /// Tolerant by design: anything unreadable, absent, or from a newer writer
  /// than this reader understands is [MinorCoverage.notRecorded]. A snapshot
  /// is history, and history that fails to parse is worse than history that
  /// admits it does not know.
  factory NutrientCoverage.fromJson(Object? raw) {
    if (raw is! Map) return const NutrientCoverage.notRecorded();

    return NutrientCoverage(<MinorNutrient, MinorCoverage>{
      for (final MinorNutrient nutrient in MinorNutrient.values)
        if (_read(raw[nutrient.name]) case final MinorCoverage state)
          nutrient: state,
    });
  }

  static MinorCoverage? _read(Object? value) {
    for (final MinorCoverage state in MinorCoverage.values) {
      if (state.name == value) return state;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is NutrientCoverage &&
      MinorNutrient.values.every((MinorNutrient n) => other.of(n) == of(n));

  @override
  int get hashCode =>
      Object.hashAll(MinorNutrient.values.map(of).toList(growable: false));

  @override
  String toString() =>
      'NutrientCoverage(${MinorNutrient.values.map((MinorNutrient n) => '${n.name}: ${of(n).name}').join(', ')})';
}
