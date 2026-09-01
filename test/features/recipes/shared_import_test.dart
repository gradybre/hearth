import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/shared_content.dart';

import '../../support/app_harness.dart';
import 'recipe_import_test.dart' show FakeAi, FakePicker;

/// A recipe arriving from another app's share sheet (spec §5.3).
///
/// The share extension itself cannot be tested — it is a separate iOS process
/// with no Dart in it — so the seam is put here deliberately: everything from
/// "something was shared" onwards runs against a fake.
class FakeShare implements SharedContentSource {
  FakeShare({this.waiting});

  /// What was shared before the app was listening — the cold-start case, and
  /// the common one, since the extension runs while Hearth is closed.
  final SharedContent? waiting;

  final StreamController<SharedContent> _later =
      StreamController<SharedContent>.broadcast();

  @override
  Stream<SharedContent> get incoming => _later.stream;

  @override
  Future<SharedContent?> pending() async => waiting;
}

/// A 1x1 transparent PNG — the smallest thing an image decoder will take.
Uint8List aPng() => Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, //
  13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

Future<FakeAi> openShared(WidgetTester tester, SharedContent shared) async {
  final FakeAi ai = FakeAi(answer: null);
  await pumpHearthApp(
    tester,
    recipeAi: ai,
    photoPicker: FakePicker(),
    sharedContent: FakeShare(waiting: shared),
  );
  await pumpFrames(tester, frames: 12);
  return ai;
}

void main() {
  testWidgets('a shared link opens the import screen with it filled in', (
    WidgetTester tester,
  ) async {
    await openShared(
      tester,
      const SharedContent(url: 'https://halfbakedharvest.com/short-ribs/'),
    );

    expect(find.text('Read the recipe'), findsOneWidget);
    expect(
      find.widgetWithText(
        TextField,
        'https://halfbakedharvest.com/short-ribs/',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a shared Instagram reel says what to do instead', (
    WidgetTester tester,
  ) async {
    // The whole reason this feature is shaped the way it is. Instagram serves
    // a login wall to anything that is not a signed-in browser, so reading the
    // page would come back with no caption in it — and "that did not work"
    // would send someone to try the same thing again.
    await openShared(
      tester,
      const SharedContent(url: 'https://www.instagram.com/reel/C8QltHYyPqe/'),
    );

    expect(find.textContaining('Screenshot the caption'), findsOneWidget);
  });

  testWidgets('and does not offer to read it anyway', (
    WidgetTester tester,
  ) async {
    await openShared(
      tester,
      const SharedContent(url: 'https://www.instagram.com/reel/C8QltHYyPqe/'),
    );

    final FilledButton read = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Read the recipe'),
    );
    expect(read.onPressed, isNull);
  });

  testWidgets('a recipe shared as text is read as it stands', (
    WidgetTester tester,
  ) async {
    // What a creator's DM actually contains when you comment "recipe": the
    // whole thing, as words. Nothing to fetch and nothing to photograph.
    const String dm =
        '2 lb ground beef\n1 tbsp soy sauce\nBrown the beef, add the sauce.';
    final FakeAi ai = await openShared(tester, const SharedContent(text: dm));

    expect(find.widgetWithText(TextField, dm), findsOneWidget);

    await tester.tap(find.text('Read the recipe'));
    await pumpFrames(tester);

    expect(ai.lastText, dm);
  });

  testWidgets('a shared screenshot is queued like any other picture', (
    WidgetTester tester,
  ) async {
    await openShared(tester, SharedContent(images: <Uint8List>[aPng()]));

    expect(find.text('Read the recipe'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('a share while nothing was shared changes nothing', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, sharedContent: FakeShare());
    await pumpFrames(tester, frames: 12);

    // Still on the library, not pushed into an empty import.
    expect(find.text('Read the recipe'), findsNothing);
  });
}
