import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/shopping/shopping_list_builder.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

void main() {
  test(
    'a removed selected serving remains on the shop as an unknown amount',
    () {
      final food = Food(
        id: 'corn',
        name: 'Corn',
        source: FoodSource.manual,
        servingOptions: [
          ServingOption(
            id: 'default',
            label: '100 g',
            amount: Quantity.of(100, Units.gram),
            macros: const Macros(kcal: 100),
          ),
        ],
      );
      final today = DateTime(2026, 9, 19);
      final lines = ShoppingListBuilder.forRange(
        from: today,
        to: today,
        entriesByDay: {
          today: [
            const MealPlanEntry(
              id: 'e',
              dayId: 'd',
              slot: MealSlot.lunch,
              refType: PlanRefType.food,
              refId: 'corn',
              servings: 6,
              servingOptionId: 'removed',
            ),
          ],
        },
        recipes: {},
        foods: {food.id: food},
      );
      expect(lines, hasLength(1));
      expect(lines.single.hasUnquantified, isTrue);
      expect(lines.single.planned, isEmpty);
    },
  );
}
