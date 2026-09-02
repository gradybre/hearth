import 'shopping_line.dart';

/// Rebuilding a list without throwing away what was done to it (spec §5.7).
///
/// A rebuild happens whenever the plan or the date range changes, which is
/// often — so this decides whether the Rebuild button is one you press freely
/// or one you learn to be afraid of. Everything the plan decided is replaced;
/// everything a person decided survives.
///
/// Survives, keyed by [ShoppingLine.key]:
///
///  * **the tick and the on-hand amount** — you did not stop having the beef
///    because you added a Thursday dinner;
///  * **an edited quantity** — rounding 1.5 lb up to a whole packet is a
///    decision about how beef is sold, which no change to the plan revisits;
///  * **the order** — the route round the shop is not the plan's business;
///  * **manual items, absolutely** — the plan never put them here, so the plan
///    does not get a vote on removing them.
///
/// Replaced: what the recipes call for. That number is the plan's to own, and
/// it keeps updating underneath an edit so the screen can show both and let
/// the difference be seen rather than silently resolved.
abstract final class ShoppingListMerge {
  /// [existing] as it is now, brought up to date with [rebuilt].
  static List<ShoppingLine> into(
    List<ShoppingLine> existing,
    List<ShoppingLine> rebuilt,
  ) {
    final Map<String, ShoppingLine> byKey = <String, ShoppingLine>{
      for (final ShoppingLine line in rebuilt) line.key: line,
    };
    final Set<String> seen = <String>{};
    final List<ShoppingLine> merged = <ShoppingLine>[];

    for (final ShoppingLine line in existing) {
      seen.add(line.key);
      final ShoppingLine? now = byKey[line.key];

      if (now == null) {
        // The plan no longer calls for it. Dropped — unless somebody has
        // touched it, in which case the touch is the reason to keep it: a
        // ticked line is a note that you have the thing, and an edited one is
        // a decision that outlived the recipe that prompted it.
        if (line.isManual || line.isChecked || line.isEdited) merged.add(line);
        continue;
      }

      merged.add(
        line.copyWith(
          // The plan's half of the line, refreshed.
          planned: now.planned,
          hasUnquantified: now.hasUnquantified,
          sourceRecipeIds: now.sourceRecipeIds,
          // Where the food or its store tag has since been filled in.
          foodId: now.foodId,
          storeTag: now.storeTag ?? line.storeTag,
        ),
      );
    }

    // Anything the plan has newly asked for goes to the end of the list, where
    // new things belong until they are put somewhere.
    int next = merged.fold<int>(
      0,
      (int m, ShoppingLine l) => l.sortOrder > m ? l.sortOrder : m,
    );
    for (final ShoppingLine line in rebuilt) {
      if (seen.contains(line.key)) continue;
      merged.add(line.copyWith(sortOrder: ++next));
    }

    return merged;
  }

  /// A fresh list given the order of the last one.
  ///
  /// Without this, an order arranged once evaporates with the list it was
  /// arranged on, and nobody drags anything a second time — which would make
  /// the whole idea of ordering by hand not worth having. Items the previous
  /// list never saw go to the end.
  ///
  /// Only the order carries. Ticks and on-hand amounts deliberately do not:
  /// Hearth cannot see what was eaten between one shop and the next, and a
  /// stale "you already have this" is how something gets left off a list.
  static List<ShoppingLine> ordered(
    List<ShoppingLine> lines,
    List<ShoppingLine> previous,
  ) {
    final Map<String, int> before = <String, int>{
      for (final ShoppingLine line in previous) line.key: line.sortOrder,
    };
    int next = before.values.fold<int>(0, (int m, int o) => o > m ? o : m);

    return <ShoppingLine>[
      for (final ShoppingLine line in lines)
        line.copyWith(sortOrder: before[line.key] ?? ++next),
    ];
  }

  /// The list as the screen shows it: by store, then by the order you put them
  /// in, then by name so two unplaced items do not swap about between builds.
  ///
  /// Untagged foods come last under their own heading rather than first —
  /// most foods have no store tag yet, and a long "Anywhere" group at the top
  /// would bury the shops that are actually organised.
  static List<ShoppingLine> display(List<ShoppingLine> lines) {
    final List<ShoppingLine> sorted = <ShoppingLine>[...lines];
    sorted.sort((ShoppingLine a, ShoppingLine b) {
      final String storeA = a.storeTag ?? '';
      final String storeB = b.storeTag ?? '';
      if (storeA != storeB) {
        if (storeA.isEmpty) return 1;
        if (storeB.isEmpty) return -1;
        return storeA.compareTo(storeB);
      }
      final int byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }
}
