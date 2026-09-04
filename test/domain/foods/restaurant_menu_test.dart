import 'package:hearth/domain/foods/restaurant_menu.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

/// The restaurants a household has seeded (spec §5.2).
void main() {
  Food menuItem(
    String name, {
    required String restaurant,
    num amount = 4,
    Unit? unit,
  }) => aFood(
    name,
    id: 'f-${restaurant.toLowerCase()}-${name.toLowerCase()}',
    brand: restaurant,
    source: FoodSource.restaurant,
    servingOptions: <ServingOption>[
      aServing(
        amount: amount,
        unit: unit ?? Units.ounce,
        macros: const Macros(kcal: 180, proteinG: 32),
      ),
    ],
  );

  group('which restaurants there are', () {
    test('one entry per restaurant, however many foods it has', () {
      final List<Food> library = <Food>[
        menuItem('Chicken', restaurant: 'Chipotle'),
        menuItem('Guacamole', restaurant: 'Chipotle'),
        menuItem('Chicken', restaurant: 'Cava'),
        aFood('Ground beef'),
      ];

      expect(RestaurantMenu.restaurantsIn(library), <String>[
        'Cava',
        'Chipotle',
      ]);
    });

    test('the household\'s own foods are not a restaurant', () {
      expect(
        RestaurantMenu.restaurantsIn(<Food>[
          aFood('Ground beef', brand: 'Maverick Ranch'),
        ]),
        isEmpty,
      );
    });

    test('nor is a deleted menu, once its last item goes', () {
      // Foods are soft-deleted (§4), so a removed menu item is still there
      // to be found — and must not be.
      final Food gone = menuItem('Chicken', restaurant: 'Cava');
      final Food library = Food(
        id: gone.id,
        name: gone.name,
        brand: gone.brand,
        source: gone.source,
        servingOptions: gone.servingOptions,
        isDeleted: true,
      );

      expect(RestaurantMenu.restaurantsIn(<Food>[library]), isEmpty);
    });

    test('nor a restaurant food nobody said the restaurant for', () {
      // The editor refuses to save one. This is what happens to any that
      // predate that rule: it belongs to no menu, so no menu lists it.
      final Food orphan = aFood('Chicken', source: FoodSource.restaurant);

      expect(RestaurantMenu.restaurantsIn(<Food>[orphan]), isEmpty);
      expect(RestaurantMenu.itemsFor('', <Food>[orphan]), isEmpty);
    });
  });

  group('what is on one', () {
    test('only that restaurant, and in a findable order', () {
      final List<Food> library = <Food>[
        menuItem('Guacamole', restaurant: 'Chipotle'),
        menuItem('Barbacoa', restaurant: 'Chipotle'),
        menuItem('Chicken', restaurant: 'Cava'),
      ];

      expect(
        RestaurantMenu.itemsFor('Chipotle', library).map((Food f) => f.name),
        <String>['Barbacoa', 'Guacamole'],
      );
    });

    test('and the name is matched the way anybody would type it', () {
      final List<Food> library = <Food>[
        menuItem('Chicken', restaurant: 'Chipotle'),
      ];

      expect(RestaurantMenu.itemsFor('chipotle', library), hasLength(1));
      expect(RestaurantMenu.itemsFor(' Chipotle ', library), hasLength(1));
    });
  });

  group('what a pick writes into a recipe', () {
    test('one of them is the portion they serve', () {
      final MenuPick pick = MenuPick(
        food: menuItem('Chicken', restaurant: 'Chipotle'),
      );

      expect(pick.line, '4 oz Chicken');
    });

    test('two of them is double meat, not a second line', () {
      final MenuPick pick = MenuPick(
        food: menuItem('Chicken', restaurant: 'Chipotle'),
        count: 2,
      );

      expect(pick.line, '8 oz Chicken');
      expect(pick.quantity!.amountIn(Units.ounce), closeTo(8, 1e-9));
    });

    test('and half of one is half of one', () {
      final MenuPick pick = MenuPick(
        food: menuItem('Cilantro-Lime White Rice', restaurant: 'Chipotle'),
        count: 0.5,
      );

      expect(pick.line, '2 oz Cilantro-Lime White Rice');
    });

    test('a countable item gets a unit word the parser can read', () {
      // `Units.item` has an empty label, so "1 Flour Tortilla" would leave
      // the parser a bare number with nothing to hang it on.
      final MenuPick pick = MenuPick(
        food: menuItem(
          'Flour Tortilla',
          restaurant: 'Chipotle',
          amount: 1,
          unit: Units.item,
        ),
      );

      expect(pick.line, '1 ea Flour Tortilla');
    });

    test('a food with no serving at all still names itself', () {
      final MenuPick pick = MenuPick(
        food: aFood('Mystery', brand: 'Cava', source: FoodSource.restaurant),
      );

      expect(pick.quantity, isNull);
      expect(pick.line, 'Mystery');
    });
  });
}
