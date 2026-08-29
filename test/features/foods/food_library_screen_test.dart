import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

Food yogurt() => aFood(
  'Greek yogurt',
  id: 'food-yogurt',
  servingOptions: <ServingOption>[
    aServing(
      id: 's1',
      amount: 170,
      unit: Units.gram,
      macros: const Macros(kcal: 100, proteinG: 17, carbG: 6),
    ),
  ],
);

Food chicken() => aFood(
  'Chicken breast',
  id: 'food-chicken',
  servingOptions: <ServingOption>[
    aServing(
      id: 's2',
      amount: 100,
      unit: Units.gram,
      macros: const Macros(kcal: 165, proteinG: 31),
    ),
  ],
);

Future<void> openFoods(
  WidgetTester tester, {
  List<Food> foods = const <Food>[],
}) async {
  await pumpHearthApp(tester, foods: foods);
  await tester.tap(find.text('Foods').last);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('empty library', () {
    testWidgets('says so, and points at both ways in', (
      WidgetTester tester,
    ) async {
      await openFoods(tester);
      expect(find.text('No foods yet'), findsOneWidget);
      expect(find.textContaining('Scan a packet'), findsOneWidget);
    });

    testWidgets('offers scanning ahead of typing a food in by hand', (
      WidgetTester tester,
    ) async {
      await openFoods(tester);

      // Scanning is the faster path for anything with a packet, and §5.5 puts
      // manual entry behind it rather than in front.
      expect(find.text('Scan'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('a populated library', () {
    testWidgets('lists foods with their per-serving macros', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      expect(find.byType(FoodCard), findsNWidgets(2));
      expect(find.text('Greek yogurt'), findsOneWidget);
      // Calories lead, the other three follow — calories are the primary
      // focus (spec §5.6).
      expect(find.text('100 kcal'), findsOneWidget);
      expect(find.textContaining('per 170 g'), findsOneWidget);
    });

    testWidgets('search narrows the list as you type', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await tester.enterText(find.byType(TextField).first, 'chick');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(FoodCard), findsOneWidget);
      expect(find.text('Chicken breast'), findsOneWidget);
      expect(find.text('Greek yogurt'), findsNothing);
    });

    testWidgets('a search with no matches offers to add the food', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);

      await tester.enterText(find.byType(TextField).first, 'rutabaga');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('None of your foods match'), findsOneWidget);
      expect(find.text('Add it as a new food'), findsOneWidget);
    });

    testWidgets('an empty search shows everything again', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);

      await tester.enterText(find.byType(TextField).first, 'chick');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(FoodCard), findsNWidgets(2));
    });
  });

  group('accessibility (spec §6.3)', () {
    testWidgets('each food is one labelled button', (
      WidgetTester tester,
    ) async {
      await openFoods(tester, foods: <Food>[yogurt()]);
      final SemanticsHandle handle = tester.ensureSemantics();

      expect(find.bySemanticsLabel(RegExp('Greek yogurt')), findsOneWidget);

      handle.dispose();
    });

    testWidgets('meets the tap-target guidelines', (WidgetTester tester) async {
      await openFoods(tester, foods: <Food>[yogurt(), chicken()]);
      final SemanticsHandle handle = tester.ensureSemantics();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      handle.dispose();
    });
  });
}
