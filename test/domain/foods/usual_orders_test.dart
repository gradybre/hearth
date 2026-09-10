import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/restaurant_menu.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/fixtures.dart';

/// The orders a household already has, for the restaurant it is looking at
/// (review N03).
///
/// The builder records the restaurant in a recipe's `notes`, and `notes` is a
/// plain text box in the editor — anyone who types in it breaks the tie. The
/// components cannot be typed over: a recipe whose matched foods are Chopt
/// menu foods is a Chopt order whatever the notes say. So the components are
/// asked first and the notes are the fallback, which is what still carries a
/// recipe whose ingredients were never matched.
void main() {
  Food menuItem(String name, {required String restaurant}) => aFood(
    name,
    id: 'f-${restaurant.toLowerCase()}-${name.toLowerCase()}',
    brand: restaurant,
    source: FoodSource.restaurant,
    servingOptions: <ServingOption>[
      aServing(
        amount: 4,
        unit: Units.ounce,
        macros: const Macros(kcal: 120, proteinG: 8),
      ),
    ],
  );

  final Food guac = menuItem('Guacamole', restaurant: 'Chopt');
  final Food falafel = menuItem('Falafel', restaurant: 'Cava');

  Map<String, Food> library() => <String, Food>{
    guac.id: guac,
    falafel.id: falafel,
  };

  Recipe order(
    String title, {
    required RecipeKind kind,
    String? notes,
    String? matchedFoodId,
  }) => aRecipe(
    id: 'r-${title.toLowerCase().replaceAll(' ', '-')}',
    title: title,
    kind: kind,
    notes: notes,
    ingredients: <RecipeIngredient>[
      anIngredient('a component', foodId: matchedFoodId),
    ],
  );

  test('an order is found by the menu its components came from', () {
    final Recipe mine = order(
      'My usual bowl',
      kind: RecipeKind.eatenOut,
      // Deliberately renamed: the tie must not rest on this.
      notes: 'the one on Fulton St',
      matchedFoodId: guac.id,
    );

    expect(
      RestaurantMenu.usualOrders(
        restaurant: 'Chopt',
        recipes: <Recipe>[mine],
        foods: library(),
      ),
      <Recipe>[mine],
    );
  });

  test("and not by another restaurant's", () {
    final Recipe theirs = order(
      'Falafel plate',
      kind: RecipeKind.eatenOut,
      matchedFoodId: falafel.id,
    );

    expect(
      RestaurantMenu.usualOrders(
        restaurant: 'Chopt',
        recipes: <Recipe>[theirs],
        foods: library(),
      ),
      isEmpty,
    );
  });

  test('a recipe nobody matched falls back to what the notes say', () {
    // The builder writes the restaurant there, so an order saved without its
    // ingredients ever being matched still belongs to somebody.
    final Recipe unmatched = order(
      'Something I ordered',
      kind: RecipeKind.eatenOut,
      notes: 'Chopt',
    );

    expect(
      RestaurantMenu.usualOrders(
        restaurant: 'Chopt',
        recipes: <Recipe>[unmatched],
        foods: library(),
      ),
      <Recipe>[unmatched],
    );
  });

  test('a cooked recipe is never an order, whatever it is made of', () {
    // You can cook with a food that came off a menu. That does not make
    // dinner at home a thing you ordered.
    final Recipe cooked = order(
      'Guacamole at home',
      kind: RecipeKind.cooked,
      matchedFoodId: guac.id,
    );

    expect(
      RestaurantMenu.usualOrders(
        restaurant: 'Chopt',
        recipes: <Recipe>[cooked],
        foods: library(),
      ),
      isEmpty,
    );
  });

  test('the restaurant is matched the way its name is written', () {
    // `restaurantsIn` trims and compares case-insensitively, and this has to
    // agree with it or a menu and its orders would disagree about one place.
    final Recipe mine = order(
      'My usual bowl',
      kind: RecipeKind.eatenOut,
      notes: '  chopt  ',
    );

    expect(
      RestaurantMenu.usualOrders(
        restaurant: 'Chopt',
        recipes: <Recipe>[mine],
        foods: library(),
      ),
      <Recipe>[mine],
    );
  });

  test('a favourite is offered before a more recent one', () {
    // The review asks for Favourite/Recent ordering, and recent is inherited
    // — the library is already `updatedAt desc`. Favourite is the half that
    // has to be asked for, and it was not.
    final Recipe recent = order(
      'Something I had yesterday',
      kind: RecipeKind.eatenOut,
      notes: 'Chopt',
    );
    final Recipe loved = order(
      'My usual bowl',
      kind: RecipeKind.eatenOut,
      notes: 'Chopt',
    );

    expect(
      RestaurantMenu.usualOrders(
        restaurant: 'Chopt',
        // Library order: the recent one first.
        recipes: <Recipe>[recent, loved],
        foods: library(),
        favourites: <String>{loved.id},
      ).map((Recipe r) => r.id),
      <String>[loved.id, recent.id],
    );
  });

  test('and only a few are offered, not a whole history', () {
    // They sit above the first menu heading, in the one change whose subject
    // is reaching the menu faster. Fifteen cards there would be the problem
    // wearing a different hat.
    final List<Recipe> many = <Recipe>[
      for (int i = 0; i < 12; i++)
        order('Order $i', kind: RecipeKind.eatenOut, notes: 'Chopt'),
    ];

    expect(
      RestaurantMenu.usualOrders(
        restaurant: 'Chopt',
        recipes: many,
        foods: library(),
      ),
      hasLength(RestaurantMenu.usualOrdersShown),
    );
  });

  test('nothing saved means nothing offered', () {
    expect(
      RestaurantMenu.usualOrders(
        restaurant: 'Chopt',
        recipes: const <Recipe>[],
        foods: library(),
      ),
      isEmpty,
    );
  });
}
