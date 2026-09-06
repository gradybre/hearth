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
  const NutrientCoverage(
    this._byNutrient, [
    this._unread = const <String, Object?>{},
  ]);

  /// What a frozen record says when it predates coverage entirely.
  const NutrientCoverage.notRecorded()
    : _byNutrient = const <MinorNutrient, MinorCoverage>{},
      _unread = const <String, Object?>{};

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
      },
      _unread = const <String, Object?>{};

  /// Nothing was missing, because nothing was going to contribute.
  ///
  /// Vacuous, and deliberately so: a recipe of nothing but seasonings adds no
  /// nutrition, so it should neither claim knowledge nor take any away from
  /// the meals beside it.
  const NutrientCoverage.allComplete()
    : _byNutrient = const <MinorNutrient, MinorCoverage>{
        MinorNutrient.fiber: MinorCoverage.complete,
        MinorNutrient.sodium: MinorCoverage.complete,
        MinorNutrient.cholesterol: MinorCoverage.complete,
      },
      _unread = const <String, Object?>{};

  /// A stand-in contributor that knows nothing, used to make a sum partial.
  ///
  /// What a data gap adds: an ingredient nobody could cost is a hole in every
  /// nutrient at once, so summing this beside the ingredients that did resolve
  /// turns a complete total into the floor it really is.
  const NutrientCoverage.someUnknown() : this.allUnknown();

  final Map<MinorNutrient, MinorCoverage> _byNutrient;

  /// Sub-keys and vocabulary this version could not read, carried back out
  /// untouched. Never interpreted — only preserved.
  final Map<String, Object?> _unread;

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
  Map<String, Object?> toJson() => <String, Object?>{
    // What could not be read first, so anything this version does understand
    // wins over the copy it could not parse.
    ..._unread,
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

    return NutrientCoverage(
      <MinorNutrient, MinorCoverage>{
        for (final MinorNutrient nutrient in MinorNutrient.values)
          if (_read(raw[nutrient.name]) case final MinorCoverage state)
            nutrient: state,
      },
      // What this reader could not make sense of, kept so writing back cannot
      // erase it. Reading tolerantly and then rewriting `{}` would be a
      // slower way of destroying the same thing: a newer client saying
      // "estimated" for the fibre, plus a sodium this version *can* read,
      // would come back with both gone (§4).
      <String, Object?>{
        // Any key that is not one of this version's three, whatever its
        // value. Filtering on whether the *value* looked familiar dropped a
        // nutrient this version has never heard of whose state happened to be
        // a word it has — "potassium: partial" is not ours to read or to lose.
        for (final MapEntry<Object?, Object?> field in raw.entries)
          if (field.key case final String key)
            if (!_ownedKeys.contains(key)) key: field.value,
        // And our own three where the word is one we do not know.
        for (final MinorNutrient nutrient in MinorNutrient.values)
          if (raw.containsKey(nutrient.name) &&
              _read(raw[nutrient.name]) == null)
            nutrient.name: raw[nutrient.name],
      },
    );
  }

  /// The keys this version writes for itself.
  static final Set<String> _ownedKeys = <String>{
    for (final MinorNutrient nutrient in MinorNutrient.values) nutrient.name,
  };

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
