import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/repositories/plan_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/nutrient_coverage.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Retrying a save that half-succeeded (spec §5.2, §8.3).
///
/// The recipe is written first and the meal entry second. If the second fails
/// the editor stays open with the button live again — which is the retry — but
/// the screen had not remembered the recipe it just wrote, so pressing again
/// minted a fresh id and left two copies of the same restaurant meal in the
/// library.
void main() {
  Food burger() => aFood(
    'Steakburger',
    id: 'f-burger',
    brand: "Freddy's",
    source: FoodSource.restaurant,
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'one',
        label: '1 burger',
        amount: Quantity.of(1, Units.item),
        macros: const Macros(kcal: 460, proteinG: 26),
      ),
    ],
  );

  testWidgets('writes one recipe, not one per attempt', (
    WidgetTester tester,
  ) async {
    final _FailingPlans plans = _FailingPlans();
    final HearthDatabase db = await pumpHearthApp(
      tester,
      foods: <Food>[burger()],
      extraOverrides: <Object>[planRepositoryProvider.overrideWithValue(plans)],
    );

    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Add to dinner').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Ate out — build it from a menu'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text("Freddy's").last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Steakburger').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.textContaining('Build ('));
    await pumpFrames(tester, frames: 16);
    await tester.enterText(find.byType(TextField).first, 'Dinner out');
    await pumpFrames(tester, frames: 8);

    // The meal entry fails. The recipe is already written.
    await tester.tap(find.text('Save and log dinner'));
    await pumpFrames(tester, frames: 20);
    await pumpFrames(tester, frames: 8);
    // Said out loud rather than thrown: an unhandled async error from a save
    // leaves the editor looking as though it had done nothing at all.
    expect(
      find.textContaining('could not add it to'),
      findsOneWidget,
      reason: 'the failure was swallowed, or escaped as an unhandled error',
    );
    expect(await db.select(db.recipes).get(), hasLength(1));
    expect(
      find.text('Save and log dinner'),
      findsOneWidget,
      reason: 'the editor closed, so there is no way to retry',
    );

    // The editor is still open, so press it again — which is the retry.
    plans.fail = false;
    await tester.tap(find.text('Save and log dinner'));
    await pumpFrames(tester, frames: 24);

    expect(
      await db.select(db.recipes).get(),
      hasLength(1),
      reason: 'the retry wrote a second copy of the same restaurant meal',
    );
  });
}

/// A plan repository whose `add` fails on demand.
class _FailingPlans implements PlanRepository {
  bool fail = true;

  @override
  Future<MealPlanEntry> add({
    required DateTime date,
    required MealSlot slot,
    required PlanRefType refType,
    required String refId,
    required double servings,
    Macros? loggedMacros,
    NutrientCoverage? loggedCoverage,
    String? label,
  }) async {
    if (fail) throw StateError('the entry could not be written');
    return MealPlanEntry(
      id: 'e1',
      dayId: 'd1',
      slot: slot,
      refType: refType,
      refId: refId,
      servings: servings,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
