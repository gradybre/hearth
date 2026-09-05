import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    test('a recipe with no icon gets one', () {
      expect(
        RecipeIconController.needsDrawing(
          currentIcon: null,
          titleWhenOpened: 'Pumpkin muffins',
          titleNow: 'Pumpkin muffins',
        ),
        isTrue,
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

    testWidgets('a recipe with no icon is drawn one, in the background', (
      WidgetTester tester,
    ) async {
      final FakeIconSource source = FakeIconSource(muffin);
      await pumpHearthApp(
        tester,
        recipes: <Recipe>[aRecipe(id: 'recipe-1', title: 'Pumpkin muffins')],
        recipeIcon: source,
      );
      await tester.pumpAndSettle();

      await openEditor(tester);
      await save(tester);

      expect(source.asked, <String>['Pumpkin muffins']);
    });

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
  });
}
