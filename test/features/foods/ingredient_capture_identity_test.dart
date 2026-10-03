import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/features/foods/food_editor_screen.dart';
import 'package:hearth/features/foods/label_scan_controller.dart';
import 'package:hearth/features/recipes/recipe_editor_screen.dart';

import '../../support/app_harness.dart'
    show addRecipeVia, pumpFrames, pumpHearthApp;
import '../../support/fixtures.dart';
import '../recipes/match_resolution_harness.dart';
import 'label_scan_test.dart' show FakeCamera, FakeLabelReader, cheddar;

const _barcode = '8002210111110';
const _authoredIngredient = '200 g cottage cheese';

enum _LabelPath {
  barcodeMiss('barcode miss'),
  noBarcode('no barcode'),
  externalFood('external food found');

  const _LabelPath(this.description);
  final String description;
}

class _PendingLabelReader extends FakeLabelReader {
  final pending = Completer<LabelReading>();

  @override
  Future<LabelReading> read(List<AiImage> images) {
    calls++;
    lastImages = images;
    return pending.future;
  }
}

ResolutionSource _sourceFor(_LabelPath path) => ResolutionSource(
  barcodes: path == _LabelPath.externalFood
      ? {
          _barcode: NutritionMatch(
            food: aFood(
              'Synthetic database cottage cheese',
              id: 'external-label-fixture',
              barcode: _barcode,
              source: FoodSource.openFoodFacts,
            ),
            source: FoodSource.openFoodFacts,
            confidence: 0.2,
          ),
        }
      : const {},
);

Future<void> _startLabelRead(WidgetTester tester, _LabelPath path) async {
  await resolutionTap(tester, find.byKey(const Key('match-1-scan')));
  if (path == _LabelPath.noBarcode) {
    await resolutionTap(tester, find.text('No barcode? Read the label'));
  } else {
    await tester.enterText(find.byType(TextField), _barcode);
    await resolutionTap(tester, find.text('Look it up'));
    await resolutionTap(tester, find.text('Read the label'));
  }
  await resolutionTap(
    tester,
    find.byKey(ValueKey('${LabelSlot.nutrition}-library')),
  );
  await resolutionTap(tester, find.text('Read photos'));
}

Future<void> _tapApp(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await pumpFrames(tester, frames: 20);
}

void main() {
  for (final path in _LabelPath.values) {
    for (final roundTrip in [false, true]) {
      testWidgets(
        '${path.description}: pending ingredient label read expires on '
        '${roundTrip ? 'account away and back' : 'account change'}',
        (tester) async {
          final reader = _PendingLabelReader();
          final foods = ResolutionFoods();
          final harness = await pumpResolution(
            tester,
            foods: foods,
            source: _sourceFor(path),
            reader: reader,
          );
          final saveIdentities = <String>[];
          foods.onSave = (_) async {
            saveIdentities.add(
              '${harness.container.read(currentUserIdProvider)}/'
              '${harness.container.read(currentHouseholdIdProvider)}',
            );
          };

          await _startLabelRead(tester, path);
          expect(reader.calls, 1, reason: 'The read must actually be pending.');
          expect(reader.pending.isCompleted, isFalse);
          expect(find.byType(FoodEditorScreen), findsNothing);
          expect(foods.attempts, isEmpty);

          harness.container.read(resolutionIdentity.notifier).change();
          await tester.pump();
          if (roundTrip) {
            expect(harness.container.read(currentUserIdProvider), 'second');
            harness.container.invalidate(resolutionIdentity);
            await tester.pump();
            expect(harness.container.read(currentUserIdProvider), 'first');
            expect(
              harness.container.read(currentHouseholdIdProvider),
              'household-first',
            );
          }
          reader.pending.complete(cheddar());
          await pumpFrames(tester, frames: 20);

          final editor = find.byType(FoodEditorScreen);
          final openedEditor = editor.evaluate().isNotEmpty;
          final carriedOldIngredient = find
              .descendant(of: editor, matching: find.text(_authoredIngredient))
              .evaluate()
              .isNotEmpty;
          // If the stale continuation exposed an editor, exercise its ordinary
          // Save action too. This distinguishes rejection on eventual return to
          // recipe review from protection of the new account's write boundary.
          if (openedEditor) {
            await resolutionTap(tester, find.text('Save'));
          }
          expect(tester.takeException(), isNull);
          expect(
            {
              'new editor opened': openedEditor,
              'old ingredient carried into new editor': carriedOldIngredient,
              'food save attempts': foods.attempts.length,
              'saved foods': foods.saved.length,
              'identity at save': saveIdentities,
              'new identity draft clears': harness.secondDrafts.clears,
              'review returned': harness.returned,
            },
            {
              'new editor opened': false,
              'old ingredient carried into new editor': false,
              'food save attempts': 0,
              'saved foods': 0,
              'identity at save': <String>[],
              'new identity draft clears': 0,
              'review returned': false,
            },
            reason:
                'The scanner belongs to the first user and household. Completing '
                'its old label read must not open an editor under the new identity '
                'or allow a food write there.',
          );
        },
      );
    }

    testWidgets(
      '${path.description}: same-account label review can save for its ingredient',
      (tester) async {
        final reader = _PendingLabelReader();
        final foods = ResolutionFoods();
        final harness = await pumpResolution(
          tester,
          foods: foods,
          source: _sourceFor(path),
          reader: reader,
        );
        final saveIdentities = <String>[];
        foods.onSave = (_) async {
          saveIdentities.add(
            '${harness.container.read(currentUserIdProvider)}/'
            '${harness.container.read(currentHouseholdIdProvider)}',
          );
        };

        await _startLabelRead(tester, path);
        expect(reader.calls, 1);
        expect(reader.pending.isCompleted, isFalse);
        reader.pending.complete(cheddar());
        await pumpFrames(tester, frames: 20);

        expect(find.byType(FoodEditorScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(FoodEditorScreen),
            matching: find.text(_authoredIngredient),
          ),
          findsOneWidget,
        );
        expect(foods.attempts, isEmpty);
        await resolutionTap(tester, find.text('Save'));

        expect(find.text('1 of 3 resolved'), findsOneWidget);
        expect(foods.saved, hasLength(1));
        expect(foods.saved.values.single.servingOptions, hasLength(2));
        expect(
          foods.saved.values.single.barcode,
          path == _LabelPath.noBarcode ? isNull : _barcode,
        );
        expect(saveIdentities, ['first/household-first']);
        expect(harness.drafts.clears, 1);
        expect(harness.secondDrafts.clears, 0);
        expect(harness.returned, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final transition in ['changed', 'away and back', 'unchanged']) {
    final changeHousehold = transition != 'unchanged';
    testWidgets(
      changeHousehold
          ? 'recipe packet repair: pending label cannot edit cached food after household $transition'
          : 'recipe packet repair: same-household review saves the existing food',
      (tester) async {
        const authoredLine = '2 tbsp white onion, finely chopped';
        const foodId = 'onion-capture-household-a';
        final onion = aFoodPer100g(
          'White onion',
          id: foodId,
          kcal: 40,
        ).withHousehold('household-first');
        final reader = _PendingLabelReader();
        final libraryChanges = StreamController<List<Food>>.broadcast();
        addTearDown(libraryChanges.close);
        Stream<List<Food>> library() async* {
          yield [onion];
          yield* libraryChanges.stream;
        }

        // HearthApp's production router and food repository remain real.
        // Only the household-provider signal changes: the current user stays
        // signed in, and the old household row remains in the local cache.
        final db = await pumpHearthApp(
          tester,
          foods: [onion],
          foodStream: library(),
          labelReader: reader,
          photoPicker: FakeCamera(),
          extraOverrides: [
            currentHouseholdIdProvider.overrideWith(
              (ref) => 'household-${ref.watch(resolutionIdentity)}',
            ),
          ],
        );
        await addRecipeVia(tester, 'Write a recipe');
        await pumpFrames(tester, frames: 20);
        await tester.enterText(
          find.widgetWithText(TextField, 'Braised short ribs'),
          'Pending label repair supper',
        );
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                (widget.decoration?.hintText ?? '').startsWith(
                  '2 tbsp olive oil',
                ),
          ),
          authoredLine,
        );
        await pumpFrames(tester, frames: 20);
        await _tapApp(tester, find.text('white onion, finely chopped'));
        await _tapApp(tester, find.text('White onion'));
        await _tapApp(tester, find.text('white onion, finely chopped'));
        expect(find.text('Add a serving in tbsp'), findsOneWidget);
        await _tapApp(tester, find.text("Read the packet's label"));
        await _tapApp(
          tester,
          find.byKey(ValueKey('${LabelSlot.nutrition}-library')),
        );
        await _tapApp(tester, find.text('Read photos'));
        expect(reader.calls, 1);
        expect(reader.pending.isCompleted, isFalse);
        expect(find.byType(FoodEditorScreen), findsNothing);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(RecipeEditorScreen, skipOffstage: false)),
          listen: false,
        );
        final originalUser = container.read(currentUserIdProvider);
        expect(container.read(currentHouseholdIdProvider), 'household-first');
        if (changeHousehold) {
          container.read(resolutionIdentity.notifier).change();
          libraryChanges.add([]);
          await pumpFrames(tester, frames: 4);
          expect(
            container.read(currentHouseholdIdProvider),
            'household-second',
          );
          expect(container.read(currentUserIdProvider), originalUser);
          expect(container.read(foodLibraryProvider).value, isEmpty);
          if (transition == 'away and back') {
            container.invalidate(resolutionIdentity);
            libraryChanges.add([onion]);
            await pumpFrames(tester, frames: 4);
            expect(
              container.read(currentHouseholdIdProvider),
              'household-first',
            );
          }
        }
        reader.pending.complete(cheddar());
        await pumpFrames(tester, frames: 20);

        final editor = find.byType(FoodEditorScreen);
        final openedEditor = editor.evaluate().isNotEmpty;
        final carriedOldIngredient = find
            .descendant(of: editor, matching: find.text(authoredLine))
            .evaluate()
            .isNotEmpty;
        if (openedEditor) {
          expect(tester.widget<FoodEditorScreen>(editor).foodId, foodId);
          await _tapApp(tester, find.text('Save'));
        }
        final saved = await FoodStore(db).byId(foodId);
        final foodWrites = (await PendingWriteStore(db).pending())
            .where(
              (write) =>
                  write.entityTable == 'foods' && write.entityId == foodId,
            )
            .toList();
        expect(tester.takeException(), isNull);

        if (changeHousehold) {
          expect(
            {
              'existing food editor opened': openedEditor,
              'old ingredient carried into editor': carriedOldIngredient,
              'cached food household': saved?.householdId,
              'cached food serving count': saved?.servingOptions.length,
              'queued food write households': foodWrites
                  .map((write) => write.payload['household_id'])
                  .toList(),
            },
            {
              'existing food editor opened': false,
              'old ingredient carried into editor': false,
              'cached food household': 'household-first',
              'cached food serving count': 1,
              'queued food write households': <String>[],
            },
            reason:
                'The old recipe label request must expire before routing to '
                'the cached food. A fresh editor must not reassign that food '
                'ID to the current household or queue that write.',
          );
        } else {
          expect(openedEditor, isTrue);
          expect(carriedOldIngredient, isTrue);
          expect(saved?.householdId, 'household-first');
          expect(saved?.servingOptions, hasLength(3));
          expect(foodWrites, hasLength(1));
          expect(foodWrites.single.payload['household_id'], 'household-first');
        }
      },
    );
  }
}
