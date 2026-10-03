import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/domain/parsing/ingredient_parser.dart';
import 'package:hearth/features/recipes/match_review_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import 'match_review_test.dart' show StubSource, usda;

class _Foods extends Mock implements FoodRepository {}

Future<void> _open(
  WidgetTester tester, {
  required String lines,
  Map<String, List<NutritionMatch>> answers = const {},
  FoodRepository? repository,
}) async {
  await pumpHearthApp(
    tester,
    nutritionSources: [StubSource(answers)],
    extraOverrides: [
      if (repository != null)
        foodRepositoryProvider.overrideWithValue(repository),
    ],
  );
  final BuildContext context = tester.element(find.byType(Scaffold).first);
  unawaited(
    showMatchReview(
      context,
      ingredients: lines.split('\n').map(IngredientParser.parse).toList(),
    ),
  );
  await pumpFrames(tester, frames: 20);
}

void main() {
  setUpAll(() => registerFallbackValue(aFood('Fallback')));

  testWidgets('an unmatched review row retains its authored amount', (
    tester,
  ) async {
    await _open(tester, lines: '1 pinch of asafoetida');
    expect(find.text('1 pinch of asafoetida'), findsOneWidget);
  });

  testWidgets('a failed batch save stays reviewable and offers a retry', (
    tester,
  ) async {
    final repository = _Foods();
    when(() => repository.byId(any())).thenAnswer((_) async => null);
    when(() => repository.save(any())).thenThrow(StateError('disk full'));
    await _open(
      tester,
      lines: '100 g olive oil',
      answers: {
        'olive oil': [usda('Olive oil')],
      },
      repository: repository,
    );
    await tester.ensureVisible(find.byKey(const Key('match-review-apply')));
    await tester.tap(find.byKey(const Key('match-review-apply')));
    await pumpFrames(tester, frames: 20);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not apply'), findsOneWidget);
    expect(find.text('100 g olive oil'), findsOneWidget);
  });

  testWidgets('applying a library match reuses its food without another save', (
    tester,
  ) async {
    final repository = _Foods();
    final food = aFood('Olive oil', id: 'already-saved');
    when(() => repository.byId(food.id)).thenAnswer((_) async => food);
    when(() => repository.save(any())).thenAnswer((_) async {});
    await _open(
      tester,
      lines: '100 g olive oil',
      answers: {
        'olive oil': [
          NutritionMatch(
            food: food,
            source: food.source,
            confidence: 1,
            fromLibrary: true,
          ),
        ],
      },
      repository: repository,
    );
    await tester.ensureVisible(find.byKey(const Key('match-review-apply')));
    await tester.tap(find.byKey(const Key('match-review-apply')));
    await pumpFrames(tester, frames: 20);
    verifyNever(() => repository.save(any()));
  });
}
