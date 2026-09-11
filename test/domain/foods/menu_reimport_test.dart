import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/menu_reimport.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// What importing a menu a second time would change (review N08).
///
/// Menu foods are keyed by restaurant, name, section *and portion*, so the
/// same document twice already updates rather than duplicates. What it could
/// not do was notice: a dish whose portion changed saved as a second food, a
/// dish dropped from the menu stayed for ever, and nothing said so.
void main() {
  const Macros bowl = Macros(kcal: 690, proteinG: 26, carbG: 78, fatG: 30);

  Food saved({
    required String id,
    String name = 'Harvest Bowl',
    String? section = 'Warm bowls',
    Macros macros = bowl,
    double amount = 1,
  }) => aFood(
    name,
    id: id,
    brand: 'Chopt',
    source: FoodSource.restaurant,
    menuGroup: section,
    servingOptions: <ServingOption>[
      aServing(id: '$id-s', amount: amount, unit: Units.item, macros: macros),
    ],
  );

  ({String id, String name, String? section, Macros macros}) row({
    required String id,
    String name = 'Harvest Bowl',
    String? section = 'Warm bowls',
    Macros macros = bowl,
  }) => (id: id, name: name, section: section, macros: macros);

  test('a dish that was not there is added', () {
    final MenuReimport diff = MenuReimport.compare(
      incoming: <({String id, String name, String? section, Macros macros})>[
        row(id: 'f-1'),
      ],
      existing: const <Food>[],
    );

    expect(diff.added, 1);
    expect(diff.stale, isEmpty);
    expect(diff.isNoOp, isFalse);
  });

  test('the same document twice changes nothing', () {
    final MenuReimport diff = MenuReimport.compare(
      incoming: <({String id, String name, String? section, Macros macros})>[
        row(id: 'f-1'),
      ],
      existing: <Food>[saved(id: 'f-1')],
    );

    expect(diff.unchanged, 1);
    expect(diff.isNoOp, isTrue);
  });

  test('new numbers on the same dish update it in place', () {
    // The id is the same, so every recipe and plan pointing at it follows.
    final MenuReimport diff = MenuReimport.compare(
      incoming: <({String id, String name, String? section, Macros macros})>[
        row(id: 'f-1', macros: const Macros(kcal: 710, proteinG: 27)),
      ],
      existing: <Food>[saved(id: 'f-1')],
    );

    expect(diff.updated, 1);
    expect(diff.stale, isEmpty, reason: 'nothing is left behind');
  });

  test('a changed portion leaves the old one behind, and says so', () {
    // The portion is in the id, so this cannot update in place. Left alone it
    // is exactly how a restaurant comes to have two of everything.
    final MenuReimport diff = MenuReimport.compare(
      incoming: <({String id, String name, String? section, Macros macros})>[
        row(id: 'f-2'),
      ],
      existing: <Food>[saved(id: 'f-1')],
    );

    expect(diff.reportioned, hasLength(1));
    expect(diff.reportioned.single.supersedes, 'f-1');
    expect(diff.stale, <String>['f-1']);
    expect(diff.added, 0, reason: 'it is the same dish, not a new one');
  });

  test('a dish the document does not mention is reported as missing', () {
    final MenuReimport diff = MenuReimport.compare(
      incoming: <({String id, String name, String? section, Macros macros})>[
        row(id: 'f-1'),
      ],
      existing: <Food>[
        saved(id: 'f-1'),
        saved(id: 'f-gone', name: 'Winter Bowl'),
      ],
    );

    expect(diff.missing, hasLength(1));
    expect(diff.missing.single.name, 'Winter Bowl');
    expect(diff.stale, <String>['f-gone']);
  });

  test('the same name in a different section is a different dish', () {
    // Chopt prints "Chicken" under warm bowls and under add-ons, and they are
    // not the same row.
    final MenuReimport diff = MenuReimport.compare(
      incoming: <({String id, String name, String? section, Macros macros})>[
        row(id: 'f-2', name: 'Chicken', section: 'Add-ons'),
      ],
      existing: <Food>[
        saved(id: 'f-1', name: 'Chicken', section: 'Warm bowls'),
      ],
    );

    expect(diff.added, 1);
    expect(diff.missing, hasLength(1));
    expect(diff.reportioned, isEmpty);
  });

  test('and spelling is normalised before any of that', () {
    final MenuReimport diff = MenuReimport.compare(
      incoming: <({String id, String name, String? section, Macros macros})>[
        row(id: 'f-2', name: 'harvest  bowl'),
      ],
      existing: <Food>[saved(id: 'f-1')],
    );

    expect(diff.reportioned, hasLength(1), reason: 'the same dish, respelled');
  });

  test('everything stale is offered together', () {
    final MenuReimport diff = MenuReimport.compare(
      incoming: <({String id, String name, String? section, Macros macros})>[
        row(id: 'f-2'),
      ],
      existing: <Food>[
        saved(id: 'f-1'),
        saved(id: 'f-gone', name: 'Winter Bowl'),
      ],
    );

    expect(diff.stale, containsAll(<String>['f-1', 'f-gone']));
    expect(diff.stale, hasLength(2));
  });
}
