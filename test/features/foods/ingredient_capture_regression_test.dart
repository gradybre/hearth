import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/features/foods/food_picker.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

class _Foods extends Mock implements FoodRepository {}

void main() {
  setUpAll(() => registerFallbackValue(aFood('Fallback')));
  testWidgets('ingredient search scrolls at 320 by 568 with 3x text', (
    tester,
  ) async {
    await pumpHearthApp(tester, size: const Size(320, 568), textScale: 3);
    unawaited(
      showFoodPicker(
        tester.element(find.byType(Scaffold).first),
        ingredientName: 'olive oil',
      ),
    );
    await pumpFrames(tester, frames: 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ingredient scanner typed path scrolls at 320 by 568 with 3x text',
    (tester) async {
      await pumpHearthApp(tester, size: const Size(320, 568), textScale: 3);
      unawaited(
        tester
            .element(find.byType(Scaffold).first)
            .push<String>('/food/scan?pick=1'),
      );
      await pumpFrames(tester, frames: 20);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual food failure is readable and keeps its draft for retry', (
    tester,
  ) async {
    final repository = _Foods();
    when(() => repository.likelyDuplicatesOf(any()))
        .thenAnswer((_) async => []);
    when(() => repository.save(any())).thenThrow(StateError('disk full'));
    await pumpHearthApp(
      tester,
      extraOverrides: [foodRepositoryProvider.overrideWithValue(repository)],
    );
    unawaited(
      tester.element(find.byType(Scaffold).first).push<String>('/food/new'),
    );
    await pumpFrames(tester, frames: 20);
    await tester.enterText(
      find.widgetWithText(TextField, 'Greek yogurt'),
      'Yogurt',
    );
    await tester.tap(find.text('Save'));
    await pumpFrames(tester, frames: 20);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not save this food'), findsOneWidget);
    expect(find.text('Yogurt'), findsOneWidget);
  });
}
