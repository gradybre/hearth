import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/adapters/recipe_icon.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/local/recipe_store.dart';
import 'package:hearth/data/mappers/recipe_mapper.dart';
import 'package:hearth/data/mappers/sync_payload.dart';
import 'package:hearth/data/repositories/recipe_repository.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/recipe_icon.dart';
import 'package:hearth/features/recipes/recipe_icon_controller.dart';
import 'package:hearth/features/recipes/recipe_library_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import 'recipe_import_test.dart' show FakeAi;

const String muffin =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">'
    '<path d="M6 12h12l-1 8H7z"/><path d="M8 12a4 4 0 018 0"/>'
    '</svg>';

const String hostile =
    '<svg viewBox="0 0 24 24"><script>alert(1)</script>'
    '<path d="M1 1L2 2"/></svg>';

/// Answers with whatever it was handed, and remembers what it was asked.
class FakeIconSource implements RecipeIconSource {
  FakeIconSource(this.answer);

  final String? answer;
  final List<String> asked = <String>[];

  @override
  Future<String?> draw({required String title}) async {
    asked.add(title);
    return answer;
  }
}

class ThrowingIconSource implements RecipeIconSource {
  @override
  Future<String?> draw({required String title}) async =>
      throw StateError('the network is not there');
}

void main() {
  group('when a recipe should be redrawn', () {
    test('a recipe saved for the first time gets one', () {
      expect(
        RecipeIconController.needsDrawing(
          currentIcon: null,
          titleWhenOpened: 'Pumpkin muffins',
          titleNow: 'Pumpkin muffins',
          isNewRecipe: true,
        ),
        isTrue,
      );
    });

    test('a recipe that already exists and has none is left alone', () {
      // The removal control is the whole reason writing an icon without a
      // review screen is defensible (CLAUDE.md rule 4), and "it has no icon"
      // as a reason to draw made that control a lie: removing one and saving
      // fired a fresh paid call and landed another. It also re-billed on
      // every save of a recipe whose answer failed validation or whose share
      // of the month's budget was spent. "Draw one now" is the way back.
      expect(
        RecipeIconController.needsDrawing(
          currentIcon: null,
          titleWhenOpened: 'Pumpkin muffins',
          titleNow: 'Pumpkin muffins',
          isNewRecipe: false,
        ),
        isFalse,
      );
    });

    test('a recipe whose title still says the same dish is left alone', () {
      // The rule that keeps this from costing money on every keystroke: an
      // ingredient edit, a note, a fixed typo — none of them redraw.
      expect(
        RecipeIconController.needsDrawing(
          currentIcon: muffin,
          titleWhenOpened: 'Pumpkin muffins',
          titleNow: 'Pumpkin muffins',
          isNewRecipe: false,
        ),
        isFalse,
      );
    });

    test('capitals and punctuation are not a material change', () {
      expect(
        RecipeIconController.needsDrawing(
          currentIcon: muffin,
          titleWhenOpened: 'Pumpkin Muffins',
          titleNow: 'pumpkin muffins!',
          isNewRecipe: false,
        ),
        isFalse,
      );
    });

    test('a genuinely different dish is redrawn', () {
      expect(
        RecipeIconController.needsDrawing(
          currentIcon: muffin,
          titleWhenOpened: 'Pumpkin muffins',
          titleNow: 'Chicken noodle soup',
          isNewRecipe: false,
        ),
        isTrue,
      );
    });

    test('a rename still redraws a recipe whose icon was removed', () {
      // Removal keeps an icon away until the dish itself changes, not for
      // ever: the drawing that was thrown away was of the old dish.
      expect(
        RecipeIconController.needsDrawing(
          currentIcon: null,
          titleWhenOpened: 'Pumpkin muffins',
          titleNow: 'Chicken noodle soup',
          isNewRecipe: false,
        ),
        isTrue,
      );
    });
  });

  group('drawing one', () {
    late HearthDatabase db;
    late RecipeRepository repository;

    setUp(() async {
      db = HearthDatabase.forTesting(NativeDatabase.memory());
      repository = RecipeRepository(
        database: db,
        store: RecipeStore(db),
        queue: PendingWriteStore(db),
        householdId: 'household-1',
      );
      await repository.save(aRecipe(id: 'recipe-1', title: 'Pumpkin muffins'));
    });

    tearDown(() => db.close());

    test('a drawing that comes back is stored on the recipe', () async {
      final FakeIconSource source = FakeIconSource(muffin);
      await RecipeIconController(
        source: source,
        recipes: repository,
      ).drawFor(recipeId: 'recipe-1', title: 'Pumpkin muffins');

      expect(source.asked, <String>['Pumpkin muffins']);
      expect((await repository.byId('recipe-1'))!.iconSvg, muffin);
    });

    test('a hostile drawing is refused and leaves the recipe without one', () {
      // Belt to the adapter's braces: nothing unvalidated reaches the store,
      // even if a caller hands it something straight from a model.
      return expectLater(
        RecipeIconController(
              source: FakeIconSource(hostile),
              recipes: repository,
            )
            .drawFor(recipeId: 'recipe-1', title: 'Pumpkin muffins')
            .then((_) => repository.byId('recipe-1')),
        completion(
          isA<Recipe>().having((Recipe r) => r.iconSvg, 'icon', isNull),
        ),
      );
    });

    test('a failure is swallowed, because nobody is waiting on a picture', () {
      // The recipe is already saved by the time this runs. A snackbar in front
      // of somebody who has just saved would report a problem they do not have.
      return expectLater(
        RecipeIconController(
          source: ThrowingIconSource(),
          recipes: repository,
        ).drawFor(recipeId: 'recipe-1', title: 'Pumpkin muffins'),
        completes,
      );
    });

    test('a build with no backend simply does not draw', () async {
      await RecipeIconController(
        source: null,
        recipes: repository,
      ).drawFor(recipeId: 'recipe-1', title: 'Pumpkin muffins');

      expect((await repository.byId('recipe-1'))!.iconSvg, isNull);
    });

    test('clearing one takes it away, at the user\'s word', () async {
      final RecipeIconController controller = RecipeIconController(
        source: FakeIconSource(muffin),
        recipes: repository,
      );
      await controller.drawFor(recipeId: 'recipe-1', title: 'Pumpkin muffins');
      await controller.clear('recipe-1');

      expect((await repository.byId('recipe-1'))!.iconSvg, isNull);
    });
  });

  group('what survives storage and sync', () {
    test('an icon makes the round trip through the sync payload', () {
      final Recipe recipe = aRecipe(id: 'recipe-1', iconSvg: muffin);
      final Recipe back = SyncPayload.recipe(
        RecipeMapper.toJson(recipe, updatedAt: DateTime.utc(2026)),
      );

      expect(back.iconSvg, muffin);
    });

    test('an icon arriving from another device is validated too', () {
      // A row pulled from the server was written by a device this one has no
      // reason to trust, and it is model output wherever it came from.
      final Map<String, Object?> payload = RecipeMapper.toJson(
        aRecipe(id: 'recipe-1'),
        updatedAt: DateTime.utc(2026),
      )..['icon_svg'] = hostile;

      expect(SyncPayload.recipe(payload).iconSvg, isNull);
    });

    test('an icon field that is not a string is no icon, not a lost pull', () {
      // Every other read in the payload is defensive, and this is the one
      // field the change itself calls untrusted. A cast that throws here
      // takes down the whole pull rather than one picture.
      final Map<String, Object?> payload = RecipeMapper.toJson(
        aRecipe(id: 'recipe-1'),
        updatedAt: DateTime.utc(2026),
      )..['icon_svg'] = 42;

      expect(SyncPayload.recipe(payload).iconSvg, isNull);
    });
  });

  group('on screen', () {
    testWidgets('a recipe with an icon draws one in the library', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'recipe-1', title: 'Pumpkin muffins', iconSvg: muffin),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(RecipeCard),
          matching: find.byType(RecipeIcon),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a recipe without one draws nothing at all', (
      WidgetTester tester,
    ) async {
      // Not a grey placeholder: an undrawn library should look undrawn, not
      // broken.
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[aRecipe(id: 'recipe-1', title: 'Pumpkin muffins')],
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomPaint).evaluate().isEmpty, isFalse);
      expect(
        find.descendant(
          of: find.byType(RecipeCard),
          matching: find.byType(RecipeIcon),
        ),
        findsNothing,
      );
    });

    testWidgets('an icon that would not validate is not drawn', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'recipe-1', title: 'Pumpkin muffins', iconSvg: hostile),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(RecipeCard),
          matching: find.byType(RecipeIcon),
        ),
        findsNothing,
      );
    });

    testWidgets('the sketch is decoration, so a screen reader skips it', (
      WidgetTester tester,
    ) async {
      // The recipe's name carries the meaning (spec §6.3). An icon announced
      // as content would be the decoration read once and the recipe twice.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RecipeIcon(svg: muffin, size: 40, color: Color(0xFF3B2F2A)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder excluder = find.descendant(
        of: find.byType(RecipeIcon),
        matching: find.byType(ExcludeSemantics),
      );
      expect(excluder, findsOneWidget);
      expect(tester.widget<ExcludeSemantics>(excluder).excluding, isTrue);
    });

    testWidgets('a photo wins the slot a sketch would have taken', (
      WidgetTester tester,
    ) async {
      // Two pictures of one recipe competing in a 64pt square is worse than
      // either alone, and a photograph of the actual dish beats a sketch of
      // the idea of it.
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'recipe-1', title: 'Pumpkin muffins', iconSvg: muffin),
        ],
        photos: const <String, String>{'recipe-1': 'muffins.jpg'},
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(RecipeCard),
          matching: find.byType(RecipeIcon),
        ),
        findsNothing,
      );
    });
  });

  group('saving a recipe', () {
    /// Opens the editor for the one recipe in the library.
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(find.byType(RecipeCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      final Finder button = find.widgetWithText(FilledButton, 'Save');
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('an unchanged title does not spend anything redrawing', (
      WidgetTester tester,
    ) async {
      // The rule that keeps a decorative feature cheap: editing a note or an
      // ingredient must not buy the same muffin again.
      final FakeIconSource source = FakeIconSource(muffin);
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'recipe-1', title: 'Pumpkin muffins', iconSvg: muffin),
        ],
        recipeIcon: source,
      );
      await tester.pumpAndSettle();

      await openEditor(tester);
      await save(tester);

      expect(source.asked, isEmpty);
    });

    testWidgets('renaming the dish redraws it', (WidgetTester tester) async {
      final FakeIconSource source = FakeIconSource(muffin);
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'recipe-1', title: 'Pumpkin muffins', iconSvg: muffin),
        ],
        recipeIcon: source,
      );
      await tester.pumpAndSettle();

      await openEditor(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'Chicken noodle soup',
      );
      await tester.pumpAndSettle();
      await save(tester);

      expect(source.asked, <String>['Chicken noodle soup']);
    });

    testWidgets('a recipe saved for the first time is drawn one', (
      WidgetTester tester,
    ) async {
      final FakeIconSource source = FakeIconSource(muffin);
      await pumpHearthApp(tester, recipeIcon: source);
      await tester.pumpAndSettle();

      await addRecipeVia(tester, 'Write a recipe');
      await pumpFrames(tester);
      await tester.enterText(find.byType(TextField).first, 'Pumpkin muffins');
      await pumpFrames(tester);
      await save(tester);

      expect(source.asked, <String>['Pumpkin muffins']);
    });

    testWidgets('an icon the user removed is not bought again on save', (
      WidgetTester tester,
    ) async {
      // This is the control the whole rule-4 exception is argued on: an icon
      // is written without a review screen because it is "reversible in one
      // tap". Removing one and then saving used to fire a fresh paid call and
      // land a new sketch, which makes the tap not a reversal at all.
      final FakeIconSource source = FakeIconSource(muffin);
      final HearthDatabase db = await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'recipe-1', title: 'Pumpkin muffins', iconSvg: muffin),
        ],
        recipeIcon: source,
      );
      await tester.pumpAndSettle();

      await openEditor(tester);
      await tester.tap(find.text('Remove icon'));
      await tester.pumpAndSettle();
      await save(tester);

      expect(source.asked, isEmpty);
      expect((await RecipeStore(db).byId('recipe-1'))?.iconSvg, isNull);
    });

    testWidgets('a recipe whose icon never arrived is not re-billed', (
      WidgetTester tester,
    ) async {
      // Same mechanism, without anybody having pressed anything: a drawing
      // that failed validation, or one the month's picture budget refused,
      // leaves the recipe with no icon — and every later save of it used to
      // buy the attempt again. "Draw one now" is the way back.
      final FakeIconSource source = FakeIconSource(muffin);
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[aRecipe(id: 'recipe-1', title: 'Pumpkin muffins')],
        recipeIcon: source,
      );
      await tester.pumpAndSettle();

      await openEditor(tester);
      await save(tester);

      expect(source.asked, isEmpty);
    });

    testWidgets('a title changed by asking for it still redraws', (
      WidgetTester tester,
    ) async {
      // The revise panel fills the fields from the answer, and filling them
      // used to reset the very field the redraw rule compares against. Muffins
      // then stayed beside a dish they no longer described.
      final FakeIconSource icons = FakeIconSource(muffin);
      final FakeAi ai = FakeAi(answer: _vegan)..answer2 = _vegan;
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'recipe-1', title: 'Pumpkin muffins', iconSvg: muffin),
        ],
        recipeIcon: icons,
        recipeAi: ai,
      );
      await tester.pumpAndSettle();

      await openEditor(tester);
      await tester.scrollUntilVisible(
        find.text('Ask for a change'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'What should change?'),
        'Make it vegan.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
      await pumpFrames(tester, frames: 20);
      await save(tester);

      expect(icons.asked, <String>['Vegan pumpkin muffins']);
    });
  });

  group('asking for another sketch', () {
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(find.byType(RecipeCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
    }

    testWidgets('a redraw that fails says so, because somebody is waiting', (
      WidgetTester tester,
    ) async {
      // Silence is right for the background drawing after a save — the recipe
      // is already safe and nobody asked for a picture. It is wrong here: the
      // button un-disabled itself and nothing else happened, whether the
      // network was gone, the month's picture budget was spent, or the markup
      // failed validation.
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[aRecipe(id: 'recipe-1', title: 'Pumpkin muffins')],
        recipeIcon: ThrowingIconSource(),
      );
      await tester.pumpAndSettle();

      await openEditor(tester);
      await tester.tap(find.text('Draw one now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not draw'), findsOneWidget);
      // Never colour alone (CLAUDE.md rule 6).
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('a redraw that works says nothing and shows the sketch', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[aRecipe(id: 'recipe-1', title: 'Pumpkin muffins')],
        recipeIcon: FakeIconSource(muffin),
      );
      await tester.pumpAndSettle();

      await openEditor(tester);
      await tester.tap(find.text('Draw one now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not draw'), findsNothing);
      expect(find.text('Draw another'), findsOneWidget);
    });

    testWidgets('an icon another device removed stops showing', (
      WidgetTester tester,
    ) async {
      // The editor deliberately shows the stored icon rather than the one the
      // form opened with, so a drawing that lands in the background appears.
      // The same has to hold in reverse: a removal on the partner's phone must
      // not leave a sketch on screen that is no longer there.
      final StreamController<List<Recipe>> library =
          StreamController<List<Recipe>>();
      addTearDown(library.close);

      final Recipe drawn = aRecipe(
        id: 'recipe-1',
        title: 'Pumpkin muffins',
        iconSvg: muffin,
      );
      final HearthDatabase db = await pumpHearthApp(
        tester,
        recipes: <Recipe>[drawn],
        recipeStream: library.stream,
        recipeIcon: FakeIconSource(muffin),
      );
      library.add(<Recipe>[drawn]);
      await tester.pumpAndSettle();

      await openEditor(tester);
      expect(find.text('Draw another'), findsOneWidget);

      // The pull lands: the row arrives with no icon on it any more.
      final Recipe cleared = drawn.copyWith(clearIconSvg: true);
      await RecipeStore(db).upsert(cleared, updatedAt: DateTime(2026, 2));
      library.add(<Recipe>[cleared]);
      await tester.pumpAndSettle();

      expect(find.text('Draw one now'), findsOneWidget);
    });
  });
}

/// What the revise panel answers with: the same muffins, gone vegan.
const AiRecipe _vegan = AiRecipe(
  title: 'Vegan pumpkin muffins',
  servings: 12,
  sections: <AiSection>[
    AiSection(
      name: '',
      ingredientsText: '400 g pumpkin purée\n2 tbsp flax meal',
      directionsText: '1. Mix.\n2. Bake.',
    ),
  ],
  reply: 'Swapped the eggs for flax.',
);
