import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/features/recipes/recipe_plan_sheet.dart';

import '../../support/fixtures.dart';

class _ReviewResult {
  bool completed = false;
  RecipePlanSelection? selection;
}

Future<_ReviewResult> _open(
  WidgetTester tester, {
  Recipe? recipe,
  DateTime Function()? clock,
  double textScale = 1,
}) async {
  final _ReviewResult result = _ReviewResult();
  await tester.pumpWidget(
    MaterialApp(
      theme: HearthTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: FilledButton(
              onPressed: () async {
                result.selection = await showRecipePlanSheet(
                  context,
                  recipe:
                      recipe ?? aRecipe(title: 'Weeknight chili', servings: 8),
                  clock: clock ?? () => DateTime(2026, 9, 30, 14, 31),
                );
                result.completed = true;
              },
              child: const Text('Open plan'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open plan'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _reach(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _add(WidgetTester tester) async {
  final Finder add = find.widgetWithText(FilledButton, 'Add to my plan');
  await _reach(tester, add);
  await tester.tap(add, kind: PointerDeviceKind.touch);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Today, Dinner and one personal serving', (
    WidgetTester tester,
  ) async {
    final Recipe recipe = aRecipe(title: 'Weeknight chili', servings: 8);
    final _ReviewResult result = await _open(tester, recipe: recipe);

    expect(find.text('My plan'), findsOneWidget);
    expect(find.text(recipe.title), findsOneWidget);
    expect(find.text('Today · Wednesday 9/30/2026'), findsOneWidget);
    expect(
      find.text(
        'The shared recipe makes 8 servings. Your portion below is just for you.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Dinner'))
          .selected,
      isTrue,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1',
    );
    expect(result.completed, isFalse);

    await _add(tester);

    expect(result.completed, isTrue);
    expect(result.selection!.date, DateTime(2026, 9, 30));
    expect(result.selection!.slot, MealSlot.dinner);
    expect(result.selection!.servings, 1);
    expect(recipe.servings, 8);
  });

  testWidgets(
    'reviews another date and meal, then saves the focused fraction',
    (WidgetTester tester) async {
      final _ReviewResult result = await _open(tester);
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.text('Plan date'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('recipe-plan-date-input')),
        '10/7/2026',
      );
      await tester.tap(find.text('Use date'), kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(find.text('Wednesday 10/7/2026'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Lunch'));
      await tester.enterText(find.byType(TextField), '1 1/2');
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      // Saving must read the current field without a keyboard Done first.
      await _add(tester);

      expect(result.selection!.date, DateTime(2026, 10, 7));
      expect(result.selection!.slot, MealSlot.lunch);
      expect(result.selection!.servings, 1.5);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets('the desktop date review stays compact and confirms the date', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final _ReviewResult result = await _open(tester);
    await tester.tap(find.byKey(const ValueKey<String>('recipe-plan-date')));
    await tester.pumpAndSettle();

    final Finder surface = find.descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (Widget widget) =>
            widget is Material && widget.type == MaterialType.card,
      ),
    );
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface).width, lessThanOrEqualTo(560));
    expect(find.text('Use date').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Tomorrow'));
    await tester.tap(find.text('Use date'));
    await tester.pumpAndSettle();
    await _add(tester);
    expect(result.selection!.date, DateTime(2026, 10, 1));
  });

  testWidgets('a cancelled date change keeps the reviewed date', (
    WidgetTester tester,
  ) async {
    final _ReviewResult result = await _open(tester);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('recipe-plan-date-input')),
      '12/31/2026',
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await _add(tester);

    expect(result.selection!.date, DateTime(2026, 9, 30));
  });

  testWidgets('a rapid second Use date tap leaves the plan review open', (
    WidgetTester tester,
  ) async {
    final _ReviewResult result = await _open(tester);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('recipe-plan-date-input')),
      '10/7/2026',
    );
    await tester.tap(find.text('Use date'));
    await tester.tap(find.text('Use date'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result.completed, isFalse);
    expect(find.text('Wednesday 10/7/2026'), findsOneWidget);
    await _add(tester);
    expect(result.selection!.date, DateTime(2026, 10, 7));
  });

  testWidgets('invalid dates stay open and Tomorrow reviews the next day', (
    WidgetTester tester,
  ) async {
    final _ReviewResult result = await _open(tester);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    for (final String invalidDate in <String>[
      '2/30/2026',
      '13/1/2026',
      '1/1/0',
      '1/1/999999999',
    ]) {
      await tester.enterText(
        find.byKey(const ValueKey<String>('recipe-plan-date-input')),
        invalidDate,
      );
      await tester.tap(find.text('Use date'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter a valid date'),
        findsOneWidget,
        reason: 'Invalid date: $invalidDate',
      );
      expect(result.completed, isFalse);
    }
    await tester.tap(find.text('Tomorrow'));
    await tester.tap(find.text('Use date'));
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow · Thursday 10/1/2026'), findsOneWidget);
    await _add(tester);
    expect(result.selection!.date, DateTime(2026, 10, 1));
  });

  testWidgets(
    'a typed date crosses the year boundary without changing its day',
    (WidgetTester tester) async {
      final _ReviewResult result = await _open(
        tester,
        clock: () => DateTime(2026, 12, 31, 21),
      );
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.text('mm/dd/yyyy'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('recipe-plan-date-input')),
        '1/1/2027',
      );
      await tester.tap(find.text('Use date'));
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow · Friday 1/1/2027'), findsOneWidget);
      await _add(tester);
      expect(result.selection!.date, DateTime(2027, 1, 1));
    },
  );

  testWidgets('invalid portions stay open without replacing the typed input', (
    WidgetTester tester,
  ) async {
    final _ReviewResult result = await _open(tester);
    for (final String input in <String>[
      '',
      '0',
      '-1',
      'not an amount',
      'NaN',
      'Infinity',
      '1e999',
      '1/0',
    ]) {
      await _reach(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), input);
      await _add(tester);

      expect(result.completed, isFalse, reason: 'Invalid portion: $input');
      expect(
        find.text('Enter a serving amount greater than zero.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        input,
      );
    }

    await _reach(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '3/4');
    await _add(tester);
    expect(result.selection!.servings, 0.75);
  });

  testWidgets('cancel returns no selection after changing the portion', (
    WidgetTester tester,
  ) async {
    final _ReviewResult result = await _open(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Breakfast'));
    await tester.enterText(find.byType(TextField), '2.75');
    await _reach(tester, find.widgetWithText(TextButton, 'Cancel'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result.completed, isTrue);
    expect(result.selection, isNull);
  });

  for (final bool rebuild in <bool>[false, true]) {
    testWidgets('the opening date survives midnight with rebuild=$rebuild', (
      WidgetTester tester,
    ) async {
      DateTime now = DateTime(2026, 9, 30, 23, 59);
      final _ReviewResult result = await _open(tester, clock: () => now);
      now = DateTime(2026, 10, 1, 0, 1);
      if (rebuild) {
        await tester.tap(find.widgetWithText(ChoiceChip, 'Lunch'));
        await tester.pump();
        expect(find.text('Yesterday · Wednesday 9/30/2026'), findsOneWidget);
      }
      await _add(tester);

      expect(result.selection!.date, DateTime(2026, 9, 30));
      expect(
        result.selection!.slot,
        rebuild ? MealSlot.lunch : MealSlot.dinner,
      );
    });
  }

  testWidgets('a restaurant meal can be planned in a fractional portion', (
    WidgetTester tester,
  ) async {
    final Recipe restaurant = aRecipe(
      title: 'Burrito bowl',
      kind: RecipeKind.eatenOut,
      servings: 1,
    );
    final _ReviewResult result = await _open(tester, recipe: restaurant);
    expect(find.textContaining('restaurant meal'), findsOneWidget);
    expect(find.textContaining('shared recipe makes'), findsNothing);
    await tester.enterText(find.byType(TextField), '⅔');
    await _add(tester);

    expect(result.selection!.servings, closeTo(2 / 3, 1e-12));
    expect(restaurant.servings, 1);
  });

  for (final double recipeYield in <double>[0, double.nan, double.infinity]) {
    testWidgets(
      'an unavailable recipe yield keeps the personal default at 1 ($recipeYield)',
      (WidgetTester tester) async {
        final _ReviewResult result = await _open(
          tester,
          recipe: aRecipe(servings: recipeYield),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('no valid yield yet'), findsOneWidget);
        await _add(tester);
        expect(result.selection!.servings, 1);
      },
    );
  }

  testWidgets('controls have spoken labels and at least 44-point targets', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _open(tester);

    expect(find.bySemanticsLabel('Your portion in servings'), findsOneWidget);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Date for my plan'), findsOneWidget);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  for (final double scale in <double>[1, 3]) {
    testWidgets('date can be changed at 320×568 and ${scale}x text', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      addTearDown(tester.view.reset);
      final _ReviewResult result = await _open(tester, textScale: scale);
      final Finder date = find.byKey(
        const ValueKey<String>('recipe-plan-date'),
      );
      await _reach(tester, date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final Finder dateInput = find.byKey(
        const ValueKey<String>('recipe-plan-date-input'),
      );
      await _reach(tester, dateInput);
      await tester.enterText(dateInput, '10/7/2026');
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      tester.view.padding = const FakeViewPadding(top: 24);
      await tester.pumpAndSettle();
      for (final Finder action in <Finder>[
        find.widgetWithText(TextButton, 'Cancel').last,
        find.widgetWithText(FilledButton, 'Use date'),
      ]) {
        await _reach(tester, action);
        final Rect bounds = tester.getRect(action);
        expect(bounds.top, greaterThanOrEqualTo(24));
        expect(bounds.bottom, lessThanOrEqualTo(348));
      }
      await tester.tap(find.text('Use date'), kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _add(tester);
      expect(result.selection!.date, DateTime(2026, 10, 7));
    });

    for (final bool keyboard in <bool>[false, true]) {
      for (final String action in <String>['Add to my plan', 'Cancel']) {
        testWidgets(
          '$action is reachable at 320×568, ${scale}x, keyboard=$keyboard',
          (WidgetTester tester) async {
            tester.view.physicalSize = const Size(320, 568);
            tester.view.devicePixelRatio = 1;
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
            tester.view.viewPadding = const FakeViewPadding(
              top: 24,
              bottom: 34,
            );
            addTearDown(tester.view.reset);
            final _ReviewResult result = await _open(tester, textScale: scale);
            expect(tester.takeException(), isNull);
            await _reach(tester, find.byType(TextField));
            if (keyboard) {
              await tester.enterText(find.byType(TextField), '1/2');
              tester.view.viewInsets = const FakeViewPadding(bottom: 220);
              tester.view.padding = const FakeViewPadding(top: 24);
              await tester.pumpAndSettle();
            }

            for (final String label in <String>['Add to my plan', 'Cancel']) {
              final Finder button = find.ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate(
                  (Widget w) => w is ButtonStyleButton,
                ),
              );
              await _reach(tester, button);
              final Rect bounds = tester.getRect(button);
              expect(bounds.top, greaterThanOrEqualTo(24));
              expect(bounds.bottom, lessThanOrEqualTo(keyboard ? 348 : 534));
              expect(bounds.height, greaterThanOrEqualTo(44));
              expect(tester.takeException(), isNull);
            }
            final Finder chosen = find.text(action);
            await _reach(tester, chosen);
            await tester.tap(chosen, kind: PointerDeviceKind.touch);
            await tester.pumpAndSettle();

            expect(result.completed, isTrue);
            if (action == 'Cancel') {
              expect(result.selection, isNull);
            } else {
              expect(result.selection!.servings, keyboard ? 0.5 : 1);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
