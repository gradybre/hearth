import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_icon.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/recipe_photo_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/sync/photo_sync.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/planning/day_format.dart';
import 'package:hearth/domain/planning/meal_plan.dart';
import 'package:hearth/domain/planning/week.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/plan/log_sheet.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';
import 'package:hearth/features/recipes/recipe_editor_args.dart';
import 'package:hearth/features/recipes/recipe_editor_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fake_photo_storage.dart';
import '../../support/fixtures.dart';
import '../../support/swept_surfaces.dart';
import 'restaurant_usual_fixtures.dart';

const String _usualSketch =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">'
    '<path d="M4 12h16M5 14c2 6 12 6 14 0"/></svg>';

class _NoDrawing implements RecipeIconSource {
  final List<String> titles = <String>[];

  @override
  Future<String?> draw({required String title}) async {
    titles.add(title);
    return null;
  }
}

final Uint8List _localHero = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZXsAAAAASUVORK5CYII=',
);

final Uint8List _chosenHero = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _ChosenPhoto implements PhotoPicker {
  int selections = 0;

  @override
  bool get canUseCamera => false;

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async {
    selections++;
    return PickedPhoto(bytes: _chosenHero, extension: 'png');
  }

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async =>
      const <PickedPhoto>[];
}

class _VariationPhotoStore extends RecipePhotoStore {
  _VariationPhotoStore(
    super.database, {
    required super.directory,
    this.failCopies = 0,
  });

  int failCopies;
  int copyAttempts = 0;
  Completer<void>? _copyObserved;
  Future<void> Function()? beforeCopy;

  Future<void> observeNextCopy() {
    _copyObserved = Completer<void>();
    return _copyObserved!.future;
  }

  @override
  Future<void> save({
    required String recipeId,
    required Uint8List bytes,
    required String extension,
    required DateTime now,
  }) async {
    final bool variation = recipeId != 'saved-usual';
    try {
      if (variation) {
        copyAttempts++;
        if (beforeCopy case final Future<void> Function() callback) {
          beforeCopy = null;
          await callback();
        }
        if (failCopies > 0) {
          failCopies--;
          throw const FileSystemException('Synthetic photo copy failure');
        }
      }
      await super.save(
        recipeId: recipeId,
        bytes: bytes,
        extension: extension,
        now: now,
      );
    } finally {
      if (variation && !(_copyObserved?.isCompleted ?? true)) {
        _copyObserved!.complete();
      }
    }
  }
}

class _HeldPhotoStorage extends FakePhotoStorage {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<Uint8List> download(String path) async {
    started.complete();
    await release.future;
    return super.download(path);
  }
}

void main() {
  for (final bool pendingReplacement in <bool>[false, true]) {
    testWidgets(
      'variation keeps current local photo despite sync (replacement $pendingReplacement)',
      (WidgetTester tester) async {
        final Directory directory = Directory.systemTemp.createTempSync(
          'hearth-variation-photo-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final Recipe original = savedUsual().copyWith(
          iconSvg: _usualSketch,
          photoUrl: pendingReplacement ? 'saved-usual/older-photo.png' : null,
        );
        final _NoDrawing icons = _NoDrawing();
        final _HeldPhotoStorage storage = _HeldPhotoStorage()
          ..objects['saved-usual/older-photo.png'] = _chosenHero;
        Future<PhotoSyncResult>? pendingPull;
        late _VariationPhotoStore photos;
        final HearthDatabase db = await _openVariation(
          tester,
          original: original,
          icons: icons,
          extraOverrides: <Object>[
            recipePhotoStoreProvider.overrideWith(
              (ref) => _VariationPhotoStore(
                ref.watch(databaseProvider),
                directory: () async => directory,
              ),
            ),
          ],
          beforeOpening: (HearthDatabase database) async {
            photos = ProviderScope.containerOf(
              tester.element(find.byType(Scaffold).first),
            ).read(recipePhotoStoreProvider) as _VariationPhotoStore;
            await tester.runAsync(
              () => photos.save(
                recipeId: original.id,
                bytes: _localHero,
                extension: 'png',
                now: DateTime.utc(2026, 10, 1),
              ),
            );
            if (pendingReplacement) {
              final PhotoSync sync = PhotoSync(
                database: database,
                photos: photos,
                recipes: ProviderScope.containerOf(
                  tester.element(find.byType(Scaffold).first),
                ).read(recipeRepositoryProvider),
                storage: storage,
              );
              photos.beforeCopy = () async {
                pendingPull = sync.pull();
                // Under the bug the old download starts and is held until
                // after the local copy. With no old URL exposed, pull ends.
                await Future.any<Object?>(<Future<Object?>>[
                  storage.started.future,
                  pendingPull!,
                ]);
              };
            }
          },
        );
        final RecipeRow sourceBefore =
            (await db.select(db.recipes).get()).single;
        final RecipePhotoRow photoBefore =
            (await db.select(db.recipePhotos).get()).single;
        await _saveWithPhotoIo(tester, photos);
        storage.release.complete();
        if (pendingPull != null) {
          await tester.runAsync(() => pendingPull!);
          await pumpFrames(tester);
        }

        final List<RecipeRow> rows = await db.select(db.recipes).get();
        expect(rows, hasLength(2));
        final Recipe variation = (await RecipeStore(
          db,
        ).byId(rows.singleWhere((RecipeRow row) => row.id != original.id).id))!;
        final File? copy = await tester.runAsync<File?>(
          () => photos.fileFor(variation.id),
        );
        expect(
          copy,
          isNotNull,
          reason:
              'Available local artwork belongs to the new recipe even offline.',
        );
        expect(copy!.readAsBytesSync(), _localHero);
        expect(copy.path, isNot(endsWith(photoBefore.fileName!)));
        final File? source = await tester.runAsync<File?>(
          () => photos.fileFor(original.id),
        );
        expect(source!.readAsBytesSync(), _localHero);
        expect(
          (await db.select(db.recipePhotos).get())
              .singleWhere((RecipePhotoRow row) => row.recipeId == original.id)
              .toJson(),
          photoBefore.toJson(),
        );
        expect(
          rows.singleWhere((RecipeRow row) => row.id == original.id).toJson(),
          sourceBefore.toJson(),
        );
        expect(variation.iconSvg, _usualSketch);
        expect(await db.select(db.mealPlanEntries).get(), isEmpty);
        expect(photos.copyAttempts, 1);
        expect(icons.titles, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final String retryPhoto in <String>[
    'none',
    'chosen',
    'downloaded',
    'uploaded choice',
  ]) {
    testWidgets(
      'variation photo copy failure retries the same saved recipe ($retryPhoto)',
      (WidgetTester tester) async {
        const String inheritedUrl = 'fixture-household/saved-usual/old.png';
        final bool chooseOwnPhoto =
            retryPhoto == 'chosen' || retryPhoto == 'uploaded choice';
        final Directory directory = Directory.systemTemp.createTempSync(
          'hearth-variation-photo-retry-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final _NoDrawing icons = _NoDrawing();
        final _ChosenPhoto picker = _ChosenPhoto();
        late _VariationPhotoStore photos;
        final HearthDatabase db = await _openVariation(
          tester,
          icons: icons,
          original: savedUsual().copyWith(photoUrl: inheritedUrl),
          photoPicker: picker,
          extraOverrides: <Object>[
            recipePhotoStoreProvider.overrideWith(
              (ref) => _VariationPhotoStore(
                ref.watch(databaseProvider),
                directory: () async => directory,
                failCopies: 1,
              ),
            ),
          ],
          beforeOpening: (HearthDatabase database) async {
            photos = ProviderScope.containerOf(
              tester.element(find.byType(Scaffold).first),
            ).read(recipePhotoStoreProvider) as _VariationPhotoStore;
            await tester.runAsync(
              () => photos.save(
                recipeId: 'saved-usual',
                bytes: _localHero,
                extension: 'png',
                now: DateTime.utc(2026, 10, 1),
              ),
            );
          },
        );
        final RecipeRow originalBefore =
            (await db.select(db.recipes).get()).single;
        final RecipePhotoRow photoBefore =
            (await db.select(db.recipePhotos).get()).single;
        await _saveWithPhotoIo(tester, photos);
        expect(find.byType(RecipeEditorScreen), findsOneWidget);
        expect(find.textContaining('could not keep its photo'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final List<RecipeRow> firstRows = await db.select(db.recipes).get();
        expect(firstRows, hasLength(2));
        final String variationId = firstRows
            .singleWhere((RecipeRow row) => row.id != 'saved-usual')
            .id;
        expect(await db.select(db.mealPlanEntries).get(), isEmpty);

        RecipePhotoRow? chosenPhotoBefore;
        final String chosenUrl = 'fixture-household/$variationId/chosen.png';
        if (chooseOwnPhoto) {
          final Finder addPhoto = find.text('Add a photo');
          await _backTo(tester, addPhoto);
          await _tapWithPhotoIo(tester, photos, addPhoto);
          if (retryPhoto == 'uploaded choice') {
            final container = ProviderScope.containerOf(
              tester.element(find.byType(Scaffold).first),
            );
            await db.transaction(() async {
              await photos.markUploaded(recipeId: variationId, path: chosenUrl);
              await container
                  .read(recipeRepositoryProvider)
                  .setPhotoUrl(variationId, chosenUrl);
            });
          }
          chosenPhotoBefore = (await db.select(db.recipePhotos).get())
              .singleWhere((RecipePhotoRow row) => row.recipeId == variationId);
        } else if (retryPhoto == 'downloaded') {
          // A normal sync pull can cache the inherited old URL while the
          // editor is waiting for the failed local-photo copy to be retried.
          await tester.runAsync(
            () => photos.saveDownloaded(
              recipeId: variationId,
              path: inheritedUrl,
              bytes: _chosenHero,
              now: DateTime.utc(2026, 10, 2),
            ),
          );
        }

        await _saveWithPhotoIo(tester, photos);
        expect(find.byType(RecipeEditorScreen), findsNothing);
        final List<RecipeRow> finalRows = await db.select(db.recipes).get();
        expect(finalRows.map((RecipeRow row) => row.id).toSet(), <String>{
          'saved-usual',
          variationId,
        });
        expect(
          finalRows
              .singleWhere((RecipeRow row) => row.id == variationId)
              .photoUrl,
          retryPhoto == 'uploaded choice' ? chosenUrl : isNull,
          reason: 'Retry preserves a photo already uploaded for the variation.',
        );
        final File? copy = await tester.runAsync<File?>(
          () => photos.fileFor(variationId),
        );
        expect(copy, isNotNull);
        expect(
          copy!.readAsBytesSync(),
          chooseOwnPhoto ? _chosenHero : _localHero,
          reason: 'A chosen variation photo wins; a downloaded old URL must not replace the current local usual photo.',
        );
        if (chosenPhotoBefore != null) {
          expect(
            (await db.select(db.recipePhotos).get())
                .singleWhere(
                  (RecipePhotoRow row) => row.recipeId == variationId,
                )
                .toJson(),
            chosenPhotoBefore.toJson(),
          );
        }
        expect(
          finalRows
              .singleWhere((RecipeRow row) => row.id == 'saved-usual')
              .toJson(),
          originalBefore.toJson(),
        );
        expect(
          (await db.select(db.recipePhotos).get())
              .singleWhere(
                (RecipePhotoRow row) => row.recipeId == 'saved-usual',
              )
              .toJson(),
          photoBefore.toJson(),
        );
        final File? source = await tester.runAsync<File?>(
          () => photos.fileFor('saved-usual'),
        );
        expect(source!.readAsBytesSync(), _localHero);
        expect(photos.copyAttempts, 2);
        expect(picker.selections, chooseOwnPhoto ? 1 : 0);
        expect(icons.titles, isEmpty);
        expect(await db.select(db.mealPlanEntries).get(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'preselected variation review refuses a repeated published modifier',
    (WidgetTester tester) async {
      final Recipe variation = aRecipe(
        id: 'new-variation',
        title: 'Double burger variation',
        servings: 1,
        kind: RecipeKind.eatenOut,
        notes: 'Corner Kitchen',
        ingredients: <RecipeIngredient>[
          anIngredient(
            'Burger',
            amount: 2,
            unit: Units.item,
            foodId: 'usual-burger',
          ),
          anIngredient(
            'Lettuce wrap',
            amount: 2,
            unit: Units.item,
            foodId: 'usual-wrap',
          ),
        ],
      );
      final HearthDatabase db = await pumpHearthApp(
        tester,
        size: const Size(390, 1000),
        foods: usualMenuFoods(),
        recipes: <Recipe>[variation],
      );
      await pumpFrames(tester);
      unawaited(
        showLogSheet(
          tester.element(find.byType(Scaffold).first),
          date: addDays(DateTime.now(), -2),
          slot: MealSlot.dinner,
          initialRecipeId: variation.id,
        ),
      );
      await pumpFrames(tester, frames: 12);
      await SweepTools(tester).reach(find.text('Log it'));
      expect(
        await db.select(db.mealPlanEntries).get(),
        isEmpty,
        reason:
            'Saving a variation does not make a twice-applied modifier valid.',
      );
      expect(find.textContaining('can be applied only once'), findsOneWidget);
    },
  );

  for (final ({int days, bool commit}) scenario in <({int days, bool commit})>[
    (days: -2, commit: true),
    (days: 2, commit: true),
    (days: -2, commit: false),
  ]) {
    testWidgets(
      'variation saves separately before portion review (${scenario.days}, commit ${scenario.commit})',
      (WidgetTester tester) async {
        final DateTime date = addDays(DateTime.now(), scenario.days);
        final Recipe original = savedUsual().copyWith(
          photoUrl: 'fixture-household/saved-usual/hero.jpg',
          iconSvg: _usualSketch,
        );
        final StreamController<List<Recipe>> updates =
            StreamController<List<Recipe>>.broadcast();
        addTearDown(() => unawaited(updates.close()));
        final _NoDrawing icons = _NoDrawing();
        final HearthDatabase db = await _openVariation(
          tester,
          date: date,
          icons: icons,
          original: original,
          recipeStream: () async* {
            yield <Recipe>[original];
            yield* updates.stream;
          }(),
        );
        final RecipeRow before = (await db.select(db.recipes).get()).single;
        expect(await db.select(db.mealPlanEntries).get(), isEmpty);
        final SweepTools tools = SweepTools(tester);
        await tools.reach(find.text('Save new variation and review portion'));
        // The new recipe lands before photo preservation and its portion
        // review. Assert the completed user-visible handoff, not that first
        // intermediate database write.
        await _waitForHandoff(tester, portionReview: true);

        final List<RecipeRow> rows = await db.select(db.recipes).get();
        expect(rows, hasLength(2));
        expect(
          rows.singleWhere((RecipeRow row) => row.id == original.id).toJson(),
          before.toJson(),
        );
        final RecipeRow added = rows.singleWhere(
          (RecipeRow row) => row.id != original.id,
        );
        final Recipe variation = (await RecipeStore(db).byId(added.id))!;
        expect(variation.servings, 2);
        expect(variation.title, 'Our usual dinner (variation)');
        expect(
          variation.allIngredients.map((RecipeIngredient line) => line.foodId),
          <String>['usual-burger', 'usual-rice', 'usual-wrap'],
        );
        expect(
          variation.sections.single.id,
          isNot(original.sections.single.id),
        );
        expect(variation.photoUrl, original.photoUrl);
        expect(variation.iconSvg, original.iconSvg);
        expect(
          variation.allIngredients.map((RecipeIngredient line) => line.id),
          everyElement(
            isNot(
              isIn(
                original.allIngredients.map((RecipeIngredient line) => line.id),
              ),
            ),
          ),
        );
        expect(
          await db.select(db.mealPlanEntries).get(),
          isEmpty,
          reason: 'Saving the reusable variation is not approval of a personal portion.',
        );
        expect(
          icons.titles,
          isEmpty,
          reason: 'An explicit variation does not request new AI artwork.',
        );

        // The harness library is a controlled stream. Publish the real saved
        // recipe as the production repository watcher would after its save.
        updates.add(<Recipe>[original, variation]);
        await pumpFrames(tester, frames: 16);
        expect(
          find.text('Dinner · ${weekdayName(date)} ${shortDate(date)}'),
          findsOneWidget,
        );
        expect(find.textContaining('Your portion · 660 kcal'), findsOneWidget);
        if (!scenario.commit) {
          await tester.tapAt(const Offset(12, 120));
          await pumpFrames(tester, frames: 12);
          expect(find.byType(BottomSheet), findsNothing);
          expect(await db.select(db.mealPlanEntries).get(), isEmpty);
          expect(await db.select(db.recipes).get(), hasLength(2));
          return;
        }

        final Finder portion = find.descendant(
          of: find.byType(BottomSheet).last,
          matching: find.byType(TextField),
        );
        await tester.enterText(portion, '0.5');
        await tools.reach(
          find.text(scenario.days > 0 ? 'Add to plan' : 'Log it'),
        );
        final MealPlanEntryRow entry =
            (await db.select(db.mealPlanEntries).get()).single;
        final MealPlanDayRow day =
            (await db.select(db.mealPlanDays).get()).single;
        expect(entry.refId, variation.id);
        expect(entry.servings, 0.5);
        expect(entry.mealSlot, MealSlot.dinner.name);
        expect(dayKey(day.day), dayKey(date));
        expect(entry.isLogged, scenario.days < 0);
        if (scenario.days < 0) {
          final Map<String, Object?> snapshot =
              jsonDecode(entry.macroSnapshot!) as Map<String, Object?>;
          expect(snapshot['kcal'], 330);
        } else {
          expect(entry.macroSnapshot, isNull);
        }
        expect(icons.titles, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'library variation explicitly saves a new recipe without a diary entry',
    (WidgetTester tester) async {
      final _NoDrawing icons = _NoDrawing();
      final HearthDatabase db = await _openVariation(tester, icons: icons);
      final RecipeRow before = (await db.select(db.recipes).get()).single;
      await SweepTools(tester).reach(find.text('Save new variation'));
      await _waitForHandoff(tester);
      final List<RecipeRow> rows = await db.select(db.recipes).get();
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((RecipeRow row) => row.id == before.id).toJson(),
        before.toJson(),
      );
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      expect(find.byType(BottomSheet), findsNothing);
      expect(icons.titles, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling variation review preserves only the original usual', (
    WidgetTester tester,
  ) async {
    final _NoDrawing icons = _NoDrawing();
    final HearthDatabase db = await _openVariation(tester, icons: icons);
    final RecipeRow before = (await db.select(db.recipes).get()).single;
    final SweepTools tools = SweepTools(tester);
    await tools.reach(find.text('Cancel'));
    await tools.reach(find.text('Discard'));
    expect(
      (await db.select(db.recipes).get()).single.toJson(),
      before.toJson(),
    );
    expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    expect(icons.titles, isEmpty);
  });

  testWidgets(
    'explicit variation refuses the source recipe and section identities',
    (WidgetTester tester) async {
      final Recipe original = savedUsual().copyWith(
        photoUrl: 'fixture-household/saved-usual/hero.jpg',
        iconSvg: _usualSketch,
      );
      final _NoDrawing icons = _NoDrawing();
      final HearthDatabase db = await pumpHearthApp(
        tester,
        size: const Size(390, 1000),
        recipes: <Recipe>[original],
        foods: usualMenuFoods(),
        recipeIcon: icons,
      );
      await pumpFrames(tester);
      final RecipeRow before = (await db.select(db.recipes).get()).single;
      unawaited(
        tester
            .element(find.byType(Scaffold).first)
            .push<String>(
              '/recipe/new',
              extra: RecipeEditorArgs(
                draft: RecipeDraft.fromRecipe(original),
                variationOf: original.title,
                variationPhotoUrl: original.photoUrl,
              ),
            ),
      );
      await pumpFrames(tester, frames: 12);
      await tester.enterText(find.byType(TextField).first, 'Tuesday dinner');
      await SweepTools(tester).reach(find.text('Save new variation'));
      await _waitForHandoff(tester);
      final List<RecipeRow> rows = await db.select(db.recipes).get();
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((RecipeRow row) => row.id == original.id).toJson(),
        before.toJson(),
      );
      final Recipe variant = (await RecipeStore(
        db,
      ).byId(rows.singleWhere((RecipeRow row) => row.id != original.id).id))!;
      expect(variant.title, 'Tuesday dinner');
      expect(variant.sections.single.id, isNot(original.sections.single.id));
      expect(variant.photoUrl, original.photoUrl);
      expect(variant.iconSvg, original.iconSvg);
      expect(
        icons.titles,
        isEmpty,
        reason: 'Renaming a variation still preserves its copied artwork.',
      );
      expect(await db.select(db.mealPlanEntries).get(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'variation action stays reachable at 320pt and 3x with keyboard ($brightness)',
      (WidgetTester tester) async {
        final _NoDrawing icons = _NoDrawing();
        final HearthDatabase db = await _openVariation(
          tester,
          date: addDays(DateTime.now(), -2),
          icons: icons,
          size: const Size(320, 568),
          textScale: 3,
          brightness: brightness,
        );
        final SweepTools tools = SweepTools(tester);
        await tools.bring(find.byType(TextField));
        await tester.tap(find.byType(TextField).first);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await pumpFrames(tester);
        await tools.bring(find.byKey(const Key('variation-save')));
        final Finder action = find.text(
          'Save new variation and review portion',
        );
        expect(action, findsOneWidget);
        expect(tester.widget<Text>(action).maxLines, isNull);
        expect(tester.takeException(), isNull);
        await tools.reach(find.byKey(const Key('variation-save')));
        await _waitForHandoff(tester, portionReview: true);
        expect(await db.select(db.recipes).get(), hasLength(2));
        expect(await db.select(db.mealPlanEntries).get(), isEmpty);
        expect(icons.titles, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<HearthDatabase> _openVariation(
  WidgetTester tester, {
  DateTime? date,
  required _NoDrawing icons,
  Recipe? original,
  Stream<List<Recipe>>? recipeStream,
  Size size = const Size(390, 1000),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  List<Object> extraOverrides = const <Object>[],
  Future<void> Function(HearthDatabase)? beforeOpening,
  PhotoPicker? photoPicker,
}) async {
  final HearthDatabase db = await pumpHearthApp(
    tester,
    size: size,
    textScale: textScale,
    brightness: brightness,
    viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
    recipes: <Recipe>[original ?? savedUsual()],
    recipeStream: recipeStream,
    foods: usualMenuFoods(),
    recipeIcon: icons,
    selectedDate: date,
    extraOverrides: extraOverrides,
    photoPicker: photoPicker,
  );
  if (beforeOpening != null) await beforeOpening(db);
  final SweepTools tools = SweepTools(tester);
  if (date == null) {
    await tools.tab('Recipes');
    await tools.reach(find.text('Add recipe'));
    await tools.reach(find.text('Eat out'));
  } else {
    await tools.tab('Plan');
    await tools.reach(find.byTooltip('Add to dinner'));
    await tools.reach(
      find.text(
        calendarDaysBetween(DateTime.now(), date) > 0
            ? 'Plan a restaurant meal'
            : 'Ate out — build it from a menu',
      ),
    );
  }
  await tools.reach(find.text('Corner Kitchen'));
  await tools.reach(find.byKey(const Key('usual-customize-saved-usual')));
  await tools.reach(find.text('Lettuce wrap'));
  await _backTo(tester, find.byKey(const Key('usual-review-variation')));
  await tools.reach(find.byKey(const Key('usual-review-variation')));
  expect(find.byType(RecipeEditorScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
  return db;
}

Future<void> _saveWithPhotoIo(
  WidgetTester tester,
  _VariationPhotoStore photos,
) async {
  final Finder action = find.byKey(const Key('variation-save'));
  await _tapWithPhotoIo(tester, photos, action);
}

Future<void> _waitForHandoff(
  WidgetTester tester, {
  bool portionReview = false,
}) async {
  bool completed() => portionReview
      ? find.byType(BottomSheet).evaluate().isNotEmpty
      : find.byType(RecipeEditorScreen).evaluate().isEmpty;
  for (int frame = 0; frame < 60 && !completed(); frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    completed(),
    isTrue,
    reason: 'The variation save must finish its visible handoff.',
  );
}

Future<void> _tapWithPhotoIo(
  WidgetTester tester,
  _VariationPhotoStore photos,
  Finder action,
) async {
  await SweepTools(tester).bring(action);
  final Future<void> attempted = photos.observeNextCopy();
  await tester.runAsync(() async {
    await tester.tap(action);
    try {
      await attempted.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      // The regression must fail on the missing copied file rather than hang
      // when an implementation never attempts to preserve local artwork.
    }
  });
  await pumpFrames(tester, frames: 16);
}

Future<void> _backTo(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      target,
      SweepTools.verticalScroller,
      const Offset(0, 180),
      maxIteration: 100,
    );
  }
  await tester.ensureVisible(target);
  await pumpFrames(tester);
}
