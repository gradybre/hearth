import 'package:hearth/domain/foods/restaurant_menu.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
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
    String? section,
    int? order,
  }) => aFood(
    name,
    id: 'f-${restaurant.toLowerCase()}-${name.toLowerCase()}',
    brand: restaurant,
    source: FoodSource.restaurant,
    menuGroup: section,
    menuOrder: order,
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

  group('laid out the way the restaurant lays it out', () {
    // Chipotle's own sheet: tortillas, then rice, then beans, then the
    // proteins, then the salsas. Not one of those is where the alphabet
    // would put it.
    List<Food> sheet() => <Food>[
      menuItem(
        'Chicken',
        restaurant: 'Chipotle',
        section: 'Proteins',
        order: 4,
      ),
      menuItem(
        'Barbacoa',
        restaurant: 'Chipotle',
        section: 'Proteins',
        order: 3,
      ),
      menuItem(
        'Fresh Tomato Salsa',
        restaurant: 'Chipotle',
        section: 'Salsas',
        order: 5,
      ),
      menuItem(
        'Flour Tortilla',
        restaurant: 'Chipotle',
        section: 'Tortillas',
        order: 0,
      ),
      menuItem(
        'Black Beans',
        restaurant: 'Chipotle',
        section: 'Beans',
        order: 2,
      ),
      menuItem('White Rice', restaurant: 'Chipotle', section: 'Rice', order: 1),
    ];

    test('items come out where the sheet put them', () {
      expect(
        RestaurantMenu.itemsFor('Chipotle', sheet()).map((Food f) => f.name),
        <String>[
          'Flour Tortilla',
          'White Rice',
          'Black Beans',
          'Barbacoa',
          'Chicken',
          'Fresh Tomato Salsa',
        ],
      );
    });

    test('and the sections do too, by where each one first appears', () {
      // Alphabetically this would be Beans, Proteins, Rice, Salsas,
      // Tortillas — which is nobody's menu.
      expect(
        RestaurantMenu.sectionsFor(
          'Chipotle',
          sheet(),
        ).map((MenuSection s) => s.name),
        <String>['Tortillas', 'Rice', 'Beans', 'Proteins', 'Salsas'],
      );
    });

    test('a section keeps its own items together and in order', () {
      final MenuSection proteins = RestaurantMenu.sectionsFor(
        'Chipotle',
        sheet(),
      ).firstWhere((MenuSection s) => s.name == 'Proteins');

      expect(proteins.items.map((Food f) => f.name), <String>[
        'Barbacoa',
        'Chicken',
      ]);
    });

    test('an item added by hand is last, not lost', () {
      // No section and no place on a sheet nobody pasted. Putting it first
      // would push the whole menu down the screen.
      final List<Food> library = <Food>[
        ...sheet(),
        menuItem('Extra tortilla on the side', restaurant: 'Chipotle'),
      ];
      final List<MenuSection> sections = RestaurantMenu.sectionsFor(
        'Chipotle',
        library,
      );

      expect(sections.last.name, isNull);
      expect(sections.last.items.single.name, 'Extra tortilla on the side');
    });

    test('a menu nobody sectioned is one unnamed section, not none', () {
      final List<MenuSection> sections = RestaurantMenu.sectionsFor(
        'Cava',
        <Food>[
          menuItem('Falafel', restaurant: 'Cava'),
          menuItem('Harissa', restaurant: 'Cava'),
        ],
      );

      expect(sections, hasLength(1));
      expect(sections.single.name, isNull);
      expect(sections.single.items, hasLength(2));
    });
  });

  group('a portion is a portion, not a float', () {
    // Brendan's screenshot: "4.000000017636981 oz Cilantro-Lime Brown Rice"
    // in the ingredients, and "2.0000000088184904 oz" on the row.
    //
    // Two faults compounding. The seed stored 4 oz as 113.398093 g — rounded
    // to six places by the generator — so converting back gives 4.000000018.
    // And this wrote whatever double came out, so the residue was shown at
    // full width. The data is fixed separately; a portion that reads as a
    // portion is this half, and it has to hold against residue from any
    // source, not just that one.
    Food noisy({double ounces = 4}) => aFood(
      'Cilantro-Lime Brown Rice',
      brand: 'Chipotle',
      source: FoodSource.restaurant,
      servingOptions: <ServingOption>[
        ServingOption(
          id: 'serving-noisy',
          label: '$ounces oz',
          // What the seeded row actually holds, to six decimal places.
          amount: Quantity.canonical(
            canonicalAmount: 113.398093 * (ounces / 4),
            kind: UnitKind.mass,
            preferredUnit: Units.ounce,
          ),
          macros: const Macros(kcal: 210),
        ),
      ],
    );

    test('reads as the round number it is meant to be', () {
      expect(MenuPick(food: noisy()).line, '4 oz Cilantro-Lime Brown Rice');
    });

    test('and half a 4 oz scoop is 2 oz, not eight decimal places of it', () {
      expect(
        MenuPick(food: noisy(), count: 0.5).line,
        '2 oz Cilantro-Lime Brown Rice',
      );
    });

    test('a real fraction is still written as one the parser can read', () {
      final Food half = aFood(
        'Guacamole',
        brand: 'Chipotle',
        source: FoodSource.restaurant,
        servingOptions: <ServingOption>[
          aServing(
            amount: 1,
            unit: Units.ounce,
            macros: const Macros(kcal: 60),
          ),
        ],
      );

      expect(MenuPick(food: half, count: 0.5).line, '1/2 oz Guacamole');
      expect(MenuPick(food: half, count: 1.5).line, '1 1/2 oz Guacamole');
    });

    test('and a genuinely odd amount is not rounded away', () {
      // Rounding is for floating-point residue, not for numbers somebody
      // meant. A third of a cup is a third of a cup.
      final Food third = aFood(
        'Rice',
        brand: 'Chipotle',
        source: FoodSource.restaurant,
        servingOptions: <ServingOption>[
          aServing(
            amount: 1 / 3,
            unit: Units.cup,
            macros: const Macros(kcal: 70),
          ),
        ],
      );

      expect(MenuPick(food: third).line, '1/3 cup Rice');
    });
  });
}
