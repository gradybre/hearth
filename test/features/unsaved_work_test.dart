import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/auth/local_auth_gateway.dart';
import 'package:hearth/data/local/editor_draft_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';

import '../support/app_harness.dart';

import '../support/fixtures.dart';

/// Leaving an editor never throws away what was typed (review F01).
///
/// Both editors keep their work in controller state and, before this, both
/// tapped Cancel straight into `Navigator.pop()`. Nothing asked. A recipe
/// retyped from a photograph, or forty minutes of a menu, went in one tap
/// with no way back — and the tap that does it sits in the corner where a
/// back gesture lands.
///
/// The rule these hold: a *changed* editor asks before it closes, and an
/// unchanged one closes immediately. Over-prompting is its own failure — an
/// editor that asks every time teaches people to hit Discard without reading,
/// which is how the guard stops working.
void main() {
  Future<void> openNewRecipe(WidgetTester tester) async {
    await pumpHearthApp(tester);
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await addRecipeVia(tester, 'Write a recipe');
  }

  Future<void> openExistingRecipe(WidgetTester tester) async {
    await pumpHearthApp(
      tester,
      recipes: <Recipe>[aRecipe(id: 'r1', title: 'Weeknight chilli')],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('Weeknight chilli'));
    await pumpFrames(tester, frames: 16);
    await tester.tap(find.text('Edit'));
    await pumpFrames(tester, frames: 16);
  }

  group('the recipe editor', () {
    testWidgets('asks before discarding a changed draft', (
      WidgetTester tester,
    ) async {
      await openNewRecipe(tester);

      await tester.enterText(find.byType(TextField).first, 'Short ribs');
      await pumpFrames(tester);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 12);

      expect(
        find.text('Keep editing'),
        findsOneWidget,
        reason: 'Cancel threw the work away without asking',
      );
    });

    testWidgets('and keeping it leaves every field exactly as typed', (
      WidgetTester tester,
    ) async {
      // The half that matters. A dialog that asks and then loses the work
      // anyway is worse than no dialog, because it looks like it protected
      // something.
      await openNewRecipe(tester);

      await tester.enterText(find.byType(TextField).first, 'Short ribs');
      await pumpFrames(tester);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Keep editing'));
      await pumpFrames(tester, frames: 12);

      final TextField title = tester.widget(find.byType(TextField).first);
      expect(title.controller!.text, 'Short ribs');
      expect(find.text('Cancel'), findsOneWidget, reason: 'it closed anyway');
    });

    testWidgets('discarding deliberately does close it', (
      WidgetTester tester,
    ) async {
      await openNewRecipe(tester);

      await tester.enterText(find.byType(TextField).first, 'Short ribs');
      await pumpFrames(tester);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 12);
      await tester.tap(find.text('Discard'));
      await pumpFrames(tester, frames: 16);

      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('an untouched editor closes without asking', (
      WidgetTester tester,
    ) async {
      // The over-prompting failure. An editor that asks when nothing was
      // typed teaches people to hit Discard without reading it.
      await openNewRecipe(tester);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 16);

      expect(find.text('Keep editing'), findsNothing);
      expect(find.text('Cancel'), findsNothing, reason: 'it should have gone');
    });

    testWidgets('and an opened recipe left alone closes too', (
      WidgetTester tester,
    ) async {
      // Opening an existing recipe fills every field. If that counts as a
      // change, the guard fires on a recipe nobody touched.
      await openExistingRecipe(tester);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 16);

      expect(find.text('Keep editing'), findsNothing);
    });
  });

  group('what counts as work', () {
    testWidgets('a match the matcher applied by itself does not', (
      WidgetTester tester,
    ) async {
      // The over-prompting failure, reached properly this time. Opening a
      // recipe runs the trusted matcher, which fills in what the household
      // already decided elsewhere and commits it in a post-frame setState —
      // no tap involved. Counted as unsaved work, that asks "discard this
      // recipe?" over a recipe nobody touched, on nearly every recipe once
      // the library has been used for a week.
      await pumpHearthApp(
        tester,
        // A *default* food. Only a default, a remembered correction or a
        // restaurant menu is trusted enough to be applied without asking —
        // an ordinary library food is offered, not applied, so it would not
        // reach the path this test is about.
        foods: <Food>[aFood('Ground beef', id: 'f-beef', isDefault: true)],
        recipes: <Recipe>[
          aRecipe(
            id: 'r1',
            title: 'Weeknight chilli',
            ingredients: <RecipeIngredient>[
              anIngredient('ground beef', amount: 450),
            ],
          ),
        ],
      );
      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Weeknight chilli'));
      await pumpFrames(tester, frames: 16);
      await tester.tap(find.text('Edit'));
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 16);

      expect(
        find.text('Keep editing'),
        findsNothing,
        reason: 'an automatic match was treated as something you typed',
      );
    });

    testWidgets('and neither does opening an import you have not edited', (
      WidgetTester tester,
    ) async {
      // Cancel on a review screen is the reject answer that screen exists to
      // offer (rule 4). Asking "discard this recipe?" when somebody pressed
      // the button meaning exactly that is over-prompting, not protection —
      // and `recipe_import_test` was already holding this before the guard
      // existed. Editing the import first is what makes it ask, which the
      // recipe group above covers.
      await pumpHearthApp(tester);
      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await addRecipeVia(tester, 'Write a recipe');

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 16);

      expect(find.text('Keep editing'), findsNothing);
    });
  });

  group('a draft that outlived the app (review N01)', () {
    testWidgets('is offered back, not applied', (WidgetTester tester) async {
      // Applied on open, a restored draft puts work in front of somebody who
      // does not know where it came from — and for an existing recipe could
      // quietly replace what their partner changed since. Rule 4's spirit,
      // one screen earlier.
      final HearthDatabase db = await pumpHearthApp(tester);
      await EditorDraftStore(db, userId: LocalAuthGateway.account.userId).save(
        EditorDraft(
          kind: 'recipe',
          payload: const RecipeDraft(
            title: 'Half-typed short ribs',
            servings: 4,
          ).toJson(),
        ),
        at: DateTime.utc(2026, 9, 10),
      );

      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await addRecipeVia(tester, 'Write a recipe');
      await pumpFrames(tester, frames: 20);

      expect(find.text('Unfinished changes'), findsOneWidget);

      // Nothing is in the fields until it is asked for.
      final TextField before = tester.widget(find.byType(TextField).first);
      expect(before.controller!.text, isEmpty);

      await tester.tap(find.text('Restore'));
      await pumpFrames(tester, frames: 20);

      final TextField after = tester.widget(find.byType(TextField).first);
      expect(after.controller!.text, 'Half-typed short ribs');
    });

    testWidgets('and discarding it leaves nothing behind', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pumpHearthApp(tester);
      final EditorDraftStore drafts = EditorDraftStore(
        db,
        userId: LocalAuthGateway.account.userId,
      );
      await drafts.save(
        EditorDraft(
          kind: 'recipe',
          payload: const RecipeDraft(title: 'Abandoned', servings: 2).toJson(),
        ),
        at: DateTime.utc(2026, 9, 10),
      );

      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await addRecipeVia(tester, 'Write a recipe');
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.text('Discard them'));
      await pumpFrames(tester, frames: 20);

      expect(await drafts.find(kind: 'recipe'), isNull);
      // And the editor is clean, so leaving does not ask again about work
      // that was just deliberately thrown away.
      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 16);
      expect(find.text('Keep editing'), findsNothing);
    });

    testWidgets('and says so when the recipe moved on underneath', (
      WidgetTester tester,
    ) async {
      // The case that could lose somebody else's work rather than your own:
      // a draft taken on Monday, the other phone edits the recipe on
      // Tuesday, and restoring hands back a copy of Monday's version over
      // the top of theirs. Refusing outright would be wrong — it is still
      // your work — so it is said plainly and left as a decision.
      final DateTime monday = DateTime.utc(2026, 9, 7);
      final DateTime tuesday = DateTime.utc(2026, 9, 8);

      final HearthDatabase db = await pumpHearthApp(
        tester,
        recipes: <Recipe>[
          aRecipe(id: 'r1', title: 'Weeknight chilli', updatedAt: tuesday),
        ],
      );
      await EditorDraftStore(db, userId: LocalAuthGateway.account.userId).save(
        EditorDraft(
          kind: 'recipe',
          targetId: 'r1',
          sourceUpdatedAt: monday,
          payload: const RecipeDraft(
            title: 'Weeknight chilli, my version',
            servings: 4,
          ).toJson(),
        ),
        at: monday,
      );

      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Weeknight chilli'));
      await pumpFrames(tester, frames: 16);
      await tester.tap(find.text('Edit'));
      await pumpFrames(tester, frames: 24);

      expect(
        find.textContaining('has been edited since'),
        findsOneWidget,
        reason: 'restoring over the other phone\'s edit said nothing',
      );
    });

    testWidgets('and work put back is still work unsaved', (
      WidgetTester tester,
    ) async {
      // The trap in restoring: filling the fields makes the restored draft
      // the editor's own baseline, so it reads as *clean* and leaving loses
      // it again — silently, and immediately after somebody chose to keep it.
      final HearthDatabase db = await pumpHearthApp(tester);
      await EditorDraftStore(db, userId: LocalAuthGateway.account.userId).save(
        EditorDraft(
          kind: 'recipe',
          payload: const RecipeDraft(
            title: 'Recovered ribs',
            servings: 4,
          ).toJson(),
        ),
        at: DateTime.utc(2026, 9, 10),
      );

      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await addRecipeVia(tester, 'Write a recipe');
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.text('Restore'));
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 16);

      expect(
        find.text('Keep editing'),
        findsOneWidget,
        reason: 'the restored draft was treated as though it were saved',
      );
    });

    testWidgets('a change that was not typing is written down too', (
      WidgetTester tester,
    ) async {
      // Typing is one of fifteen ways this editor changes. Hanging the draft
      // off the text fields meant the guard and the draft disagreed about
      // what counts as work: add a section or match an ingredient, lose the
      // app, and it was gone — although Cancel would have asked about it.
      final HearthDatabase db = await pumpHearthApp(tester);
      final EditorDraftStore drafts = EditorDraftStore(
        db,
        userId: LocalAuthGateway.account.userId,
      );

      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await addRecipeVia(tester, 'Write a recipe');
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.text('Add a section'));
      await pumpFrames(tester, frames: 12);
      // Past the debounce, without waiting two real seconds.
      await tester.pump(const Duration(seconds: 3));
      await pumpFrames(tester, frames: 8);

      final EditorDraft? saved = await drafts.find(kind: 'recipe');
      expect(
        saved,
        isNotNull,
        reason: 'a change made without the keyboard was never written down',
      );
      expect((saved!.payload['sections']! as List<Object?>), hasLength(2));
    });

    testWidgets('an untouched editor is never offered one', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester);
      await tester.tap(find.text('Recipes').last);
      await pumpFrames(tester);
      await addRecipeVia(tester, 'Write a recipe');
      await pumpFrames(tester, frames: 20);

      expect(find.text('Unfinished changes'), findsNothing);
    });
  });

  group('the food editor', () {
    Future<void> openNewFood(WidgetTester tester) async {
      await pumpHearthApp(tester, foods: <Food>[aFood('Rolled oats')]);
      await tester.tap(find.text('Foods').last);
      await pumpFrames(tester);
      await tester.tap(find.text('Rolled oats'));
      await pumpFrames(tester, frames: 16);
    }

    testWidgets('asks before discarding a changed food', (
      WidgetTester tester,
    ) async {
      await openNewFood(tester);

      await tester.enterText(find.byType(TextField).first, 'Porridge oats');
      await pumpFrames(tester);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 12);

      expect(
        find.text('Keep editing'),
        findsOneWidget,
        reason: 'Cancel threw the work away without asking',
      );
    });

    testWidgets('an untouched food editor closes without asking', (
      WidgetTester tester,
    ) async {
      await openNewFood(tester);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester, frames: 16);

      expect(find.text('Keep editing'), findsNothing);
    });
  });
}
