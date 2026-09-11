import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/recipes/repair_queue.dart';

import '../support/fixtures.dart';

/// What the repair queue reports while the two libraries are answering.
///
/// It needs both: a queue built while the foods are still loading would
/// report every matched line as unmatched, which is the one thing a repair
/// list must never do. The question this file settles is what it says in the
/// three states that are not "both arrived".
void main() {
  ProviderContainer containerWith({
    required AsyncValue<List<Recipe>> recipes,
    required AsyncValue<List<Food>> foods,
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        recipeLibraryProvider.overrideWith(
          (Ref ref) => switch (recipes) {
            AsyncData<List<Recipe>>(:final List<Recipe> value) =>
              Stream<List<Recipe>>.value(value),
            AsyncError<List<Recipe>>(:final Object error) =>
              Stream<List<Recipe>>.error(error),
            _ => const Stream<List<Recipe>>.empty(),
          },
        ),
        foodLibraryProvider.overrideWith(
          (Ref ref) => switch (foods) {
            AsyncData<List<Food>>(:final List<Food> value) =>
              Stream<List<Food>>.value(value),
            AsyncError<List<Food>>(:final Object error) =>
              Stream<List<Food>>.error(error),
            _ => const Stream<List<Food>>.empty(),
          },
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Subscribes and lets the one-shot streams deliver.
  ///
  /// `read` alone starts the provider and returns the first frame, which for
  /// a stream is always `loading` — so a test that only read would say
  /// "loading" whatever the stream went on to do.
  Future<void> settle(ProviderContainer container) async {
    container.listen(
      repairQueueProvider,
      (AsyncValue<RepairQueue>? previous, AsyncValue<RepairQueue> next) {},
      fireImmediately: true,
    );
    for (int i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('it waits while the foods are still being read', () async {
    final ProviderContainer container = containerWith(
      recipes: AsyncValue<List<Recipe>>.data(<Recipe>[aRecipe(id: 'r')]),
      foods: const AsyncValue<List<Food>>.loading(),
    );

    expect(container.read(repairQueueProvider).isLoading, isTrue);
  });

  test('and reports a library that could not be read, rather than waiting '
      'for ever', () async {
    // The screen renders `loading` as a spinner with no words. A food store
    // that throws — a corrupt row, a migration that did not land — would have
    // spun there until the app was killed, saying nothing.
    final ProviderContainer container = containerWith(
      recipes: AsyncValue<List<Recipe>>.data(<Recipe>[aRecipe(id: 'r')]),
      foods: AsyncValue<List<Food>>.error(
        StateError('the food table is unreadable'),
        StackTrace.empty,
      ),
    );
    await settle(container);

    final AsyncValue<RepairQueue> queue = container.read(repairQueueProvider);
    expect(queue.hasError, isTrue);
    expect(queue.isLoading, isFalse);
  });

  test('and a recipe library that could not be read', () async {
    final ProviderContainer container = containerWith(
      recipes: AsyncValue<List<Recipe>>.error(
        StateError('the recipe table is unreadable'),
        StackTrace.empty,
      ),
      foods: const AsyncValue<List<Food>>.data(<Food>[]),
    );
    await settle(container);

    expect(container.read(repairQueueProvider).hasError, isTrue);
  });
}
