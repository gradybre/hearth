import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Duplicating a recipe (spec §5.2).
///
/// "My usual bowl, but no rice" is a different meal, not an edit — editing the
/// shared one would rewrite what a partner planned and what the library calls
/// your usual.
void main() {
  Recipe bowl() => aRecipe(
    id: 'r-bowl',
    title: 'My usual bowl',
    servings: 1,
    kind: RecipeKind.eatenOut,
    ingredients: <RecipeIngredient>[
      anIngredient('chicken', amount: 4, unit: Units.ounce),
      anIngredient('white rice', amount: 4, unit: Units.ounce),
    ],
  );

  group('the copy itself', () {
    test('drops every id, the recipe and its sections', () {
      // A section id is a primary key. Carrying one into a second recipe
      // would either collide outright or quietly re-parent the original's
      // ingredients onto the copy.
      final RecipeDraft copy = RecipeDraft.fromRecipe(bowl()).asCopy();

      expect(copy.existingId, isNull);
      expect(
        copy.sections.map((DraftSection s) => s.existingId),
        everyElement(isNull),
      );
    });

    test('and comes out as two separate recipes when saved', () {
      final Recipe original = bowl();
      final Recipe copy = RecipeDraft.fromRecipe(original).asCopy().toRecipe();

      expect(copy.id, isNot(original.id));
      expect(copy.sections.single.id, isNot(original.sections.single.id));
      expect(
        copy.allIngredients.map((RecipeIngredient i) => i.id),
        everyElement(
          isNot(
            isIn(original.allIngredients.map((RecipeIngredient i) => i.id)),
          ),
        ),
      );
    });

    test('keeps what made the original worth copying', () {
      final RecipeDraft copy = RecipeDraft.fromRecipe(bowl()).asCopy();

      // The kind above all: a duplicated bowl that came back as a recipe you
      // cook would land on the shopping list.
      expect(copy.kind, RecipeKind.eatenOut);
      expect(copy.servings, 1);
      expect(copy.sections.single.ingredientsText, contains('chicken'));
    });

    test('and says it is a copy, so the library does not read as double', () {
      expect(
        RecipeDraft.fromRecipe(bowl()).asCopy().title,
        'My usual bowl (copy)',
      );
    });
  });

  testWidgets('duplicating opens an unsaved copy, and writes nothing yet', (
    WidgetTester tester,
  ) async {
    // Nothing is written until Save — the same rule an import follows
    // (CLAUDE.md rule 4). A copy that saved itself would litter the shared
    // library with a recipe nobody had looked at.
    final HearthDatabase db = await pumpHearthApp(
      tester,
      recipes: <Recipe>[bowl()],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('My usual bowl'));
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.byTooltip('Duplicate this recipe'));
    await pumpFrames(tester, frames: 12);

    expect(find.text('My usual bowl (copy)'), findsOneWidget);
    expect(await db.select(db.recipes).get(), hasLength(1));
  });

  testWidgets('and saving it leaves the original alone', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(
      tester,
      recipes: <Recipe>[bowl()],
    );
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await tester.tap(find.text('My usual bowl'));
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.byTooltip('Duplicate this recipe'));
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester, frames: 20);

    final List<RecipeRow> rows = await db.select(db.recipes).get();
    expect(rows, hasLength(2));
    expect(
      rows.map((RecipeRow r) => r.title),
      containsAll(<String>['My usual bowl', 'My usual bowl (copy)']),
    );
    // Both eaten out, because a copy that forgot would go shopping.
    expect(rows.map((RecipeRow r) => r.kind), everyElement('eaten_out'));
  });
}
