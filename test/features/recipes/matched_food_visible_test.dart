import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/models/food.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';
import 'ingredient_capture_test.dart' show openIngredientPicker;

/// The food a line is already matched to has to be *in* the picker
/// (Brendan's report).
///
/// A recipe line reading "apples", matched to a food called "Honeycrisp
/// Apple", opened on "None of your foods match" — with an Unmatch button in
/// the header saying the opposite. The sheet searches on the ingredient
/// wording, and a wording that differs from the food's name is precisely what
/// remembered matches are for.
void main() {
  testWidgets('a match whose name differs from the wording is still shown', (
    WidgetTester tester,
  ) async {
    await openIngredientPicker(
      tester,
      ingredientLine: '24 oz apples',
      ingredientName: 'apples',
      foods: <Food>[aFood('Honeycrisp Apple', id: 'food-apple')],
    );

    // "apples" does not appear anywhere in "Honeycrisp Apple", which is how
    // the food came to be filtered out of its own match sheet.
    expect(find.text('Match "apples"'), findsOneWidget);
    expect(find.text('None of your foods match.'), findsNothing);
    expect(find.text('Honeycrisp Apple'), findsWidgets);
  });

  testWidgets('a plural finds the singular food it names', (
    WidgetTester tester,
  ) async {
    // The other half of the same report: even unmatched, searching "apples"
    // should find an apple.
    await openIngredientPicker(
      tester,
      ingredientLine: '2 eggs',
      ingredientName: 'eggs',
      foods: <Food>[aFood('Large Egg', id: 'food-egg')],
    );

    expect(find.text('Large Egg'), findsWidgets);
  });

  testWidgets('the seasoning line reads as an offer, not as a verdict', (
    WidgetTester tester,
  ) async {
    // It was an accent text button with the same grass icon the badge on a
    // *marked* row wears, so opening the sheet on an apple looked like Hearth
    // declaring the apple a seasoning.
    await openIngredientPicker(
      tester,
      ingredientLine: '24 oz apples',
      ingredientName: 'apples',
      foods: <Food>[aFood('Honeycrisp Apple', id: 'food-apple')],
    );

    expect(find.text('Mark as a seasoning instead'), findsOneWidget);
    expect(find.textContaining("it's a seasoning"), findsNothing);
  });

  testWidgets('a remembered match survives a search that cannot find it', (
    WidgetTester tester,
  ) async {
    // Brendan's case, driven the way he hit it. "evoo" shares no word with
    // "Olive Oil", so the sheet — which pre-fills its search with the
    // ingredient's own wording — cannot find the food this line is matched
    // to. It used to answer "None of your foods match" under a header
    // offering to Unmatch it.
    await openIngredientPicker(
      tester,
      ingredientLine: '2 tbsp evoo',
      ingredientName: 'evoo',
      foods: <Food>[aFood('Olive Oil', id: 'food-oil')],
    );

    // Nothing found on the wording, as expected — so clear it and pick.
    await tester.enterText(find.widgetWithText(TextField, 'evoo'), '');
    await pumpFrames(tester);
    await tester.tap(find.text('Olive Oil').first);
    await pumpFrames(tester);

    // Reopen on the same line, now matched and remembered.
    await tester.tap(find.text('evoo'));
    await pumpFrames(tester);

    expect(find.text('Match "evoo"'), findsOneWidget);
    expect(find.text('None of your foods match.'), findsNothing);
    expect(find.text('Olive Oil'), findsWidgets);
  });
}
