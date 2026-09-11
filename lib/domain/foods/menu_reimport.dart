import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../models/food.dart';
import '../models/macros.dart';
import '../text/text_normaliser.dart';

/// What a reimport would do to one menu row (review N08).
enum MenuChange {
  /// Not on the menu before.
  added,

  /// There already, saying the same thing. Saved again and unchanged.
  unchanged,

  /// There already, with different numbers. The food is updated in place,
  /// so every recipe and plan pointing at it follows.
  updated,

  /// The same dish at a different portion.
  ///
  /// A menu food's id carries its portion, so this cannot update in place —
  /// it saves as a second food and the old portion stays on the menu unless
  /// it is retired. Left alone, this is exactly how a restaurant comes to
  /// have two of everything.
  reportioned,

  /// On the menu before and not in this document at all.
  missing,
}

/// One row of a reimport, and what it would do.
@immutable
class MenuLineChange {
  const MenuLineChange({
    required this.name,
    required this.section,
    required this.change,
    this.foodId,
    this.supersedes,
  });

  final String name;
  final String? section;
  final MenuChange change;

  /// The food this row writes, when it writes one.
  final String? foodId;

  /// The food this row leaves behind at the old portion, if any.
  final String? supersedes;

  bool get isWrite => change != MenuChange.missing;
}

/// What a reimport of one restaurant's menu would change (review N08).
///
/// Menu foods are keyed by restaurant, name, section **and portion**, so
/// importing the same document twice already updates rather than duplicates.
/// What it cannot do is notice: a dish whose portion changed saves as a
/// second food, a dish dropped from the menu stays for ever, and nothing says
/// so. Review before commit is not only for what is written — it is for what
/// a write leaves behind (CLAUDE.md rule 4).
@immutable
class MenuReimport {
  const MenuReimport(this.lines);

  final List<MenuLineChange> lines;

  int _count(MenuChange change) =>
      lines.where((MenuLineChange l) => l.change == change).length;

  int get added => _count(MenuChange.added);
  int get unchanged => _count(MenuChange.unchanged);
  int get updated => _count(MenuChange.updated);

  /// Rows that would leave an old portion behind.
  List<MenuLineChange> get reportioned => <MenuLineChange>[
    for (final MenuLineChange l in lines)
      if (l.change == MenuChange.reportioned) l,
  ];

  /// Menu foods this document does not mention.
  List<MenuLineChange> get missing => <MenuLineChange>[
    for (final MenuLineChange l in lines)
      if (l.change == MenuChange.missing) l,
  ];

  /// Everything that would be left on the menu saying something the document
  /// does not — the old portions and the dropped dishes.
  ///
  /// These are what "review changes on reimport rather than duplicate a
  /// restaurant" is about: offered for retirement together, never retired
  /// without being shown.
  List<String> get stale => <String>[
    for (final MenuLineChange l in reportioned) l.supersedes!,
    for (final MenuLineChange l in missing) l.foodId!,
  ];

  /// True when this document says exactly what the menu already says.
  bool get isNoOp => added == 0 && updated == 0 && stale.isEmpty;

  /// Compares a parsed document against the menu already saved.
  ///
  /// [incoming] carries the id each row would save under, which the caller
  /// derives the same way the save does — so what the review promises and
  /// what the save performs cannot come apart.
  static MenuReimport compare({
    required List<({String id, String name, String? section, Macros macros})>
    incoming,
    required Iterable<Food> existing,
  }) {
    final Map<String, Food> byId = <String, Food>{
      for (final Food food in existing) food.id: food,
    };

    /// The same dish at whatever portion: name and section, normalised.
    String dish(String name, String? section) =>
        '${normaliseKey(name)}|${normaliseKey(section ?? '')}';

    final Map<String, Food> byDish = <String, Food>{
      for (final Food food in existing) dish(food.name, food.menuGroup): food,
    };

    final Set<String> seen = <String>{};
    final List<MenuLineChange> lines = <MenuLineChange>[];

    for (final ({String id, String name, String? section, Macros macros}) row
        in incoming) {
      final Food? sameId = byId[row.id];
      if (sameId != null) {
        seen.add(sameId.id);
        lines.add(
          MenuLineChange(
            name: row.name,
            section: row.section,
            foodId: row.id,
            change: _saysTheSame(sameId, row.macros)
                ? MenuChange.unchanged
                : MenuChange.updated,
          ),
        );
        continue;
      }

      final Food? sameDish = byDish[dish(row.name, row.section)];
      if (sameDish != null) {
        seen.add(sameDish.id);
        lines.add(
          MenuLineChange(
            name: row.name,
            section: row.section,
            foodId: row.id,
            change: MenuChange.reportioned,
            supersedes: sameDish.id,
          ),
        );
        continue;
      }

      lines.add(
        MenuLineChange(
          name: row.name,
          section: row.section,
          foodId: row.id,
          change: MenuChange.added,
        ),
      );
    }

    for (final Food food in existing) {
      if (seen.contains(food.id)) continue;
      lines.add(
        MenuLineChange(
          name: food.name,
          section: food.menuGroup,
          foodId: food.id,
          change: MenuChange.missing,
        ),
      );
    }

    return MenuReimport(lines);
  }

  /// Whether the saved food already says what the document says.
  ///
  /// Compared on the numbers rather than on everything: a menu food's name,
  /// section and portion are in its id, so two foods with one id differ only
  /// in what they claim to contain.
  static bool _saysTheSame(Food food, Macros incoming) {
    if (food.servingOptions.length != 1) return false;
    return food.servingOptions.single.macros == incoming;
  }
}

/// The id a menu row always gets.
///
/// Derived rather than random, which is what makes a retry safe: the loop
/// used to mint a fresh uuid per row, so pressing Save again after a
/// failure part way through inserted every already-saved row a second time.
/// Deriving it from what identifies the row on the menu means the second
/// attempt updates what the first one wrote.
///
/// The same pattern as `IngredientMatchStore.idFor` and `PlanStore.idFor`,
/// and for the same reason: two attempts at one fact should meet on one row.
/// The portion is part of it, and has to be. A menu that lists "Fries"
/// twice at two sizes is two foods, and a key on the name alone would
/// quietly keep the second and lose the first — a silent collapse that the
/// random ids this replaced could not produce.
String menuFoodId({
  required String restaurant,
  required String name,
  required String portion,
  String? section,
}) => const Uuid().v5(
  Namespace.url.value,
  'hearth:menu-food:${normaliseKey(restaurant)}:${normaliseKey(name)}:'
  '${normaliseKey(section ?? '')}:${normaliseKey(portion)}',
);
