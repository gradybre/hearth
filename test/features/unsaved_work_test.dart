import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';

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
