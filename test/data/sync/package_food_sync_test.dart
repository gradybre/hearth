import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/mappers/food_mapper.dart';
import 'package:hearth/data/mappers/sync_payload.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/units/mass_display_mode.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

void main() {
  test('the inbound sync decoder carries both package fields', () {
    final Food food = Food(
      id: 'food',
      name: 'Corn',
      source: FoodSource.manual,
      servingOptions: const [],
      massDisplayMode: MassDisplayMode.ounces,
      packSize: Quantity.of(10, Units.ounce),
      packageNutrition: PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 'cup',
        servingAmount: Quantity.of(1, Units.cup),
        packageAmount: Quantity.of(10, Units.ounce),
      ),
    );
    final Food decoded = SyncPayload.food(
      FoodMapper.toJson(food, updatedAt: DateTime.utc(2026, 9, 19)),
    );
    expect(decoded.massDisplayMode, MassDisplayMode.ounces);
    expect(decoded.packageNutrition?.toJson(), food.packageNutrition!.toJson());
  });
}
