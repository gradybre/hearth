import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import 'match_resolution_harness.dart';
import 'match_review_test.dart' show usda;

Future<ResolutionHarness> _failAfterFirstSave(WidgetTester tester) async {
  final foods = ResolutionFoods()..failAttempt = 2;
  final harness = await pumpResolution(
    tester,
    foods: foods,
    source: ResolutionSource(
      answers: {
        'olive oil': [usda('Olive oil')],
        'cottage cheese': [usda('Cottage cheese')],
      },
    ),
  );
  await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
  expect(find.textContaining('Could not apply'), findsOneWidget);
  expect(find.text('2 of 3 resolved'), findsOneWidget);
  expect(harness.returned, isFalse);
  expect(foods.saved, hasLength(1));
  expect(foods.attempts, hasLength(2));
  expect(tester.takeException(), isNull);
  return harness;
}

void main() {
  for (final unavailableState in ['deleted', 'modifier']) {
    testWidgets(
      'partial Apply retry rejects the first saved food when it becomes $unavailableState',
      (tester) async {
        final harness = await _failAfterFirstSave(tester);
        final foods = harness.foods;
        final firstFood = foods.saved.values.single;
        final unavailable = unavailableState == 'deleted'
            ? firstFood.withDeleted()
            : firstFood.asModifier();
        foods.saved[firstFood.id] = unavailable;

        await resolutionTap(
          tester,
          find.byKey(const Key('match-review-apply')),
        );
        expect(tester.takeException(), isNull);
        expect(
          {
            'review returned': harness.returned,
            'unavailable id returned':
                harness.result?.values.contains(firstFood.id) ?? false,
            'review remains open': find
                .byKey(const Key('match-review-apply'))
                .evaluate()
                .isNotEmpty,
            'retry error shown': find
                .textContaining(RegExp('Could not apply|no longer available'))
                .evaluate()
                .isNotEmpty,
            'unavailable record preserved': identical(
              foods.saved[firstFood.id],
              unavailable,
            ),
            'first food save attempts': foods.attempts
                .where((food) => food.id == firstFood.id)
                .length,
          },
          {
            'review returned': false,
            'unavailable id returned': false,
            'review remains open': true,
            'retry error shown': true,
            'unavailable record preserved': true,
            'first food save attempts': 1,
          },
          reason:
              'A stable ID from a partial Apply is not proof that the food is '
              'still available. Retry must revalidate it without resurrecting '
              'the saved food or returning its unavailable ID to the recipe.',
        );
      },
    );
  }

  testWidgets(
    'partial Apply retry keeps stable ids when the first saved food is unchanged',
    (tester) async {
      final harness = await _failAfterFirstSave(tester);
      final foods = harness.foods;
      final firstFood = foods.saved.values.single;
      await resolutionTap(tester, find.byKey(const Key('match-review-apply')));

      expect(harness.returned, isTrue);
      expect(harness.result, hasLength(2));
      expect(harness.result!['olive oil'], firstFood.id);
      expect(foods.saved, hasLength(2));
      expect(identical(foods.saved[firstFood.id], firstFood), isTrue);
      expect(foods.attempts, hasLength(3));
      expect(foods.attempts[1].id, foods.attempts[2].id);
      expect(foods.attempts[0].id, isNot(foods.attempts[1].id));
      expect(tester.takeException(), isNull);
    },
  );
}
