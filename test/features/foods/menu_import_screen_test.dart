import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth/data/adapters/menu_reader.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/foods/menu_import.dart';
import 'package:hearth/domain/models/macros.dart';

import '../../support/app_harness.dart';

/// Adding a restaurant menu by pasting it (spec §5.2).
///
/// The review is the screen, not a step after it: what was read sits under
/// the box it was read from, so a line Hearth could not understand is visible
/// while the text that caused it is still in front of you.
void main() {
  Future<void> openImporter(WidgetTester tester) async {
    await tester.tap(find.text('Recipes').last);
    await pumpFrames(tester);
    await addRecipeVia(tester, 'Eat out');
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Paste a menu'));
    await pumpFrames(tester, frames: 12);
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).at(1), text);
    await pumpFrames(tester, frames: 12);
  }

  testWidgets('shows what it read as you paste', (WidgetTester tester) async {
    await pumpHearthApp(tester);
    await openImporter(tester);

    expect(find.text('Nothing pasted yet.'), findsOneWidget);

    await paste(tester, 'Chicken, 4 oz, 180, 32, 0, 7');

    expect(find.text('1 to add'), findsOneWidget);
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.textContaining('180 kcal'), findsOneWidget);
  });

  testWidgets('and names the lines it could not read, without dropping them', (
    WidgetTester tester,
  ) async {
    // A silent skip in a paste of thirty rows is how a menu ends up missing
    // its chicken with nobody any the wiser.
    await pumpHearthApp(tester);
    await openImporter(tester);

    await paste(
      tester,
      'Proteins\n'
      'Chicken, 4 oz, 180, 32, 0, 7\n'
      'Steak, one scoopful, 150',
    );

    // The heading is neither added nor unread — it is the shape of the menu,
    // and it renders as a heading in the review too.
    expect(find.textContaining('1 to add'), findsOneWidget);
    expect(find.textContaining('1 Hearth could not read'), findsOneWidget);
    // `findsWidgets`, not one: the pasted text is still in the box above, so
    // the words appear there too. The counts on the summary line are the
    // precise assertion.
    expect(find.textContaining('one scoopful'), findsWidgets);
  });

  testWidgets('a pasted heading becomes a section, shown as one', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester);
    await openImporter(tester);
    await tester.enterText(find.byType(TextField).first, 'Cava');
    await pumpFrames(tester);
    await paste(
      tester,
      'Proteins\nFalafel, 4 oz, 330, 12, 30, 18\n'
      'Dips\nHarissa, 2 oz, 60, 1, 4, 5',
    );

    expect(find.text('2 to add'), findsOneWidget);

    await tester.tap(find.text('Save 2'));
    await pumpFrames(tester, frames: 20);

    final List<FoodRow> foods = await db.select(db.foods).get();
    expect(
      <String?>{for (final FoodRow f in foods) f.menuGroup},
      <String>{'Proteins', 'Dips'},
    );
    // The order the sheet had them in, which is what lays the menu out.
    expect(
      foods.firstWhere((FoodRow f) => f.name == 'Falafel').menuOrder,
      lessThan(foods.firstWhere((FoodRow f) => f.name == 'Harissa').menuOrder!),
    );
  });

  testWidgets('saving writes them as that restaurant\'s foods', (
    WidgetTester tester,
  ) async {
    final HearthDatabase db = await pumpHearthApp(tester);
    await openImporter(tester);

    await tester.enterText(find.byType(TextField).first, 'Cava');
    await pumpFrames(tester);
    await paste(
      tester,
      'Falafel, 4 oz, 330, 12, 30, 18\n'
      'Harissa, 2 oz, 60, 1, 4, 5, 1, 210, 0',
    );

    await tester.tap(find.text('Save 2'));
    await pumpFrames(tester, frames: 20);

    final List<FoodRow> foods = await db.select(db.foods).get();
    expect(foods, hasLength(2));
    expect(foods.map((FoodRow f) => f.brand), everyElement('Cava'));
    expect(foods.map((FoodRow f) => f.source), everyElement('restaurant'));

    // The minor three where the sheet gave them, unknown where it did not —
    // the same distinction everywhere else keeps (spec §5.6).
    final List<FoodServingOptionRow> servings = await db
        .select(db.foodServingOptions)
        .get();
    expect(servings, hasLength(2));
    expect(servings.map((FoodServingOptionRow s) => s.sodiumMg), contains(210));
    expect(
      servings.map((FoodServingOptionRow s) => s.sodiumMg),
      contains(null),
    );
  });

  testWidgets('and will not save without a restaurant to file them under', (
    WidgetTester tester,
  ) async {
    // A restaurant food with no restaurant belongs to no menu, so it would be
    // saved and invisible.
    final HearthDatabase db = await pumpHearthApp(tester);
    await openImporter(tester);
    await paste(tester, 'Falafel, 4 oz, 330, 12, 30, 18');

    await tester.tap(find.text('Save 1'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Which restaurant?'), findsOneWidget);
    expect(await db.select(db.foods).get(), isEmpty);
  });

  testWidgets('and hands you back to the builder when it is done', (
    WidgetTester tester,
  ) async {
    // Deliberately not asserting that Cava then appears in the list. The
    // harness feeds `foodLibraryProvider` a fixed stream, because fake async
    // cannot drive real sqlite — so a food saved mid-test never reaches it,
    // and asserting otherwise would be asserting the harness. The two halves
    // are covered where they are real: the rows written here, and
    // `RestaurantMenu.restaurantsIn` picking up exactly such a food.
    final HearthDatabase db = await pumpHearthApp(tester);
    await openImporter(tester);
    await tester.enterText(find.byType(TextField).first, 'Cava');
    await pumpFrames(tester);
    await paste(tester, 'Falafel, 4 oz, 330, 12, 30, 18');

    await tester.tap(find.text('Save 1'));
    await pumpFrames(tester, frames: 20);

    // Back on the builder — its empty state, because the stubbed library
    // cannot have grown. "Paste a menu" is on that screen too, so the title
    // is what tells the two apart.
    expect(find.text('Ate out'), findsOneWidget);
    expect(find.text('No restaurants yet'), findsOneWidget);
    expect(await db.select(db.foods).get(), hasLength(1));
  });

  group('reading a menu off pictures (spec §5.2)', () {
    testWidgets('the read buttons are hidden without a backend', (
      WidgetTester tester,
    ) async {
      // Null is the honest state of a build with no backend, and a button
      // that fails on tap is worse than one that is not there.
      await pumpHearthApp(tester);
      await openImporter(tester);

      expect(find.text('Read from screenshots'), findsNothing);
    });

    testWidgets('what it read lands in the box, not in the library', (
      WidgetTester tester,
    ) async {
      // The whole design: a transcription becomes exactly the text a person
      // would have pasted, and goes through the same parser and the same live
      // review — editable before it is saved, and nothing written yet
      // (rule 4).
      final HearthDatabase db = await pumpHearthApp(
        tester,
        photoPicker: _OnePhoto(),
        menuReader: _FakeMenuReader(
          const MenuReading(
            restaurant: 'Cava',
            rows: <MenuRow>[
              MenuRow(
                name: 'Falafel',
                portion: '1 serving',
                section: 'Mains',
                macros: Macros(kcal: 350, proteinG: 6, carbG: 24, fatG: 26),
              ),
            ],
          ),
        ),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from screenshots'));
      await pumpFrames(tester, frames: 20);

      // The box holds exactly what a person would have pasted…
      final TextField box = tester.widget(find.byType(TextField).at(1));
      expect(box.controller!.text, contains('Falafel'));
      // …including the section, so it becomes a heading the same way.
      expect(box.controller!.text, contains('Mains'));

      // …and the same parser read it back. The list is lazy, so the review's
      // tail is scrolled to rather than assumed built.
      expect(find.text('1 to add'), findsOneWidget);

      // The page named the restaurant, so the field is filled rather than
      // asked for.
      final TextField name = tester.widget(find.byType(TextField).first);
      expect(name.controller!.text, 'Cava');

      // And none of it is in the library until Save (rule 4).
      expect(await db.select(db.foods).get(), isEmpty);
    });

    testWidgets('and it fills the restaurant only when it is still empty', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        photoPicker: _OnePhoto(),
        menuReader: _FakeMenuReader(
          const MenuReading(
            restaurant: 'Cava',
            rows: <MenuRow>[
              MenuRow(
                name: 'Falafel',
                portion: '1 serving',
                macros: Macros(kcal: 350),
              ),
            ],
          ),
        ),
      );
      await openImporter(tester);
      // A name already typed is a decision; a page's branding is a guess.
      await tester.enterText(find.byType(TextField).first, 'Cava Mezze');
      await pumpFrames(tester);

      await tester.tap(find.text('Read from screenshots'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Cava Mezze'), findsWidgets);
    });

    testWidgets('what the model would not vouch for is shown, not swallowed', (
      WidgetTester tester,
    ) async {
      // A value taken from the wrong column reads perfectly and is wrong in
      // every day it is later logged into.
      await pumpHearthApp(
        tester,
        photoPicker: _OnePhoto(),
        menuReader: _FakeMenuReader(
          const MenuReading(
            rows: <MenuRow>[
              MenuRow(
                name: 'Barbacoa',
                portion: '4 oz',
                macros: Macros(kcal: 170),
              ),
            ],
            uncertain: <AiUncertainty>[
              AiUncertainty(
                field: 'Barbacoa sodium',
                note: 'Row ran into the one above it.',
              ),
            ],
          ),
        ),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from screenshots'));
      await pumpFrames(tester, frames: 20);

      expect(find.text('Check these before saving'), findsOneWidget);
      expect(find.textContaining('ran into the one above'), findsOneWidget);
    });

    testWidgets('a second read adds to the box rather than wiping it', (
      WidgetTester tester,
    ) async {
      // A guide is read a page at a time, and hand-typed corrections sit in
      // the same box. Overwriting destroys both, with no undo.
      await pumpHearthApp(
        tester,
        photoPicker: _OnePhoto(),
        menuReader: _FakeMenuReader(
          const MenuReading(
            rows: <MenuRow>[
              MenuRow(
                name: 'Falafel',
                portion: '1 serving',
                macros: Macros(kcal: 350),
              ),
            ],
          ),
        ),
      );
      await openImporter(tester);
      await tester.enterText(
        find.byType(TextField).at(1),
        'Chicken, 4 oz, 180, 32, 0, 7',
      );
      await pumpFrames(tester, frames: 12);

      await tester.tap(find.text('Read from screenshots'));
      await pumpFrames(tester, frames: 20);

      final TextField box = tester.widget(find.byType(TextField).at(1));
      expect(box.controller!.text, contains('Chicken'));
      expect(box.controller!.text, contains('Falafel'));
    });

    testWidgets('a doubt from an earlier read does not outlive its rows', (
      WidgetTester tester,
    ) async {
      // A warning pointing at an item no longer on screen is worse than no
      // warning: it teaches you to ignore the panel.
      await pumpHearthApp(
        tester,
        photoPicker: _OnePhoto(),
        menuReader: _FakeMenuReader(
          const MenuReading(
            rows: <MenuRow>[
              MenuRow(
                name: 'Barbacoa',
                portion: '4 oz',
                macros: Macros(kcal: 170),
              ),
            ],
            uncertain: <AiUncertainty>[
              AiUncertainty(field: 'Barbacoa sodium', note: 'Smudged.'),
            ],
          ),
        ),
      );
      await openImporter(tester);
      await tester.tap(find.text('Read from screenshots'));
      await pumpFrames(tester, frames: 20);
      expect(find.text('Check these before saving'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).at(1),
        'Chicken, 4 oz, 180, 32, 0, 7',
      );
      await pumpFrames(tester, frames: 12);

      expect(find.text('Check these before saving'), findsNothing);
    });

    testWidgets('a read that fails for any other reason still says so', (
      WidgetTester tester,
    ) async {
      // A file dialog throwing a PlatformException is not a RecipeAiException,
      // and catching only the latter leaves the button snapping back with
      // nothing said.
      await pumpHearthApp(
        tester,
        photoPicker: _ThrowingPicker(),
        menuReader: _FakeMenuReader(const MenuReading(rows: <MenuRow>[])),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from screenshots'));
      await pumpFrames(tester, frames: 20);

      expect(find.textContaining('Could not read'), findsOneWidget);
    });

    testWidgets('a failed read says why and writes nothing', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = await pumpHearthApp(
        tester,
        photoPicker: _OnePhoto(),
        menuReader: _FailingMenuReader(),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from screenshots'));
      await pumpFrames(tester, frames: 20);

      expect(find.textContaining('looked like a menu'), findsOneWidget);
      expect(find.text('Nothing pasted yet.'), findsOneWidget);
      expect(await db.select(db.foods).get(), isEmpty);
    });
  });

  group('reading a nutrition guide a batch at a time (spec §5.2, R11)', () {
    // Every page is an image sent to the model, so a long guide is read in
    // batches. It always was — six pages, silently, with the other twelve
    // discarded and no way to know they existed. What is new is that the
    // screen says how long the document is, which pages it read, which it
    // could not, and offers the rest rather than deciding for you.
    MenuReading oneRow(String name) => MenuReading(
      rows: <MenuRow>[
        MenuRow(
          name: name,
          portion: '1 serving',
          macros: const Macros(kcal: 350, proteinG: 6, carbG: 24, fatG: 26),
        ),
      ],
    );

    testWidgets('six of eighteen is said to be six of eighteen', (
      WidgetTester tester,
    ) async {
      final FakePdf pdf = FakePdf(pageCount: 18);
      await pumpHearthApp(
        tester,
        pdfPages: pdf,
        menuReader: _FakeMenuReader(oneRow('Falafel')),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      expect(pdf.asked.single, <int>[1, 2, 3, 4, 5, 6]);
      expect(
        find.textContaining('Pages 1–6 of 18 read'),
        findsOneWidget,
        reason: 'the count is the whole point: six pages is not the document',
      );
      expect(find.textContaining('12 not read yet'), findsOneWidget);
    });

    testWidgets('and the rest is offered, one batch at a time', (
      WidgetTester tester,
    ) async {
      // Offered, not taken. A forty-page guide read whole without being asked
      // is a bill nobody agreed to.
      final FakePdf pdf = FakePdf(pageCount: 18);
      await pumpHearthApp(
        tester,
        pdfPages: pdf,
        menuReader: _FakeMenuReader(oneRow('Falafel')),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.textContaining('Read pages 7–12 of 18'));
      await pumpFrames(tester, frames: 20);

      expect(pdf.asked, <List<int>>[
        <int>[1, 2, 3, 4, 5, 6],
        <int>[7, 8, 9, 10, 11, 12],
      ], reason: 'the second read asks for the next pages, not the same six');
      expect(find.textContaining('Pages 7–12 of 18 read'), findsOneWidget);
    });

    testWidgets('a short document is read whole and offers nothing more', (
      WidgetTester tester,
    ) async {
      final FakePdf pdf = FakePdf(pageCount: 2);
      await pumpHearthApp(
        tester,
        pdfPages: pdf,
        menuReader: _FakeMenuReader(oneRow('Falafel')),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      expect(pdf.asked.single, <int>[1, 2]);
      expect(find.textContaining('Pages 1–2 of 2 read'), findsOneWidget);
      expect(
        find.textContaining('Read pages'),
        findsNothing,
        reason: 'there is nothing left to offer',
      );
      expect(find.textContaining('not read yet'), findsNothing);
    });

    testWidgets('a page that will not render is named, not dropped', (
      WidgetTester tester,
    ) async {
      // The silent one. A page that would not render used to vanish from the
      // batch without a word, so a guide came back missing a section and
      // looked complete — and nobody goes looking for an item they were never
      // told was missing.
      final FakePdf pdf = FakePdf(pageCount: 6, wontRender: <int>{3});
      await pumpHearthApp(
        tester,
        pdfPages: pdf,
        menuReader: _FakeMenuReader(oneRow('Falafel')),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.textContaining('Page 3 of 6 would not render'),
        findsOneWidget,
      );
      // And what it claims to have read excludes it, rather than saying 1–6.
      expect(
        find.textContaining('Pages 1, 2, 4, 5 and 6 of 6 read'),
        findsOneWidget,
      );
    });

    testWidgets('and comes round again rather than being skipped for ever', (
      WidgetTester tester,
    ) async {
      final FakePdf pdf = FakePdf(pageCount: 6, wontRender: <int>{3});
      await pumpHearthApp(
        tester,
        pdfPages: pdf,
        menuReader: _FakeMenuReader(oneRow('Falafel')),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.textContaining('Read page 3 of 6'));
      await pumpFrames(tester, frames: 20);

      expect(pdf.asked.last, <int>[3]);
    });

    testWidgets('a whole batch that fails says so rather than going quiet', (
      WidgetTester tester,
    ) async {
      final FakePdf pdf = FakePdf(pageCount: 2, wontRender: <int>{1, 2});
      await pumpHearthApp(
        tester,
        pdfPages: pdf,
        menuReader: _FakeMenuReader(oneRow('Falafel')),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.textContaining('would not render'),
        findsWidgets,
        reason: 'silence here is indistinguishable from backing out',
      );
    });

    testWidgets('backing out of the dialog changes nothing on screen', (
      WidgetTester tester,
    ) async {
      // Cancelling is not an error and must not cost review work. It used to:
      // the doubts from an earlier read were cleared on the way *to* the
      // picker, so opening the dialog and changing your mind left rows on
      // screen with the warnings that belonged to them gone.
      await pumpHearthApp(
        tester,
        photoPicker: _OnePhoto(),
        pdfPages: FakePdf(picks: false),
        menuReader: _FakeMenuReader(
          const MenuReading(
            rows: <MenuRow>[
              MenuRow(
                name: 'Falafel',
                portion: '1 serving',
                macros: Macros(kcal: 350, proteinG: 6, carbG: 24, fatG: 26),
              ),
            ],
            uncertain: <AiUncertainty>[
              AiUncertainty(
                field: 'Falafel',
                note: 'the carbs column was cut off',
              ),
            ],
          ),
        ),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from screenshots'));
      await pumpFrames(tester, frames: 20);
      expect(
        find.textContaining('the carbs column was cut off'),
        findsOneWidget,
      );

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.textContaining('the carbs column was cut off'),
        findsOneWidget,
        reason: 'the rows are still there, so their doubts must be too',
      );
      expect(find.textContaining('would not render'), findsNothing);
    });
  });
}

/// Answers with one prepared reading, however many pictures it is given.
class _FakeMenuReader implements MenuReader {
  _FakeMenuReader(this._reading);

  final MenuReading _reading;

  @override
  Future<MenuReading> read(List<AiImage> images) async => _reading;
}

class _FailingMenuReader implements MenuReader {
  @override
  Future<MenuReading> read(List<AiImage> images) async =>
      throw const RecipeAiException(
        'Nothing on that page looked like a menu.',
        isRetryable: false,
      );
}

/// One picture, which is all the reader is asked to be given.
class _OnePhoto implements PhotoPicker {
  /// A 1x1 transparent PNG — the smallest thing a decoder will accept.
  static final Uint8List _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  bool get canUseCamera => false;

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async =>
      PickedPhoto(bytes: _pixel, extension: 'png');

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async => <PickedPhoto>[
    PickedPhoto(bytes: _pixel, extension: 'png'),
  ];
}

/// A picker that fails the way a permission refusal does.
class _ThrowingPicker implements PhotoPicker {
  @override
  bool get canUseCamera => false;

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async =>
      throw Exception('photo access denied');

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async =>
      throw Exception('photo access denied');
}
