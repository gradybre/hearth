@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/swept_surfaces.dart';
import 'gallery.dart';

const List<Scene> _devices = <Scene>[
  Scene(name: 'grocery-add-phone'),
  Scene(name: 'grocery-add-dark', brightness: Brightness.dark),
  Scene(name: 'grocery-add-desktop', size: Size(1280, 900)),
  Scene(name: 'grocery-add-small-3x', size: Size(320, 568), textScale: 3),
];

Future<void> _capture(WidgetTester tester, Scene scene, String suffix) async {
  expect(tester.takeException(), isNull);
  await writeScene(tester, Scene(name: '${scene.name}-$suffix'));
}

Future<void> _enter(
  WidgetTester tester,
  SweepTools tools,
  String key,
  String text,
) async {
  await tester.enterText(await tools.bring(find.byKey(Key(key))), text);
  await pumpFrames(tester, frames: 6);
}

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });

  for (final Scene scene in _devices) {
    testWidgets('${scene.name}: amounts and reviewed paste', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        size: scene.size,
        brightness: scene.brightness,
        textScale: scene.textScale,
        viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
        shoppingLines: galleryShoppingLines(),
      );
      final SweepTools tools = SweepTools(tester);
      await tools.tab('Shopping');
      await tools.reach(find.text('Add item'));
      await _enter(tester, tools, 'manual-item-name', 'Coffee');
      await tools.reach(find.byKey(const Key('manual-item-add-amount')));
      await _enter(tester, tools, 'manual-item-amount', '500');
      await tools.reach(find.byKey(const Key('manual-item-unit')));
      await tools.reach(find.text('g'));
      await tools.bring(find.byKey(const Key('manual-item-amount')));
      await _capture(tester, scene, 'amount');

      // The quantity is committed directly from typed text, without Done.
      await tools.reach(find.byKey(const Key('manual-item-add')));
      await pumpFrames(tester, frames: 16);
      await tools.bring(find.text('Coffee'));
      await _capture(tester, scene, 'added');

      // At 3× text Add item follows the checklist in its scroll content.
      // Let the confirmation finish before scrolling behind its overlay.
      await tester.pump(const Duration(seconds: 5));
      await pumpFrames(tester, frames: 12);
      await tools.reach(find.text('Add item'));
      await tools.reach(find.byKey(const Key('paste-items-open')));
      await _enter(
        tester,
        tools,
        'paste-items-input',
        'Coffee\nEggs\nEggs\nPaper towels 2 packs',
      );
      await _capture(tester, scene, 'paste');
      await tools.reach(find.byKey(const Key('paste-items-review')));
      await tools.bring(find.text('2 ready to add · 2 will be skipped'));
      await _capture(tester, scene, 'review');
      await tools.bring(find.text('Already on the list · will skip'));
      await _capture(tester, scene, 'already-listed');
      await tools.reach(find.byKey(const Key('paste-add-amount-1')));
      await _enter(tester, tools, 'paste-1-amount', '12');
      await tools.bring(find.byKey(const Key('paste-1-unit')));
      await _capture(tester, scene, 'review-amount');
      await tools.bring(find.text('Repeated in this paste · will skip'));
      await _capture(tester, scene, 'repeated');
      await tools.bring(find.byKey(const Key('paste-name-3')));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('paste-name-3')))
            .controller!
            .text,
        'Paper towels 2 packs',
      );
      await _capture(tester, scene, 'literal-wording');
      await tools.bring(find.byKey(const Key('paste-items-save')));
      expect(
        find.byKey(const Key('paste-items-save')).hitTestable(),
        findsOneWidget,
      );
      await _capture(tester, scene, 'controls');
      await tools.reach(find.byKey(const Key('paste-items-save')));
      await pumpFrames(tester, frames: 16);
      expect(find.text('Added 2; skipped 2.'), findsOneWidget);
      final RenderParagraph feedback = tester.renderObject<RenderParagraph>(
        find.text('Added 2; skipped 2.'),
      );
      expect(
        feedback.getMaxIntrinsicHeight(feedback.size.width),
        lessThanOrEqualTo(feedback.size.height + 0.5),
        reason: 'The complete batch result must fit without clipped text.',
      );
      final Rect feedbackBounds = tester.getRect(
        find.text('Added 2; skipped 2.'),
      );
      final Rect shoppingBounds = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('grocery-list-scroll')),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      expect(
        feedbackBounds.bottom,
        lessThanOrEqualTo(shoppingBounds.bottom),
        reason: 'The result must stay above the shopping viewport bottom.',
      );
      await _capture(tester, scene, 'result');
    }, skip: !renderingGallery);
  }
}
