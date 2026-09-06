import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/planning/day_progress.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Logging in the food's own servings (spec §5.6, U03).
///
/// A food knows several — "170 g pot", "100 g", "1 tbsp" — and logging could
/// only ever count the default one. Eating half a pot meant working out what
/// that was as a multiple of something else, in your head, in a kitchen.
void main() {
  const MacroTargets targets = MacroTargets(
    kcal: 2000,
    proteinG: 150,
    carbG: 200,
    fatG: 70,
  );

  Food yoghurt() => aFood(
    'Greek yoghurt',
    id: 'f-yoghurt',
    servingOptions: <ServingOption>[
      ServingOption(
        id: 'pot',
        label: '170 g pot',
        amount: Quantity.of(170, Units.gram),
        macros: const Macros(kcal: 170, proteinG: 17),
      ),
      ServingOption(
        id: 'hundred',
        label: '100 g',
        amount: Quantity.of(100, Units.gram),
        macros: const Macros(kcal: 100, proteinG: 10),
        isReference: true,
      ),
      ServingOption(
        id: 'spoon',
        label: '1 tbsp',
        amount: Quantity.of(1, Units.tbsp),
        macros: const Macros(kcal: 15, proteinG: 1.5),
      ),
    ],
  );

  Future<void> openPicker(WidgetTester tester) async {
    await pumpHearthApp(tester, foods: <Food>[yoghurt()], targets: targets);
    await tester.tap(find.text('Plan').last);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Add to breakfast').first);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Greek yoghurt').last);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('offers the food\'s own servings, in its own words', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    expect(find.text('Serving'), findsOneWidget);
    expect(find.text('170 g pot'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(find.text('1 tbsp'), findsOneWidget);
  });

  testWidgets('and counts the one you chose, not the default', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    // The default pot is 170 kcal.
    expect(find.textContaining('170 kcal'), findsWidgets);

    await tester.tap(find.text('100 g'));
    await pumpFrames(tester, frames: 8);

    // 1 x 170 g, expressed in 100 g units, is 1.7 of them — and 1.7 x 100
    // kcal is the same 170. Switching the unit must not change the food.
    expect(find.textContaining('170 kcal'), findsWidgets);
  });

  testWidgets('switching between masses keeps the amount', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    await tester.tap(find.text('100 g'));
    await pumpFrames(tester, frames: 8);

    // A pot is 170 g, so in 100 g units that is 1.7.
    expect(find.text('1.7'), findsOneWidget);
  });

  testWidgets('but across kinds it asks rather than guesses', (
    WidgetTester tester,
  ) async {
    // A tablespoon is a volume and a pot is a mass, and this food carries no
    // density — so there is no honest number to carry across. §5.5's rule is
    // that a figure nobody stated is not invented.
    await openPicker(tester);

    await tester.tap(find.text('1 tbsp'));
    await pumpFrames(tester, frames: 8);

    expect(
      find.text('1'),
      findsOneWidget,
      reason: 'the count should start again rather than be guessed at',
    );
  });
}
