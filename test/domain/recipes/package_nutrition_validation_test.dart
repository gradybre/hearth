import 'dart:convert';

import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/recipes/macro_calculator.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/domain/units/unit_converter.dart';
import 'package:test/test.dart';

import '../../support/fixtures.dart';

Map<String, dynamic> validRecord() => PackageNutrition.manual(
  servingsPerPackage: 2,
  servingOptionId: 'cup',
  servingAmount: Quantity.of(1, Units.cup),
  packageAmount: Quantity.of(10, Units.ounce),
).toJson();

void main() {
  test('malformed version-one evidence cannot activate', () {
    for (final Map<String, dynamic> record in <Map<String, dynamic>>[
      validRecord()..['source'] = 'guess',
      validRecord()..['is_approximate'] = 'false',
      validRecord()..['version'] = 1.5,
      validRecord()..['serving_option_id'] = ' ',
      validRecord()..['padding'] = 'x' * 4096,
      validRecord()..['serving_amount']['unit'] = 'oz',
      validRecord()..['serving_amount']['unit'] = 'unknown',
      validRecord()..['package_amount']['unit'] = null,
    ]) {
      expect(
        PackageNutrition.fromJson(record).isValid,
        isFalse,
        reason: '$record',
      );
    }
  });
  test('nonfinite version parses without throwing and stays inactive', () {
    final PackageNutrition record = PackageNutrition.fromJson(
      validRecord()..['version'] = double.infinity,
    );
    expect(record.isValid, isFalse);
    expect(record.isSendable, isFalse);
    expect(
      PackageNutrition.fromJson(validRecord()..['version'] = 1.5).isSendable,
      isFalse,
    );
  });
  test('snapshot unit changes require review consistently with the server', () {
    final PackageNutrition record = PackageNutrition.fromJson(validRecord());
    expect(
      record.matches(
        pack: Quantity.of(10, Units.ounce),
        servingId: 'cup',
        servingAmount: Quantity.of(
          1,
          Units.cup,
        ).withPreferredUnit(Units.millilitre),
      ),
      isFalse,
    );
  });

  test('a finite but absurd count states no density, and is not valid', () {
    final PackageNutrition record = PackageNutrition.fromJson(
      validRecord()..['servings_per_package'] = 1e308,
    );
    expect(
      record.gramsPerMillilitre,
      isNull,
      reason: 'a package divided into that many servings overflows',
    );
    expect(
      record.isValid,
      isFalse,
      reason: 'a confirmed relationship that answers nothing is not one',
    );
  });

  test('the cap also includes Postgres JSONB separators', () {
    final record = validRecord()..['padding'] = '';
    final compact = utf8.encode(jsonEncode(record)).length;
    record['padding'] = 'x' * (4096 - compact);
    // Compact JSON fits, but Postgres inserts spaces after colons and commas.
    expect(PackageNutrition.fromJson(record).isSendable, isFalse);
    record['padding'] = 'x' * 3000;
    expect(PackageNutrition.fromJson(record).isSendable, isTrue);
  });

  test('unreadable quantity evidence survives without normalization', () {
    final raw = validRecord()..['serving_amount']['unit'] = 'future-unit';
    final stored = PackageNutrition.fromJson(raw).toJson();
    expect(stored, raw);
    expect(PackageNutrition.fromJson(stored).isValid, isFalse);
  });

  test('a future key inside a version-one record survives a re-save', () {
    final PackageNutrition record = PackageNutrition.fromJson(
      validRecord()..['basis_note'] = 'drained-verified',
    );
    expect(record.isValid, isTrue);

    final Map<String, dynamic> saved = record.toJson();
    expect(
      saved['basis_note'],
      'drained-verified',
      reason: 'an unrelated edit on this build must not drop it',
    );
    expect(saved['version'], 1);
    expect(saved['servings_per_package'], 2);
    expect(saved['basis'], 'as_packaged');
  });

  test('a malformed field is not quietly rewritten into a valid one', () {
    final PackageNutrition record = PackageNutrition.fromJson(
      validRecord()..['is_approximate'] = 'false',
    );
    expect(record.isValid, isFalse);
    expect(record.toJson()['is_approximate'], 'false');
    expect(
      PackageNutrition.fromJson(record.toJson()).isValid,
      isFalse,
      reason: 'normalising it here would activate it on the next read',
    );
  });

  test('only a record the server would accept is pushed', () {
    expect(PackageNutrition.fromJson(validRecord()).isSendable, isTrue);
    expect(
      PackageNutrition.fromJson(validRecord()..['source'] = 'guess').isSendable,
      isFalse,
      reason: 'it would fail the whole food upsert',
    );
    expect(
      PackageNutrition.fromJson(validRecord()..['padding'] = 'x' * 5000)
          .isSendable,
      isFalse,
    );
    expect(
      PackageNutrition.fromJson(<String, dynamic>{'version': 99, 'kept': 'yes'})
          .isSendable,
      isTrue,
      reason: 'it came from a server that understood it',
    );
  });

  group('a stored density that cannot be divided by (review B1)', () {
    Food subjectWith(double? density) => Food(
      id: 'food-bad-density',
      name: 'Test food',
      source: FoodSource.manual,
      servingOptions: <ServingOption>[
        ServingOption(
          id: 'cup',
          label: '1 cup',
          amount: Quantity.of(1, Units.cup),
          macros: const Macros(kcal: 100, proteinG: 2),
        ),
      ],
      packSize: Quantity.of(10, Units.ounce),
      gramsPerMillilitre: density,
      packageNutrition: PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: 'cup',
        servingAmount: Quantity.of(1, Units.cup),
        packageAmount: Quantity.of(10, Units.ounce),
      ),
    );

    for (final double bad in <double>[
      double.nan,
      0,
      -1,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('$bad is ignored, so the reviewed package answers instead', () {
        final Food food = subjectWith(bad);
        expect(food.ownGramsPerMillilitre, isNull);
        expect(
          food.effectiveGramsPerMillilitre,
          food.packageGramsPerMillilitre,
        );

        final IngredientMacros result = MacroCalculator.forIngredient(
          anIngredient(
            'Test food',
            amount: 30,
            unit: Units.ounce,
            foodId: food.id,
          ),
          food: food,
        );
        expect(result.status, IngredientMacroStatus.resolved);
        expect(result.macros.kcal, closeTo(600, 1e-6));
        expect(result.macros.proteinG, closeTo(12, 1e-6));
        expect(result.macros.kcal.isFinite, isTrue);
      });

      test('$bad never reaches a conversion', () {
        final ConversionResult converted = UnitConverter.crossKind(
          Quantity.of(1, Units.cup),
          UnitKind.mass,
          gramsPerMillilitre: bad,
        );
        expect(converted.densityMissing, isTrue);
        expect(converted.isExact, isFalse);
        expect(
          converted.quantity.canonicalAmount.isFinite,
          isTrue,
          reason: 'the quantity comes back untouched, not poisoned',
        );
      });
    }
  });
}
