import 'dart:convert';

import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/logged_portion.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/planning/portion_unit.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  ServingOption pot({double grams = 170, String label = '170 g pot'}) =>
      ServingOption(
        id: 'pot',
        label: label,
        amount: Quantity.of(grams, Units.gram),
        macros: const Macros(kcal: 170, proteinG: 17),
      );
  LoggedPortion grams([double amount = 125]) => LoggedPortion.tryCapture(
    amount: amount,
    unit: const PortionUnit.raw(Units.gram),
    servings: amount / 170,
    standard: pot(),
  )!;
  LoggedPortion roundTrip(LoggedPortion portion) =>
      LoggedPortion.fromJson(jsonDecode(jsonEncode(portion.toJson())))!;

  test('125 g retains the exact entered amount and its frozen 170 g basis', () {
    final LoggedPortion saved = roundTrip(grams());
    expect(saved.enteredAmount, 125);
    expect(saved.enteredUnit.id, 'unit:g');
    expect(saved.nutritionServing.label, '170 g pot');
    expect(saved.nutritionServing.amount.amountIn(Units.gram), 170);
    expect(saved.servings, 125 / 170);
    expect(saved.matchesServings(125 / 170), isTrue);
    expect(saved.withServings(saved.servings), same(saved));
  });

  test('changed serving size and label cannot change a saved correction', () {
    final LoggedPortion saved = grams();
    final ServingOption changed = pot(grams: 200, label: 'New 200 g pot');
    expect(
      saved.countOf(1, unit: const PortionUnit.raw(Units.gram)),
      closeTo(170, 1e-12),
    );
    expect(saved.countOf(1, unit: PortionUnit.serving(changed)), 1);
    final LoggedPortion corrected = saved.corrected(
      amount: 62.5,
      unit: const PortionUnit.raw(Units.gram),
    )!;
    expect(corrected.servings, closeTo(saved.servings / 2, 1e-12));
    expect(corrected.nutritionServing.label, '170 g pot');
    expect(corrected.nutritionServing.amount.amountIn(Units.gram), 170);
  });

  test('a named serving freezes its own size and the nutrition serving', () {
    final ServingOption scoop = ServingOption(
      id: 'scoop',
      label: '100 g scoop',
      amount: Quantity.of(100, Units.gram),
      macros: const Macros(kcal: 100),
    );
    final LoggedPortion saved = LoggedPortion.tryCapture(
      amount: 1.25,
      unit: PortionUnit.serving(scoop),
      servings: 125 / 170,
      standard: pot(),
    )!;
    final LoggedPortion back = roundTrip(saved);
    expect(back.enteredUnit.serving!.label, '100 g scoop');
    expect(back.enteredUnit.size.canonicalAmount, 100);
    expect(
      back.servingsFor(0.625, unit: PortionUnit.serving(scoop)),
      closeTo(62.5 / 170, 1e-12),
    );
    expect(back.nutritionServing.id, 'pot');
  });

  test(
    'fixed ounce conversions retain precise input without display rounding',
    () {
      const double ounces = 4.123456789;
      final double count = ounces * Units.ounce.toCanonical / 170;
      final LoggedPortion saved = LoggedPortion.tryCapture(
        amount: ounces,
        unit: const PortionUnit.raw(Units.ounce),
        servings: count,
        standard: pot(),
      )!;
      expect(roundTrip(saved).enteredAmount, ounces);
      expect(
        saved.countOf(count, unit: const PortionUnit.raw(Units.ounce)),
        ounces,
      );
      expect(
        saved.countOf(count, unit: const PortionUnit.raw(Units.gram)),
        closeTo(ounces * Units.ounce.toCanonical, 1e-10),
      );
      expect(
        saved.corrected(amount: ounces, unit: saved.enteredUnit),
        same(saved),
      );
    },
  );

  test(
    'a package equivalence works with zero calories and no live density',
    () {
      final ServingOption cup = ServingOption(
        id: 'nutrition-cup',
        label: '1 cup',
        amount: Quantity.of(1, Units.cup),
        macros: Macros.zero,
      );
      final LoggedPortion saved = LoggedPortion.tryCapture(
        amount: 30,
        unit: const PortionUnit.raw(Units.ounce),
        servings: 6,
        standard: cup,
      )!;
      expect(
        saved.servingsFor(15, unit: const PortionUnit.raw(Units.ounce)),
        3,
      );
      expect(saved.nutritionServing.id, 'nutrition-cup');
      // Entering the named serving changes the receipt's display, not its
      // numerical bridge. A later correction still knows the original oz/cup.
      final LoggedPortion cups = roundTrip(
        saved.corrected(amount: 3, unit: PortionUnit.serving(cup))!,
      );
      expect(cups.enteredUnit.id, 'serving:nutrition-cup');
      expect(cups.countOf(3, unit: const PortionUnit.raw(Units.ounce)), 15);
      expect(cups.servingsFor(5, unit: const PortionUnit.raw(Units.ounce)), 1);
      expect(
        cups.countOf(3, unit: const PortionUnit.raw(Units.millilitre)),
        closeTo(3 * Units.cup.toCanonical, 1e-9),
      );
    },
  );

  test('unsupported units cannot infer a new serving row or density', () {
    final LoggedPortion saved = grams();
    expect(
      saved.servingsFor(10, unit: const PortionUnit.raw(Units.millilitre)),
      isNull,
    );
    expect(
      saved.corrected(
        amount: 1,
        unit: PortionUnit.serving(
          ServingOption(
            id: 'new-serving',
            label: 'New serving',
            amount: Quantity.of(200, Units.gram),
            macros: Macros.zero,
          ),
        ),
      ),
      isNull,
    );
    expect(saved.units.map((PortionUnit unit) => unit.id), <String>[
      'unit:g',
      'serving:pot',
      'unit:oz',
    ]);
  });

  test(
    'invalid capture or correction values fail without a guessed amount',
    () {
      for (final double bad in <double>[0, -1, double.nan, double.infinity]) {
        expect(
          LoggedPortion.tryCapture(
            amount: bad,
            unit: const PortionUnit.raw(Units.gram),
            servings: 1,
            standard: pot(),
          ),
          isNull,
        );
        expect(grams().servingsFor(bad, unit: grams().enteredUnit), isNull);
        expect(grams().countOf(bad, unit: grams().enteredUnit), isNull);
      }
      expect(
        LoggedPortion.tryCapture(
          amount: 125,
          unit: const PortionUnit.raw(Units.gram),
          servings: 1,
          standard: pot(),
        ),
        isNull,
        reason: '125 g cannot establish one 170 g serving',
      );
      expect(
        LoggedPortion.tryCapture(
          amount: 1,
          unit: null,
          servings: 1,
          standard: pot(),
        ),
        isNull,
      );
    },
  );

  test(
    'a changed associated count suppresses evidence instead of inventing grams',
    () {
      final MacroSnapshot mixedClient = MacroSnapshot(
        macros: const Macros(kcal: 340),
        servings: 2,
        capturedAt: DateTime.utc(2026, 9, 30),
        label: 'Old yogurt',
        loggedPortion: grams(),
      );
      expect(mixedClient.usableLoggedPortion, isNull);
      expect(mixedClient.loggedPortion!.enteredAmount, 125);
    },
  );

  test(
    'correcting stale evidence back to its old count does not revive it',
    () {
      final LoggedPortion oldEvidence = grams();
      final MealPlanEntry mixedClient = MealPlanEntry(
        id: 'log',
        dayId: 'day',
        slot: MealSlot.lunch,
        refType: PlanRefType.food,
        refId: 'yogurt',
        servings: 2,
        isLogged: true,
        loggedAt: DateTime.utc(2026, 9, 30),
        macroSnapshot: MacroSnapshot(
          macros: const Macros(kcal: 340),
          servings: 2,
          capturedAt: DateTime.utc(2026, 9, 30),
          label: 'Old yogurt',
          loggedPortion: oldEvidence,
        ),
      );
      final MealPlanEntry corrected = mixedClient.log(
        liveMacros: const Macros(kcal: 170),
        at: DateTime.utc(2026, 10, 1),
        label: 'Changed yogurt',
        portion: oldEvidence.servings,
        coverage: const NutrientCoverage.notRecorded(),
      );
      expect(corrected.macroSnapshot!.usableLoggedPortion, isNull);
    },
  );

  test('future nested annotations survive known corrections and reload', () {
    final Map<String, Object?> raw = grams().toJson();
    raw['future_receipt'] = <String, Object?>{'photo': 'retained'};
    (raw['entered_unit']! as Map<String, Object?>)['future_unit'] = 'retained';
    (raw['conversion']! as Map<String, Object?>)['future_conversion'] = true;
    final Map<String, Object?> serving =
        raw['nutrition_serving']! as Map<String, Object?>;
    (serving['amount']! as Map<String, Object?>)['future_size'] = 42;
    final LoggedPortion corrected = roundTrip(
      LoggedPortion.fromJson(raw)!
          .corrected(amount: 62.5, unit: const PortionUnit.raw(Units.gram))!,
    );
    final Map<String, Object?> output = corrected.toJson();
    expect(output['future_receipt'], <String, Object?>{'photo': 'retained'});
    expect((output['entered_unit']! as Map)['future_unit'], 'retained');
    expect((output['conversion']! as Map)['future_conversion'], isTrue);
    expect(
      ((output['nutrition_serving']! as Map)['amount']! as Map)['future_size'],
      42,
    );
  });

  test(
    'future versions and malformed conversion evidence are not interpreted',
    () {
      expect(
        LoggedPortion.fromJson(<String, Object?>{
          ...grams().toJson(),
          'version': 99,
        }),
        isNull,
      );
      expect(
        LoggedPortion.fromJson(<String, Object?>{
          ...grams().toJson(),
          'conversion': <String, Object?>{},
        }),
        isNull,
      );
      expect(
        LoggedPortion.fromJson(<String, Object?>{
          ...grams().toJson(),
          'entered_amount': '125',
        }),
        isNull,
      );
      expect(
        LoggedPortion.fromJson(<String, Object?>{
          ...grams().toJson(),
          'associated_servings': 9,
        }),
        isNull,
      );
    },
  );
}
