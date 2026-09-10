import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth/app/providers.dart';
import 'package:hearth/data/adapters/menu_reader.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/domain/foods/menu_import.dart';
import 'package:hearth/domain/models/food.dart';
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
      // Everything read so far, not the last batch alone. The two sit side by
      // side — "Pages 1–12 of 18 read · 6 not read yet" — and the per-batch
      // version contradicted its own neighbour: "Pages 7–12 read · 6 not read
      // yet" says the first six were not.
      expect(find.textContaining('Pages 1–12 of 18 read'), findsOneWidget);
      expect(find.textContaining('6 not read yet'), findsOneWidget);
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

    testWidgets('a document with no pages says so rather than doing nothing', (
      WidgetTester tester,
    ) async {
      // The silent path this whole change is against, one layer down: with
      // nothing to ask for, the read returned an empty batch, which the
      // screen reads as "backed out of the picker" — so tapping the button
      // did nothing at all and said nothing at all.
      await pumpHearthApp(
        tester,
        pdfPages: FakePdf(pageCount: 0),
        menuReader: _FakeMenuReader(oneRow('Falafel')),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.textContaining('no pages'),
        findsWidgets,
        reason: 'a tap that does nothing has to say why',
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

  group('what a batch actually got (review F03, F04)', () {
    MenuReading oneRow(String name) => MenuReading(
      rows: <MenuRow>[
        MenuRow(
          name: name,
          portion: '1 serving',
          macros: const Macros(kcal: 350, proteinG: 6, carbG: 24, fatG: 26),
        ),
      ],
    );

    testWidgets('a render that succeeds and an extraction that fails leaves '
        'those pages retryable', (WidgetTester tester) async {
      // F03. Coverage was committed on *render*, before the model was even
      // asked. So a failed extraction still stepped past those pages, and
      // the screen claimed them as read while showing the error saying it
      // had not worked — the paid pages, gone, with no way back but to pick
      // the file again.
      final FakePdf pdf = FakePdf(pageCount: 18);
      await pumpHearthApp(
        tester,
        pdfPages: pdf,
        menuReader: _FailingMenuReader(),
      );
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.textContaining('Pages 1–6 of 18 read'),
        findsNothing,
        reason: 'it claimed pages it never managed to read',
      );
      expect(
        find.textContaining('Read pages 1–6 of 18'),
        findsOneWidget,
        reason: 'the pages that failed have to be offered again',
      );
    });

    testWidgets('and a retry that works claims them once', (
      WidgetTester tester,
    ) async {
      final FakePdf pdf = FakePdf(pageCount: 18);
      final _FlakyMenuReader reader = _FlakyMenuReader(oneRow('Falafel'));
      await pumpHearthApp(tester, pdfPages: pdf, menuReader: reader);
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);

      reader.failNext = false;
      await tester.tap(find.textContaining('Read pages 1–6 of 18'));
      await pumpFrames(tester, frames: 20);

      expect(find.textContaining('Pages 1–6 of 18 read'), findsOneWidget);
      expect(find.textContaining('12 not read yet'), findsOneWidget);
    });

    testWidgets('a save that fails part way says so and does not duplicate', (
      WidgetTester tester,
    ) async {
      // F04. The loop minted a fresh uuid per row and had no `catch`: a
      // failure on row three left rows one and two committed, the exception
      // escaping an async `onPressed` where nothing could show it, and the
      // button live again. Pressing Save a second time inserted rows one and
      // two *again*, because their ids were new both times.
      late _HalfFailingFoods repository;
      final HearthDatabase db = await pumpHearthApp(
        tester,
        extraOverrides: <Object>[
          foodRepositoryProvider.overrideWith((Ref ref) {
            final HearthDatabase database = ref.watch(databaseProvider);
            return repository = _HalfFailingFoods(
              FoodRepository(
                database: database,
                store: FoodStore(database),
                queue: PendingWriteStore(database),
                householdId: 'household-1',
              ),
              failOn: 'Falafel',
            );
          }),
        ],
      );
      await openImporter(tester);
      await tester.enterText(find.byType(TextField).first, 'Cava');
      await paste(
        tester,
        'Chicken, 4 oz, 180, 32, 0, 7\n'
        'Falafel, 1 serving, 350, 6, 24, 26\n'
        'Rice, 4 oz, 210, 4, 44, 1',
      );

      await tester.tap(find.textContaining('Save'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.textContaining('could not be saved'),
        findsOneWidget,
        reason: 'the failure escaped with nothing on screen',
      );

      // Now let it through and press again: the rows already in are updated,
      // not inserted a second time.
      repository.failOn = null;
      await tester.tap(find.textContaining('Save'));
      await pumpFrames(tester, frames: 20);

      final List<Food> saved = await FoodStore(db)
          .all(householdId: 'household-1');
      expect(
        saved.where((Food f) => f.name == 'Chicken'),
        hasLength(1),
        reason: 'the retry saved the first row twice',
      );
      expect(saved, hasLength(3));
    });

    testWidgets(
      'a failed PDF read does not get claimed by a later photo read',
      (WidgetTester tester) async {
        // What rendered belongs to the attempt that rendered it. Left standing,
        // the next successful read of *anything* commits it — so reading
        // screenshots after a PDF read failed claimed the PDF's pages, and
        // they stopped being offered without ever having been read.
        final FakePdf pdf = FakePdf(pageCount: 18);
        final _FlakyMenuReader reader = _FlakyMenuReader(oneRow('Falafel'));
        await pumpHearthApp(
          tester,
          pdfPages: pdf,
          photoPicker: _OnePhoto(),
          menuReader: reader,
        );
        await openImporter(tester);

        await tester.tap(find.text('Read from a PDF'));
        await pumpFrames(tester, frames: 20);

        reader.failNext = false;
        await tester.tap(find.text('Read from screenshots'));
        await pumpFrames(tester, frames: 20);

        expect(
          find.textContaining('Read pages 1–6 of 18'),
          findsOneWidget,
          reason: 'the photo read swallowed the PDF pages that never worked',
        );
      },
    );

    testWidgets('two sizes of the same item stay two foods', (
      WidgetTester tester,
    ) async {
      // Deriving the id made a retry safe; deriving it from the name alone
      // would make a menu lossy. "Fries" at two sizes is two foods, and the
      // random ids this replaced could not have collapsed them.
      final HearthDatabase db = await pumpHearthApp(tester);
      await openImporter(tester);
      await tester.enterText(find.byType(TextField).first, 'Chipotle');
      await paste(
        tester,
        'Fries, 4 oz, 300, 4, 40, 14\nFries, 8 oz, 600, 8, 80, 28',
      );

      await tester.tap(find.textContaining('Save'));
      await pumpFrames(tester, frames: 20);

      // Straight off the table, rather than through a household id a test
      // would have to guess — guess it wrong and the assertion runs against
      // an empty list and calls that a pass.
      final List<FoodRow> saved = await db.select(db.foods).get();
      expect(saved, hasLength(2), reason: 'one size overwrote the other');
    });

    testWidgets('a doubt from page one outlives page two', (
      WidgetTester tester,
    ) async {
      // F04. The rows accumulate and the doubts did not: after batch two,
      // batch one's flagged values sat in the box with nothing marking them.
      final FakePdf pdf = FakePdf(pageCount: 18);
      final _NumberedMenuReader reader = _NumberedMenuReader();
      await pumpHearthApp(tester, pdfPages: pdf, menuReader: reader);
      await openImporter(tester);

      await tester.tap(find.text('Read from a PDF'));
      await pumpFrames(tester, frames: 20);
      expect(find.textContaining('doubt about batch 1'), findsOneWidget);

      await tester.tap(find.textContaining('Read pages 7–12 of 18'));
      await pumpFrames(tester, frames: 20);

      expect(
        find.textContaining('doubt about batch 1'),
        findsOneWidget,
        reason: 'the first batch\'s doubts were dropped by the second',
      );
      expect(find.textContaining('doubt about batch 2'), findsOneWidget);
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

/// Fails the first read, then works. The retry case F03 is about.
class _FlakyMenuReader implements MenuReader {
  _FlakyMenuReader(this._reading);

  final MenuReading _reading;
  bool failNext = true;

  @override
  Future<MenuReading> read(List<AiImage> images) async {
    if (failNext) {
      throw const RecipeAiException('The reader was busy.', isRetryable: true);
    }
    return _reading;
  }
}

/// A different row and a different doubt per batch, so a test can tell which
/// batch a warning belongs to.
class _NumberedMenuReader implements MenuReader {
  int _batch = 0;

  @override
  Future<MenuReading> read(List<AiImage> images) async {
    _batch++;
    return MenuReading(
      rows: <MenuRow>[
        MenuRow(
          name: 'Item from batch $_batch',
          portion: '1 serving',
          macros: const Macros(kcal: 100, proteinG: 1, carbG: 1, fatG: 1),
        ),
      ],
      uncertain: <AiUncertainty>[
        AiUncertainty(
          field: 'Item from batch $_batch',
          note: 'a doubt about batch $_batch',
        ),
      ],
    );
  }
}

/// A repository that refuses one named food, so a mid-batch failure can be
/// exercised without a broken database.
class _HalfFailingFoods implements FoodRepository {
  _HalfFailingFoods(this._real, {this.failOn});

  final FoodRepository _real;
  String? failOn;

  @override
  Future<void> save(Food food) async {
    if (food.name == failOn) throw StateError('refused ${food.name}');
    return _real.save(food);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not needed here');
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
