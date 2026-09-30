@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/shopping_assistant.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';

import '../support/app_harness.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

/// Opening the relocated assistant must never make a paid request.
class _UncalledAssistant implements ShoppingAssistant {
  @override
  Future<ShoppingAnswer> edit({
    required List<ShoppingTurn> turns,
    required List<ShoppingLine> lines,
  }) => throw StateError('The gallery must not ask the assistant.');
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in const <Scene>[
    Scene(name: 'shopping-assistant'),
    Scene(name: 'shopping-assistant-dark', brightness: Brightness.dark),
    Scene(name: 'shopping-assistant-3x', size: Size(320, 568), textScale: 3),
  ]) {
    testWidgets('gallery: ${scene.name}', (WidgetTester tester) async {
      await pumpHearthApp(
        tester,
        size: scene.size,
        textScale: scene.textScale,
        brightness: scene.brightness,
        viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
        shoppingLines: galleryShoppingLines(),
        shoppingAssistant: _UncalledAssistant(),
      );
      for (final String label in <String>[
        'Shopping',
        'More',
        'Ask for a change',
      ]) {
        await pressLabel(tester, label);
        await pumpFrames(tester, frames: 20);
      }
      expect(find.text('Ask for a change'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await writeScene(tester, scene);
      await SweepTools(tester).bring(find.widgetWithText(FilledButton, 'Ask'));
      expect(
        find.widgetWithText(FilledButton, 'Ask').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await writeScene(tester, Scene(name: '${scene.name}-controls'));
    }, skip: !renderingGallery);
  }
}
