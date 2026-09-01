import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/photo_picker.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';

import '../../support/app_harness.dart';

/// Importing a recipe from screenshots or a link (spec §5.3).
///
/// The migration path off MacrosFirst. Everything here stops short of the
/// network: what matters at this level is that several pictures make one
/// recipe, that a failure keeps what the user chose, and that nothing is saved
/// without being read first.
class FakeAi implements RecipeAiSource {
  FakeAi({this.answer, this.error});

  final AiRecipe? answer;
  final RecipeAiException? error;
  int extractCalls = 0;
  List<AiImage> lastImages = const <AiImage>[];
  String? lastUrl;
  String? lastText;

  @override
  Future<AiRecipe> extract({
    List<AiImage> images = const <AiImage>[],
    String? url,
    String? text,
  }) async {
    extractCalls++;
    lastImages = images;
    lastUrl = url;
    lastText = text;
    if (error != null) throw error!;
    return answer!;
  }

  @override
  Future<AiRecipe> generate({
    required List<AiTurn> turns,
    Map<String, Object?> profile = const <String, Object?>{},
  }) async => answer!;
}

class FakePicker implements PhotoPicker {
  FakePicker({this.count = 1, this.bytes});

  final int count;

  /// What the screen asked for, so the limit can be checked where it is
  /// actually applied rather than by counting widgets a scroll view has not
  /// built yet.
  int? lastMax;

  /// Null means a real (tiny) PNG. A size is for testing the too-large guard,
  /// where the bytes never reach a decoder.
  final int? bytes;

  /// A 1x1 transparent PNG — the smallest thing `Image.memory` will decode.
  static final Uint8List _onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  bool get canUseCamera => true;

  PickedPhoto _photo() => PickedPhoto(
    bytes: bytes == null ? _onePixelPng : Uint8List(bytes!),
    extension: 'png',
  );

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async => _photo();

  @override
  Future<List<PickedPhoto>> pickMultiple({int max = 10}) async {
    lastMax = max;
    return <PickedPhoto>[for (int i = 0; i < count && i < max; i++) _photo()];
  }
}

AiRecipe shortRibs({List<AiUncertainty> uncertain = const <AiUncertainty>[]}) =>
    AiRecipe(
      title: 'Braised short ribs',
      servings: 4,
      uncertain: uncertain,
      sections: const <AiSection>[
        AiSection(
          name: '',
          ingredientsText: '2 tbsp olive oil\n1.5 kg short ribs',
          directionsText: 'Brown the ribs.\nBraise for three hours.',
        ),
      ],
    );

Future<void> openImport(
  WidgetTester tester, {
  RecipeAiSource? ai,
  PhotoPicker? picker,
}) async {
  await pumpHearthApp(tester, recipeAi: ai, photoPicker: picker);
  await tester.tap(find.byIcon(Icons.document_scanner_outlined));
  await pumpFrames(tester);
}

void main() {
  imageLimitTests();

  testWidgets('the library offers importing beside typing one in', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester);

    expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);
    // And beside it, having Hearth write one (§5.4).
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(find.text('New recipe'), findsOneWidget);
  });

  testWidgets('several pictures are one recipe, and it says so', (
    WidgetTester tester,
  ) async {
    final FakeAi ai = FakeAi(answer: shortRibs());
    await openImport(tester, ai: ai, picker: FakePicker(count: 2));

    // The sentence that stops someone importing three screens as three
    // recipes.
    expect(find.textContaining('not two recipes'), findsOneWidget);

    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read the recipe'));
    await pumpFrames(tester, frames: 20);

    expect(ai.extractCalls, 1);
    expect(ai.lastImages, hasLength(2));
  });

  testWidgets('nothing chosen means nothing to read', (
    WidgetTester tester,
  ) async {
    await openImport(tester, ai: FakeAi(answer: shortRibs()));

    final Finder button = find.widgetWithText(FilledButton, 'Read the recipe');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });

  testWidgets('what came back is reviewed in the editor, not saved', (
    WidgetTester tester,
  ) async {
    await openImport(
      tester,
      ai: FakeAi(answer: shortRibs()),
      picker: FakePicker(),
    );

    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read the recipe'));
    await pumpFrames(tester, frames: 20);

    // The editor is the review screen (CLAUDE.md rule 4) — filled in, and
    // still asking to be saved rather than having saved itself.
    expect(find.text('Check and save'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Braised short ribs',
    );
  });

  testWidgets('a rebuild while the reading is done does not open it twice', (
    WidgetTester tester,
  ) async {
    // Importing two images once produced three identical recipes. The review
    // screen was pushed from build(), so every rebuild that happened while the
    // state was Done pushed another copy — a keyboard dismissing during the
    // transition is enough — and saving each stacked editor in turn saved the
    // same recipe again.
    await openImport(
      tester,
      ai: FakeAi(answer: shortRibs()),
      picker: FakePicker(count: 2),
    );

    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read the recipe'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Check and save'), findsOneWidget);

    // A metrics change — the keyboard going away — rebuilds the screen
    // underneath while it is still in the Done state.
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.reset);
    await pumpFrames(tester, frames: 20);

    // Backing out of the review must land on the import screen, not on
    // another identical review waiting behind it.
    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Check and save'), findsNothing);
    expect(find.text('Import a recipe'), findsOneWidget);
  });

  testWidgets('what the reader was unsure of is named, not just counted', (
    WidgetTester tester,
  ) async {
    await openImport(
      tester,
      ai: FakeAi(
        answer: shortRibs(
          uncertain: const <AiUncertainty>[
            AiUncertainty(field: 'salt', note: 'Could be 1/2 tsp or 12 tsp.'),
          ],
        ),
      ),
      picker: FakePicker(),
    );

    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read the recipe'));
    await pumpFrames(tester, frames: 20);

    // "Check the recipe" makes you re-read all of it; this sends you to one
    // field (§5.3).
    expect(find.text('One thing worth checking'), findsOneWidget);
    expect(find.textContaining('1/2 tsp or 12 tsp'), findsOneWidget);
  });

  testWidgets('a failure keeps the pictures and offers another go', (
    WidgetTester tester,
  ) async {
    final FakeAi ai = FakeAi(
      error: const RecipeAiException('The reader was busy.'),
    );
    await openImport(tester, ai: ai, picker: FakePicker());

    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read the recipe'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('The reader was busy.'), findsOneWidget);
    // §5.3's fail-soft: nothing the user captured is lost.
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await pumpFrames(tester, frames: 20);

    expect(ai.extractCalls, 2, reason: 'retry asks again with the same images');
  });

  testWidgets('a failure that retrying cannot fix does not offer a retry', (
    WidgetTester tester,
  ) async {
    await openImport(
      tester,
      ai: FakeAi(
        error: const RecipeAiException(
          'That is not a url.',
          isRetryable: false,
        ),
      ),
      picker: FakePicker(),
    );

    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read the recipe'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('That is not a url.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a build with no backend says so instead of failing later', (
    WidgetTester tester,
  ) async {
    await openImport(tester, picker: FakePicker());

    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);
    await tester.tap(find.text('Read the recipe'));
    await pumpFrames(tester, frames: 20);

    expect(find.textContaining('none configured'), findsOneWidget);
  });
}

/// How many screens one recipe is allowed to span (spec §5.3).
void imageLimitTests() {
  testWidgets('a recipe may span ten screens, not three', (
    WidgetTester tester,
  ) async {
    // Three quietly truncated a long recipe: the pages past the third were
    // simply not picked, and nothing on screen said so.
    final FakePicker picker = FakePicker(count: 5);
    await openImport(tester, picker: picker);
    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);

    expect(picker.lastMax, 10);
    expect(find.text('5 of 10 pictures'), findsOneWidget);
    // Still room for more, where three would already have been full.
    expect(find.text('Choose pictures'), findsOneWidget);
  });

  testWidgets('picking more than ten stops at ten rather than silently', (
    WidgetTester tester,
  ) async {
    // The strip scrolls sideways, so counting the pictures on screen counts
    // only the visible ones. The line under it is the honest total.
    await openImport(tester, picker: FakePicker(count: 14));
    await tester.tap(find.text('Choose pictures'));
    await pumpFrames(tester);

    expect(find.text('10 of 10 pictures'), findsOneWidget);
    expect(find.text('Choose pictures'), findsNothing);
  });
}
