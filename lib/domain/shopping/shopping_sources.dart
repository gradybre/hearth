import 'package:meta/meta.dart';

import 'shopping_contribution.dart';
import 'shopping_line.dart';

/// One thing somebody put on the list, gathered back up from the lines it
/// scattered itself across (spec §5.7).
@immutable
class ShoppingSource {
  const ShoppingSource({
    required this.key,
    required this.kind,
    required this.label,
    required this.lines,
    this.servings,
  });

  /// The [ShoppingContribution.sourceKey] this stands for, and what
  /// `ShoppingRepository.removeSource` takes back off.
  final String key;

  final ShoppingSourceKind kind;

  /// What to call it — the contribution's own stored label, so a recipe that
  /// has since been renamed or deleted still says what it said when it was
  /// added.
  final String label;

  /// How many servings were asked for, where the question means anything.
  final double? servings;

  /// How many lines it is currently asking for something on.
  final int lines;
}

/// What is on the list, by what put it there.
abstract final class ShoppingSources {
  /// Every recipe, food and plan build still asking for something.
  ///
  /// In the order they first appear down the list, which is roughly the order
  /// they were added in — nothing better is recorded, and a set of buttons
  /// that reshuffles itself between openings is worse than an imperfect order.
  ///
  /// Typed-in items are deliberately absent. A manual line *is* the thing
  /// itself rather than a source behind it, and it comes off with the swipe
  /// every other line uses; offering a second way to remove one here would
  /// read as two different acts.
  static List<ShoppingSource> of(List<ShoppingLine> lines) {
    final Map<String, ShoppingSource> found = <String, ShoppingSource>{};

    for (final ShoppingLine line in lines) {
      final List<ShoppingContribution> asks = line.contributions.isEmpty
          ? ShoppingContributions.legacy(line)
          : line.contributions;

      for (final ShoppingContribution ask in asks) {
        if (ask.kind == ShoppingSourceKind.manual) continue;

        final ShoppingSource? was = found[ask.sourceKey];
        found[ask.sourceKey] = ShoppingSource(
          key: ask.sourceKey,
          kind: ask.kind,
          label: was?.label ?? ask.label ?? _nameFor(ask.kind),
          // Taken from the first line rather than summed across them. One add
          // of a four-serving recipe writes "four servings" onto every line it
          // touches — that is what a contribution records — so adding them up
          // would report a chilli with eight ingredients as thirty-two
          // servings. The asks are already summed *per line* when the same
          // recipe is added twice, which is where that arithmetic belongs.
          servings: was?.servings ?? ask.servings,
          lines: (was?.lines ?? 0) + 1,
        );
      }
    }

    return found.values.toList(growable: false);
  }

  /// What a source with no stored label of its own is called.
  ///
  /// Only the plan reaches this — it points at a week rather than at one
  /// thing — along with rows written before contributions existed, which
  /// `ShoppingContributions.legacy` reads as the plan's for the same reason.
  static String _nameFor(ShoppingSourceKind kind) => switch (kind) {
    ShoppingSourceKind.plan => 'The meal plan',
    ShoppingSourceKind.recipe => 'A recipe',
    ShoppingSourceKind.food => 'A food',
    ShoppingSourceKind.manual => 'Added by hand',
  };
}
