import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';

import '../../support/app_harness.dart';
import 'recipe_import_test.dart' show FakeAi, FakePicker, tapRead;

/// Asking for a change instead of typing it (spec §5.4).
void main() {
  AiRecipe ribs({String directions = 'Brown the ribs.\nBraise for hours.'}) =>
      AiRecipe(
        title: 'Braised short ribs',
        servings: 4,
        sections: <AiSection>[
          AiSection(
            name: '',
            ingredientsText: '1.5 kg beef short ribs\n2 tbsp olive oil',
            directionsText: directions,
          ),
        ],
        reply: 'Swapped the two steps.',
      );

  Future<FakeAi> openEditorViaImport(WidgetTester tester, FakeAi ai) async {
    await pumpHearthApp(tester, recipeAi: ai, photoPicker: FakePicker());
    await tester.tap(find.byIcon(Icons.document_scanner_outlined));
    await pumpFrames(tester);
    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tapRead(tester);
    await pumpFrames(tester, frames: 20);
    return ai;
  }

  /// Scrolls back up to a field, after asking has left us at the chat card.
  ///
  /// The panel sits at the foot of the editor, so asking a question leaves the
  /// recipe's own fields off screen — and a ListView does not build those.
  Future<void> revealField(WidgetTester tester, String text) =>
      tester.scrollUntilVisible(
        find.widgetWithText(TextField, text),
        -300,
        scrollable: find.byType(Scrollable).first,
      );

  Future<void> ask(WidgetTester tester, String what) async {
    await tester.scrollUntilVisible(
      find.text('Ask for a change'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'What should change?'),
      what,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
    await pumpFrames(tester, frames: 20);
  }

  testWidgets('a note on the upload page reaches the reader', (
    WidgetTester tester,
  ) async {
    // The reader cannot know from the page which end of a range was meant.
    final FakeAi ai = FakeAi(answer: ribs());
    await pumpHearthApp(tester, recipeAi: ai, photoPicker: FakePicker());
    await tester.tap(find.byIcon(Icons.document_scanner_outlined));
    await pumpFrames(tester);
    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Take the higher number in any range. '
        'This serves 6, not 4.',
      ),
      'Take the higher number in any range.',
    );
    await tapRead(tester);
    await pumpFrames(tester, frames: 20);

    expect(ai.lastNotes, 'Take the higher number in any range.');
  });

  testWidgets('a change asked for lands in the fields', (
    WidgetTester tester,
  ) async {
    final FakeAi ai = await openEditorViaImport(tester, FakeAi(answer: ribs()));
    ai.answer2 = ribs(directions: 'Braise for hours.\nBrown the ribs.');

    await ask(tester, 'Swap the two steps.');

    // The reply says what changed — without it you would diff two recipes by
    // eye — and the fields have already changed.
    expect(find.text('Swapped the two steps.'), findsOneWidget);

    await revealField(tester, 'Braise for hours.\nBrown the ribs.');
    expect(
      find.widgetWithText(TextField, 'Braise for hours.\nBrown the ribs.'),
      findsOneWidget,
    );
  });

  testWidgets('the recipe sent is the one on screen, not the one imported', (
    WidgetTester tester,
  ) async {
    // A hand edit made before asking must not be silently undone by the
    // answer, which means the draft is read at the moment of asking.
    final FakeAi ai = await openEditorViaImport(tester, FakeAi(answer: ribs()));
    ai.answer2 = ribs();

    await tester.enterText(
      find.widgetWithText(
        TextField,
        '1.5 kg beef short ribs\n2 tbsp olive oil',
      ),
      '2 kg beef short ribs\n2 tbsp olive oil',
    );
    await pumpFrames(tester);
    await ask(tester, 'Anything.');

    expect(ai.lastRecipe, contains('2 kg beef short ribs'));
    expect(ai.lastRecipe, isNot(contains('1.5 kg')));
  });

  testWidgets('undo puts it back exactly', (WidgetTester tester) async {
    // Applying straight into the fields is what makes it quick; this is what
    // makes it safe.
    final FakeAi ai = await openEditorViaImport(tester, FakeAi(answer: ribs()));
    ai.answer2 = ribs(directions: 'Braise for hours.\nBrown the ribs.');

    await ask(tester, 'Swap the two steps.');
    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    await pumpFrames(tester);

    await revealField(tester, 'Brown the ribs.\nBraise for hours.');
    expect(
      find.widgetWithText(TextField, 'Brown the ribs.\nBraise for hours.'),
      findsOneWidget,
    );
  });

  testWidgets('a build with no backend does not offer the chat at all', (
    WidgetTester tester,
  ) async {
    // Same rule as every other AI surface: a box that leads nowhere is worse
    // than no box.
    await pumpHearthApp(tester);
    await tester.tap(find.text('New recipe'));
    await pumpFrames(tester);

    expect(find.text('Ask for a change'), findsNothing);
  });
}
