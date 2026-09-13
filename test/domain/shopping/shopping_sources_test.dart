import 'package:hearth/domain/shopping/shopping_contribution.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/shopping/shopping_sources.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// What is on the list, gathered back up by what put it there (spec §5.7).
void main() {
  ShoppingContribution ask(
    ShoppingSourceKind kind, {
    String? refId,
    String? label,
    double? servings,
    double pounds = 1,
  }) => ShoppingContribution(
    kind: kind,
    refId: refId,
    label: label,
    servings: servings,
    quantities: <Quantity>[Quantity.of(pounds, Units.pound)],
  );

  ShoppingLine line(
    String name, {
    List<ShoppingContribution> contributions = const <ShoppingContribution>[],
    bool manual = false,
    List<Quantity> planned = const <Quantity>[],
  }) => ShoppingContributions.settle(
    ShoppingLine(key: name, name: name, planned: planned, isManual: manual),
    contributions: contributions,
  );

  ShoppingContribution chilli({double servings = 4}) => ask(
    ShoppingSourceKind.recipe,
    refId: 'r-chilli',
    label: 'Weeknight chilli',
    servings: servings,
  );

  test('a recipe across several lines is one thing to take off', () {
    final List<ShoppingSource> sources = ShoppingSources.of(<ShoppingLine>[
      line('ground beef', contributions: <ShoppingContribution>[chilli()]),
      line('kidney beans', contributions: <ShoppingContribution>[chilli()]),
      line('onion', contributions: <ShoppingContribution>[chilli()]),
    ]);

    expect(sources, hasLength(1));
    expect(sources.single.key, 'recipe:r-chilli');
    expect(sources.single.label, 'Weeknight chilli');
    expect(sources.single.lines, 3);
  });

  test('and its servings are not added up across them', () {
    // The number a contribution carries is what the *add* asked for, written
    // onto every line it touched. Summing it would report a chilli with eight
    // ingredients as thirty-two servings — a plausible-looking number that is
    // wrong by the length of the recipe.
    final List<ShoppingSource> sources = ShoppingSources.of(<ShoppingLine>[
      line('ground beef', contributions: <ShoppingContribution>[chilli()]),
      line('kidney beans', contributions: <ShoppingContribution>[chilli()]),
    ]);

    expect(sources.single.servings, 4);
  });

  test('the plan is a source too, named rather than left blank', () {
    final List<ShoppingSource> sources = ShoppingSources.of(<ShoppingLine>[
      line(
        'ground beef',
        contributions: <ShoppingContribution>[ask(ShoppingSourceKind.plan)],
      ),
    ]);

    expect(sources.single.key, 'plan');
    expect(sources.single.label, 'The meal plan');
    expect(sources.single.servings, isNull);
  });

  test('a typed-in item is not one', () {
    // It has no source behind it — it *is* the thing — and it comes off with
    // the swipe every other line uses. Two ways to remove one would read as
    // two different acts.
    final List<ShoppingSource> sources = ShoppingSources.of(<ShoppingLine>[
      ShoppingLine.manual(
        key: 'coffee',
        name: 'Coffee',
        planned: <Quantity>[Quantity.of(1, Units.item)],
      ),
    ]);

    expect(sources, isEmpty);
  });

  test('a row written before contributions existed reads as the plan', () {
    // Every line on every phone that updates into this. Read as the plan's,
    // because the plan owned every number on a list back then — which is also
    // what makes it removable rather than stranded.
    final List<ShoppingSource> sources = ShoppingSources.of(<ShoppingLine>[
      ShoppingLine(
        key: 'ground beef',
        name: 'ground beef',
        planned: <Quantity>[Quantity.of(2, Units.pound)],
      ),
    ]);

    expect(sources.single.key, 'plan');
  });

  test('several sources on one line are all reported', () {
    // The case the whole contributions model exists for: the plan's Tuesday
    // chilli and a bolognese added on Saturday both want beef.
    final List<ShoppingSource> sources = ShoppingSources.of(<ShoppingLine>[
      line(
        'ground beef',
        contributions: <ShoppingContribution>[
          ask(ShoppingSourceKind.plan),
          chilli(),
          ask(
            ShoppingSourceKind.food,
            refId: 'f-yoghurt',
            label: 'Greek yoghurt',
            servings: 3,
          ),
        ],
      ),
    ]);

    expect(sources.map((ShoppingSource s) => s.key), <String>[
      'plan',
      'recipe:r-chilli',
      'food:f-yoghurt',
    ]);
  });
}
