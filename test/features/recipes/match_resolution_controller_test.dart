import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/nutrition_lookup.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/domain/parsing/ingredient_parser.dart';
import 'package:hearth/features/recipes/match_review_controller.dart';

import '../../support/fixtures.dart';
import 'match_resolution_harness.dart';
import 'match_review_test.dart' show usda;

class _DelayedSource extends ResolutionSource {
  final first = Completer<List<NutritionMatch>>();
  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) =>
      query == 'first' ? first.future : Future.value([usda(query)]);
}

ProviderContainer _container(NutritionSource source) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWith(
        (ref) => ref.watch(resolutionIdentity),
      ),
      currentHouseholdIdProvider.overrideWithValue('fixture-household'),
      nutritionLookupProvider.overrideWithValue(NutritionLookup([source])),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'normalized wording keeps all authored quantities in one resolution group',
    () async {
      final source = ResolutionSource();
      final container = _container(source);
      final controller = container.read(matchReviewProvider.notifier);
      await controller.findMatches([
        IngredientParser.parse('1 tbsp Olive Oil'),
        IngredientParser.parse('2 tbsp olive   oil'),
        IngredientParser.parse('200 g cottage cheese'),
        IngredientParser.parse('1 tbsp olive oil (optional)'),
      ]);
      var state = container.read(matchReviewProvider) as MatchReviewReady;
      expect(source.queries, ['Olive Oil', 'cottage cheese']);
      expect(state.rows, hasLength(2));
      expect(state.rows.first.authoredLines, [
        '1 tbsp Olive Oil',
        '2 tbsp olive   oil',
      ]);
      expect(
        state.rows.first.ingredients.map(
          (line) => line.quantity!.amountIn(line.quantity!.preferredUnit!),
        ),
        [1, 2],
      );
      controller.replaceWithSavedFood(0, aFood('Olive oil', id: 'shared-oil'));
      controller.setRemember(0, remember: true);
      state = container.read(matchReviewProvider) as MatchReviewReady;
      expect(state.resolvedCount, 1);
      expect(state.rows.first.lineCount, 2);
      expect(state.rows.first.remember, isTrue);
      expect(state.nextUnresolvedAfter(0), 1);
      controller.skip(0);
      state = container.read(matchReviewProvider) as MatchReviewReady;
      expect(state.rows.first.remember, isFalse);
      expect(state.rows.first.skipped, isTrue);
      expect(state.rows.first.lineCount, 2);
      expect(state.resolvedCount, 0);
    },
  );

  test('replacing a row keeps other choices, authored text, and explicit remembering', () async {
    final container = _container(
      ResolutionSource(
        answers: {
          'olive oil': [usda('Olive oil')],
        },
      ),
    );
    final controller = container.read(matchReviewProvider.notifier);
    await controller.findMatches([
      IngredientParser.parse('100 g olive oil'),
      IngredientParser.parse('200 g cottage cheese'),
      IngredientParser.parse('1 pinch asafoetida'),
    ]);
    controller.setRemember(0, remember: true);
    controller.replaceWithSavedFood(
      1,
      aFood('Cottage cheese', id: 'saved-cheese'),
    );
    final state = container.read(matchReviewProvider) as MatchReviewReady;
    expect(state.rows[0].remember, isTrue);
    expect(state.rows[1].authoredLine, '200 g cottage cheese');
    expect(state.rows[1].fromLibrary, isTrue);
    expect(state.rows[1].food!.id, 'saved-cheese');
    expect(state.resolvedCount, 2);
    expect(state.nextUnresolvedAfter(1), 2);
    controller.skip(2);
    final finished = container.read(matchReviewProvider) as MatchReviewReady;
    expect(finished.nextUnresolvedAfter(1), isNull);
    expect(finished.skippedCount, 1);
    expect(finished.resolvedCount, 2);
  });

  test('unchecking a suggestion revisits it without forgetting another accepted row', () async {
    final container = _container(
      ResolutionSource(
        answers: {
          'olive oil': [usda('Olive oil')],
          'cottage cheese': [usda('Cottage cheese')],
        },
      ),
    );
    final controller = container.read(matchReviewProvider.notifier);
    await controller.findMatches([
      IngredientParser.parse('100 g olive oil'),
      IngredientParser.parse('200 g cottage cheese'),
    ]);
    controller.setAccepted(0, accepted: false);
    final state = container.read(matchReviewProvider) as MatchReviewReady;
    expect(state.resolvedCount, 1);
    expect(state.nextUnresolvedAfter(1), 0);
    expect(state.rows[1].accepted, isTrue);
  });

  test('a late lookup cannot replace a newer review', () async {
    final source = _DelayedSource();
    final container = _container(source);
    final controller = container.read(matchReviewProvider.notifier);
    final old = controller.findMatches([IngredientParser.parse('1 g first')]);
    await controller.findMatches([IngredientParser.parse('1 g second')]);
    source.first.complete([usda('first')]);
    await old;
    expect(
      (container.read(
        matchReviewProvider,
      ) as MatchReviewReady).rows.single.ingredient.name,
      'second',
    );
  });

  test('an account change invalidates an outstanding lookup', () async {
    final source = _DelayedSource();
    final container = _container(source);
    final old = container.read(matchReviewProvider.notifier).findMatches([
      IngredientParser.parse('1 g first'),
    ]);
    container.read(resolutionIdentity.notifier).change();
    await container.pump();
    expect(container.read(matchReviewProvider), isA<MatchReviewIdle>());
    source.first.complete([usda('first')]);
    await old;
    expect(container.read(matchReviewProvider), isA<MatchReviewIdle>());
  });
}
