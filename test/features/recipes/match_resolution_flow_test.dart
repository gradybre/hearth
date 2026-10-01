import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/editor_draft_store.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/features/foods/food_draft.dart';
import 'package:hearth/features/foods/label_scan_controller.dart';

import '../../support/app_harness.dart' show pumpFrames;
import '../../support/fixtures.dart';
import '../foods/label_scan_test.dart' show FakeLabelReader;
import 'match_resolution_harness.dart';
import 'match_review_test.dart' show usda;

Finder action(int row, String action) => find.byKey(Key('match-$row-$action'));

class _DuplicateSource extends ResolutionSource {
  _DuplicateSource(this.first, this.second);
  final Food first;
  final Food second;
  int calls = 0;
  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    final food = calls++ == 0 ? first : second;
    return [
      NutritionMatch(
        food: food,
        source: food.source,
        confidence: 1,
        fromLibrary: true,
      ),
    ];
  }
}

void main() {
  testWidgets(
    'remembering repeated wording cannot silently remember the second food',
    (tester) async {
      final first = aFood('Olive oil', id: 'saved-first');
      final second = aFood('Olive oil', id: 'saved-second');
      final foods = ResolutionFoods()
        ..saved.addAll({first.id: first, second.id: second});
      final harness = await pumpResolution(
        tester,
        lines: '1 tbsp olive oil\n2 tbsp olive oil',
        foods: foods,
        source: _DuplicateSource(first, second),
      );
      await resolutionTap(tester, action(0, 'remember'));
      await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
      expect(harness.result, {'olive oil': first.id});
      expect(harness.result!.rememberIngredientNames, {'olive oil'});
    },
  );

  testWidgets(
    'skipping repeated wording cannot still map its other authored line',
    (tester) async {
      final first = aFood('Olive oil', id: 'saved-first');
      final second = aFood('Olive oil', id: 'saved-second');
      final foods = ResolutionFoods()
        ..saved.addAll({first.id: first, second.id: second});
      final harness = await pumpResolution(
        tester,
        lines: '1 tbsp olive oil\n2 tbsp olive oil',
        foods: foods,
        source: _DuplicateSource(first, second),
      );
      await resolutionTap(tester, action(0, 'remember'));
      await resolutionTap(tester, action(0, 'skip'));
      await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
      expect(harness.result, isEmpty);
      expect(harness.result!.rememberIngredientNames, isEmpty);
    },
  );

  testWidgets(
    'case and spacing variants show every amount in one resolution group',
    (tester) async {
      await pumpResolution(
        tester,
        lines: '1 tbsp Olive Oil\n2 tbsp olive   oil',
      );
      expect(find.text('1 tbsp Olive Oil'), findsOneWidget);
      expect(find.text('2 tbsp olive   oil'), findsOneWidget);
      expect(find.text('Applies to 2 recipe lines'), findsOneWidget);
      expect(find.byKey(const Key('match-1-search')), findsNothing);
      expect(find.text('0 of 1 resolved'), findsOneWidget);
    },
  );

  testWidgets(
    'ingredient camera mode scrolls long authored context at 320 by 568 with 3x text',
    (tester) async {
      final scanner = useResolutionScanner();
      await pumpResolution(
        tester,
        lines: '200 g low-fat cottage cheese, drained and brought to room temperature',
        size: const Size(320, 568),
        textScale: 3,
        cameraAvailable: true,
        reader: FakeLabelReader(),
      );
      await resolutionTap(tester, action(0, 'scan'));
      expect(scanner.starts, 1);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('synthetic-camera-preview')), findsOneWidget);
    },
  );

  testWidgets(
    'declining an old account restore dialog leaves the new account draft intact',
    (tester) async {
      final harness = await pumpResolution(tester);
      harness.drafts.found = EditorDraft(
        kind: 'food',
        payload: FoodDraft.blank()
            .copyWith(name: 'First account draft')
            .toJson(),
      );
      final second = EditorDraft(
        kind: 'food',
        payload: FoodDraft.blank()
            .copyWith(name: 'Second account draft')
            .toJson(),
      );
      harness.secondDrafts.found = second;
      await resolutionTap(tester, action(1, 'manual'));
      expect(find.text('Unfinished changes'), findsOneWidget);
      harness.container.read(resolutionIdentity.notifier).change();
      await pumpFrames(tester);
      await tester.tap(find.text('Discard them'));
      await pumpFrames(tester, frames: 20);
      expect(harness.secondDrafts.clears, 0);
      expect(harness.secondDrafts.found, same(second));
      expect(harness.drafts.clears, 0);
    },
  );

  testWidgets(
    'grouped search and manual capture keep every line and the explicit remember choice',
    (tester) async {
      final harness = await pumpResolution(
        tester,
        lines: '1 tbsp Olive Oil\n2 tbsp olive   oil\n200 g cottage cheese',
        source: ResolutionSource(
          answers: {
            'cottage cheese': [usda('Cottage cheese')],
          },
        ),
      );
      await resolutionTap(tester, action(0, 'search'));
      expect(find.text('Applies to 2 recipe lines'), findsWidgets);
      expect(find.text('1 tbsp Olive Oil\n2 tbsp olive   oil'), findsOneWidget);
      await resolutionTap(
        tester,
        find.byKey(const Key('ingredient-picker-manual')),
      );
      expect(find.text('1 tbsp Olive Oil\n2 tbsp olive   oil'), findsOneWidget);
      expect(find.text('Applies to 2 recipe lines'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Greek yogurt'),
        'Chosen olive oil',
      );
      await resolutionTap(tester, find.text('Save'));
      expect(find.text('Chosen olive oil'), findsOneWidget);
      expect(find.text('1 tbsp Olive Oil'), findsOneWidget);
      expect(find.text('2 tbsp olive   oil'), findsOneWidget);
      expect(find.text('2 of 2 resolved'), findsOneWidget);
      expect(find.byKey(const Key('match-2-search')), findsNothing);
      await resolutionTap(tester, action(0, 'remember'));
      await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
      expect(harness.result!.length, 2);
      expect(
        harness.result!.keys,
        containsAll(['Olive Oil', 'cottage cheese']),
      );
      expect(harness.result!.rememberIngredientNames, {'Olive Oil'});
      expect(
        harness.foods.saved[harness.result!['Olive Oil']]!.name,
        'Chosen olive oil',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'long ingredient camera preview and recovery actions are reachable at 3x ${brightness.name}',
      (tester) async {
        final scanner = useResolutionScanner();
        await pumpResolution(
          tester,
          lines: '200 g low-fat cottage cheese, drained and brought to room temperature',
          size: const Size(320, 568),
          textScale: 3,
          brightness: brightness,
          cameraAvailable: true,
          reader: FakeLabelReader(),
        );
        await resolutionTap(tester, action(0, 'scan'));
        final preview = find.byKey(const Key('synthetic-camera-preview'));
        await tester.ensureVisible(preview);
        await tester.pumpAndSettle();
        expect(preview.hitTestable(), findsOneWidget);
        expect(tester.getSize(preview).height, greaterThan(200));
        await resolutionTap(
          tester,
          find.byKey(const Key('ingredient-camera-label')),
        );
        expect(find.text('Read the label'), findsOneWidget);
        Navigator.of(tester.element(find.text('Read the label'))).pop();
        await pumpFrames(tester, frames: 20);
        await resolutionTap(
          tester,
          find.byKey(const Key('ingredient-camera-type')),
        );
        expect(
          find.byKey(const Key('ingredient-barcode-scroll')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Use the camera'));
        await pumpFrames(tester, frames: 20);
        expect(scanner.starts, 3);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'unavailable ingredient camera keeps recovery reachable at 3x ${brightness.name}',
      (tester) async {
        useResolutionScanner().unavailable = true;
        await pumpResolution(
          tester,
          lines: '200 g low-fat cottage cheese, drained and brought to room temperature',
          size: const Size(320, 568),
          textScale: 3,
          brightness: brightness,
          cameraAvailable: true,
          reader: FakeLabelReader(),
        );
        await resolutionTap(tester, action(0, 'scan'));
        expect(
          find.text(
            'The camera is not available. You can type the number instead.',
          ),
          findsOneWidget,
        );
        await resolutionTap(
          tester,
          find.byKey(const Key('ingredient-camera-type')),
        );
        expect(
          find.byKey(const Key('ingredient-barcode-scroll')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'late draft lookup cannot open a restore dialog over a newer route',
    (tester) async {
      final harness = await pumpResolution(tester);
      final lookup = Completer<EditorDraft?>();
      harness.drafts.onFind = () => lookup.future;
      await resolutionTap(tester, action(1, 'manual'));
      unawaited(harness.router.push<void>('/elsewhere'));
      await pumpFrames(tester, frames: 20);
      lookup.complete(
        EditorDraft(
          kind: 'food',
          payload: FoodDraft.blank().copyWith(name: 'Old draft').toJson(),
        ),
      );
      await pumpFrames(tester, frames: 20);
      expect(find.text('Another task'), findsOneWidget);
      expect(find.text('Unfinished changes'), findsNothing);
      expect(harness.drafts.clears, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current account restore and discard still act on their captured draft store',
    (tester) async {
      final harness = await pumpResolution(tester);
      harness.drafts.found = EditorDraft(
        kind: 'food',
        payload: FoodDraft.blank().copyWith(name: 'Restored food').toJson(),
      );
      await resolutionTap(tester, action(1, 'manual'));
      await tester.tap(find.text('Restore'));
      await pumpFrames(tester, frames: 20);
      expect(find.text('Restored food'), findsOneWidget);
      expect(harness.drafts.clears, 0);
      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester);
      await tester.tap(find.text('Discard'));
      await pumpFrames(tester, frames: 20);
      await resolutionTap(tester, action(1, 'manual'));
      await tester.tap(find.text('Discard them'));
      await pumpFrames(tester, frames: 20);
      expect(harness.drafts.clears, 1);
      expect(harness.secondDrafts.clears, 0);
      expect(find.text('Restored food'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'manual capture returns to its row, preserves choices, advances, and applies together',
    (tester) async {
      final harness = await pumpResolution(
        tester,
        source: ResolutionSource(
          answers: {
            'olive oil': [usda('Olive oil')],
          },
        ),
      );
      await resolutionTap(tester, action(0, 'remember'));
      await resolutionTap(tester, action(1, 'manual'));
      expect(find.text('200 g cottage cheese'), findsWidgets);
      expect(harness.returned, isFalse);
      await tester.enterText(
        find.widgetWithText(TextField, 'Greek yogurt'),
        'Cottage cheese from tub',
      );
      await resolutionTap(tester, find.text('Save'));
      expect(find.text('Cottage cheese from tub'), findsOneWidget);
      expect(find.text('Next ingredient'), findsOneWidget);
      expect(find.text('Next ingredient').hitTestable(), findsOneWidget);
      expect(find.text('2 of 3 resolved'), findsOneWidget);
      expect(harness.returned, isFalse);
      await resolutionTap(tester, action(2, 'skip'));
      expect(find.text('1 skipped for now'), findsOneWidget);
      await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
      expect(harness.returned, isTrue);
      expect(harness.result!.keys.toSet(), {'olive oil', 'cottage cheese'});
      expect(harness.result!.rememberIngredientNames, {'olive oil'});
      expect(harness.foods.saved, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling search, scan, manual entry, and label capture preserves choices',
    (tester) async {
      final reader = FakeLabelReader();
      final harness = await pumpResolution(
        tester,
        reader: reader,
        source: ResolutionSource(
          answers: {
            'olive oil': [usda('Olive oil')],
          },
        ),
      );
      for (final path in ['search', 'scan', 'manual', 'label']) {
        await resolutionTap(tester, action(1, path));
        expect(find.text('200 g cottage cheese'), findsWidgets);
        final context = tester.element(find.text('200 g cottage cheese').last);
        Navigator.of(context).pop();
        await pumpFrames(tester, frames: 20);
        expect(find.text('1 of 3 resolved'), findsOneWidget);
        expect(find.text('Olive oil'), findsOneWidget);
      }
      expect(reader.calls, 0);
      expect(harness.foods.attempts, isEmpty);
      expect(harness.returned, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search chooses a saved food without another library save', (
    tester,
  ) async {
    final foods = ResolutionFoods();
    final saved = aFood('Cottage cheese', id: 'cottage-saved');
    foods.saved[saved.id] = saved;
    final harness = await pumpResolution(tester, foods: foods);
    await resolutionTap(tester, action(1, 'search'));
    expect(find.text('200 g cottage cheese'), findsWidgets);
    await resolutionTap(tester, find.text('Cottage cheese'));
    expect(find.text('1 of 3 resolved'), findsOneWidget);
    expect(foods.attempts, isEmpty);
    await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
    expect(harness.result, {'cottage cheese': 'cottage-saved'});
    expect(harness.result!.rememberIngredientNames, isEmpty);
    expect(foods.attempts, isEmpty);
  });

  testWidgets(
    'external search passes ingredient context through review and save',
    (tester) async {
      final source = ResolutionSource();
      final harness = await pumpResolution(tester, source: source);
      source.answers = {
        'cottage cheese': [usda('Cottage cheese')],
      };
      await resolutionTap(tester, action(1, 'search'));
      await tester.pump(const Duration(milliseconds: 400));
      await pumpFrames(tester, frames: 20);
      await resolutionTap(tester, find.text('Cottage cheese'));
      expect(find.text('200 g cottage cheese'), findsWidgets);
      expect(harness.foods.saved, isEmpty);
      await resolutionTap(tester, find.text('Save'));
      expect(find.text('1 of 3 resolved'), findsOneWidget);
      expect(harness.foods.saved, hasLength(1));
      await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
      expect(
        harness.result!['cottage cheese'],
        harness.foods.saved.keys.single,
      );
      expect(harness.foods.attempts, hasLength(1));
    },
  );

  testWidgets(
    'barcode library hit returns to the same ingredient without saving it twice',
    (tester) async {
      final food = aFood(
        'Cottage cheese',
        id: 'barcode-food',
        barcode: '8002210111110',
      );
      final foods = ResolutionFoods()..saved[food.id] = food;
      final harness = await pumpResolution(
        tester,
        foods: foods,
        source: ResolutionSource(
          barcodes: {
            '8002210111110': NutritionMatch(
              food: food,
              source: food.source,
              confidence: 1,
              fromLibrary: true,
            ),
          },
        ),
      );
      await resolutionTap(tester, action(1, 'scan'));
      expect(find.text('200 g cottage cheese'), findsWidgets);
      await tester.enterText(find.byType(TextField), '8002210111110');
      await resolutionTap(tester, find.text('Look it up'));
      await resolutionTap(tester, find.text('Use it'));
      expect(find.text('Cottage cheese'), findsOneWidget);
      expect(find.text('Next ingredient').hitTestable(), findsOneWidget);
      expect(harness.foods.attempts, isEmpty);
    },
  );

  testWidgets('barcode miss keeps its line through manual entry', (
    tester,
  ) async {
    final harness = await pumpResolution(tester);
    await resolutionTap(tester, action(1, 'scan'));
    await tester.enterText(find.byType(TextField), '8002210111110');
    await resolutionTap(tester, find.text('Look it up'));
    await resolutionTap(tester, find.text('Add it by hand'));
    expect(find.text('200 g cottage cheese'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextField, 'Greek yogurt'),
      'Cottage cheese',
    );
    await resolutionTap(tester, find.text('Save'));
    expect(find.text('1 of 3 resolved'), findsOneWidget);
    expect(harness.foods.saved.values.single.barcode, '8002210111110');
  });

  testWidgets(
    'label reading is deliberate and saved food returns to its ingredient',
    (tester) async {
      final reader = FakeLabelReader();
      final harness = await pumpResolution(tester, reader: reader);
      await resolutionTap(tester, action(1, 'label'));
      expect(find.text('200 g cottage cheese'), findsWidgets);
      expect(reader.calls, 0);
      await resolutionTap(
        tester,
        find.byKey(ValueKey('${LabelSlot.nutrition}-library')),
      );
      expect(reader.calls, 0);
      await resolutionTap(tester, find.text('Read photos'));
      expect(reader.calls, 1);
      expect(find.text('200 g cottage cheese'), findsWidgets);
      expect(harness.foods.saved, isEmpty);
      await resolutionTap(tester, find.text('Save'));
      expect(find.text('1 of 3 resolved'), findsOneWidget);
      expect(harness.foods.saved.values.single.servingOptions, hasLength(2));
    },
  );

  testWidgets(
    'partial apply failure retries stable food ids and preserves review choices',
    (tester) async {
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
      expect(harness.returned, isFalse);
      expect(find.text('2 of 3 resolved'), findsOneWidget);
      expect(foods.saved, hasLength(1));
      await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
      expect(harness.result, hasLength(2));
      expect(foods.saved, hasLength(2));
      expect(foods.attempts, hasLength(3));
      expect(foods.attempts[1].id, foods.attempts[2].id);
      expect(foods.attempts[0].id, isNot(foods.attempts[1].id));
    },
  );

  testWidgets('manual save failure keeps values and can retry', (tester) async {
    final foods = ResolutionFoods()..failuresLeft = 1;
    final harness = await pumpResolution(tester, foods: foods);
    await resolutionTap(tester, action(1, 'manual'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Greek yogurt'),
      'Cottage cheese from tub',
    );
    await resolutionTap(tester, find.text('Save'));
    expect(find.textContaining('Could not save this food'), findsOneWidget);
    expect(find.text('Cottage cheese from tub'), findsOneWidget);
    expect(find.text('200 g cottage cheese'), findsWidgets);
    await resolutionTap(tester, find.text('Save'));
    expect(find.text('1 of 3 resolved'), findsOneWidget);
    expect(harness.foods.saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account change during a duplicate check prevents save or delivery',
    (tester) async {
      final pending = Completer<List<Food>>();
      final foods = ResolutionFoods()..onDuplicates = (_) => pending.future;
      final harness = await pumpResolution(tester, foods: foods);
      await resolutionTap(tester, action(1, 'manual'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      harness.container.read(resolutionIdentity.notifier).change();
      pending.complete([]);
      await pumpFrames(tester, frames: 20);
      expect(foods.attempts, isEmpty);
      expect(harness.returned, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'route change during save cannot pop the new route or deliver old matches',
    (tester) async {
      final pending = Completer<void>();
      final foods = ResolutionFoods()..onSave = (_) => pending.future;
      final harness = await pumpResolution(tester, foods: foods);
      await resolutionTap(tester, action(1, 'manual'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      harness.router.go('/elsewhere');
      await pumpFrames(tester, frames: 20);
      pending.complete();
      await pumpFrames(tester, frames: 20);
      expect(find.text('Another task'), findsOneWidget);
      expect(harness.result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an ingredient food draft is never written into a changed account',
    (tester) async {
      final harness = await pumpResolution(tester);
      await resolutionTap(tester, action(1, 'manual'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Greek yogurt'),
        'Private ingredient wording',
      );
      await tester.pump();
      harness.container.read(resolutionIdentity.notifier).change();
      await tester.pump(const Duration(seconds: 3));
      expect(harness.secondDrafts.saved, isEmpty);
    },
  );

  testWidgets(
    'an estimate stays opt-in and keeps its provenance when applied',
    (tester) async {
      final harness = await pumpResolution(
        tester,
        lines: '1 pinch asafoetida',
        estimates: const [
          AiEstimate(ingredient: '1 pinch asafoetida', kcal: 8),
        ],
      );
      expect(find.text('0 of 1 resolved'), findsOneWidget);
      expect(find.textContaining('AI estimate'), findsOneWidget);
      await resolutionTap(tester, action(0, 'accept'));
      await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
      expect(harness.foods.saved.values.single.source, FoodSource.aiEstimate);
      expect(harness.result!.rememberIngredientNames, isEmpty);
    },
  );

  testWidgets('skipping everything returns no matches and no new foods', (
    tester,
  ) async {
    final harness = await pumpResolution(tester);
    for (int i = 0; i < 3; i++) {
      await resolutionTap(tester, action(i, 'skip'));
    }
    expect(find.text('0 of 3 resolved'), findsOneWidget);
    await resolutionTap(tester, find.byKey(const Key('match-review-apply')));
    expect(harness.returned, isTrue);
    expect(harness.result, isEmpty);
    expect(harness.foods.attempts, isEmpty);
  });

  testWidgets(
    'retry after food save but failed draft cleanup reuses the saved id',
    (tester) async {
      final harness = await pumpResolution(tester);
      harness.drafts.clearFailuresLeft = 1;
      await resolutionTap(tester, action(1, 'manual'));
      await resolutionTap(tester, find.text('Save'));
      expect(harness.foods.saved, hasLength(1));
      await resolutionTap(tester, find.text('Save'));
      expect(find.text('1 of 3 resolved'), findsOneWidget);
      expect(harness.foods.saved, hasLength(1));
      expect(harness.foods.attempts.first.id, harness.foods.attempts.last.id);
    },
  );

  testWidgets('an external ingredient search result remains readable at 3x', (
    tester,
  ) async {
    final source = ResolutionSource();
    await pumpResolution(
      tester,
      source: source,
      size: const Size(320, 568),
      textScale: 3,
    );
    source.answers = {
      'cottage cheese': [usda('Cottage cheese')],
    };
    await resolutionTap(tester, action(1, 'search'));
    await tester.pump(const Duration(milliseconds: 400));
    await pumpFrames(tester, frames: 20);
    await resolutionTap(
      tester,
      find.descendant(
        of: find.byKey(const Key('ingredient-food-picker-scroll')),
        matching: find.text('Cottage cheese'),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('200 g cottage cheese'), findsWidgets);
  });

  testWidgets(
    'cancelling a changed capture keeps review choices after the discard dialog',
    (tester) async {
      final harness = await pumpResolution(
        tester,
        source: ResolutionSource(
          answers: {
            'olive oil': [usda('Olive oil')],
          },
        ),
      );
      await resolutionTap(tester, action(1, 'manual'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Greek yogurt'),
        'Unsaved cottage cheese',
      );
      await resolutionTap(tester, find.text('Cancel'));
      await resolutionTap(tester, find.text('Keep editing'));
      expect(find.text('Unsaved cottage cheese'), findsOneWidget);
      await resolutionTap(tester, find.text('Cancel'));
      await resolutionTap(tester, find.text('Discard'));
      expect(find.text('1 of 3 resolved'), findsOneWidget);
      expect(harness.foods.attempts, isEmpty);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('resolution actions fit 320 by 568 at 3x ${brightness.name}', (
      tester,
    ) async {
      await pumpResolution(
        tester,
        size: const Size(320, 568),
        textScale: 3,
        brightness: brightness,
        source: ResolutionSource(
          answers: {
            'olive oil': [usda('Olive oil')],
          },
        ),
        reader: FakeLabelReader(),
      );
      expect(tester.takeException(), isNull);
      await resolutionTap(tester, action(1, 'search'));
      expect(tester.takeException(), isNull);
      await resolutionTap(
        tester,
        find.byKey(const Key('ingredient-picker-manual')),
      );
      expect(find.text('200 g cottage cheese'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cancel'));
      await pumpFrames(tester, frames: 20);
      Navigator.of(tester.element(find.text('200 g cottage cheese').last))
          .pop();
      await pumpFrames(tester, frames: 20);
      await resolutionTap(tester, action(1, 'scan'));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Look it up'));
      await tester.pumpAndSettle();
      expect(find.text('Look it up').hitTestable(), findsOneWidget);
      Navigator.of(tester.element(find.text('Scan a barcode'))).pop();
      await pumpFrames(tester, frames: 20);
      await resolutionTap(tester, action(1, 'label'));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Read photos'));
      await tester.pumpAndSettle();
      expect(find.text('Read photos').hitTestable(), findsOneWidget);
    });
  }
}
