import '../models/food.dart';

/// The foods a person may choose to eat (spec §5.2).
///
/// One list, used everywhere a food is offered — the picker, the log sheet —
/// so the rule lives in a place that can be tested rather than in three
/// screens that have to remember it.
///
/// What it leaves out is a **modifier**: a menu row a restaurant publishes as
/// a deduction. Freddy's "Make any Sandwich a Lettuce Wrap" is −180 kcal, and
/// on its own it is not a meal — a day with one logged reads 180 calories
/// lighter than the day that happened, and once that is frozen into a log
/// snapshot nothing can correct it (CLAUDE.md rule 3). A modifier is chosen
/// only in the eat-out builder, and only after something real has been chosen
/// for it to apply to.
///
/// Deleted foods go too, for the older reason: they are kept so historical
/// logs keep resolving (spec §4), not so they can be logged again.
List<Food> eatableFoods(Iterable<Food> library) => <Food>[
  for (final Food food in library)
    if (!food.isDeleted && !food.isModifier) food,
];
