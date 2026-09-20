import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/walmart_fixtures.dart';

Future<void> _reach(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
  }
  await t.ensureVisible(finder.last);
  await pumpFrames(t);
}

Future<void> _read(WidgetTester t, WalmartFixtureReader reader) async {
  final action = find.text('Read link from screenshot');
  await _reach(t, action);
  await t.tap(action);
  await pumpFrames(t);
  final choose = find.text('Choose screenshot');
  await t.ensureVisible(choose);
  await t.tap(choose);
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await pumpFrames(t);
  expect(reader.calls, 0);
  await t.ensureVisible(find.text('Read link'));
  await t.tap(find.text('Read link'));
  await pumpFrames(t);
  expect(reader.calls, 1);
}

void main() {
  for (final existing in [false, true]) {
    testWidgets(
      'screenshot ${existing ? "proposes replacement" : "fills empty field"} before save',
      (t) async {
        final reader = WalmartFixtureReader();
        final db = await pumpHearthApp(
          t,
          labelReader: reader,
          photoPicker: WalmartFixturePicker(),
        );
        await t.tap(find.text('Foods').last);
        await pumpFrames(t);
        await t.tap(find.text('Add food'));
        await pumpFrames(t);
        await t.tap(find.text('Enter it by hand'));
        await pumpFrames(t);
        await t.enterText(find.byType(TextField).first, 'Synthetic corn');
        final field = find.widgetWithText(
          TextField,
          'walmart.com/ip/…/10450479',
        );
        await _reach(t, field);
        if (existing) await t.enterText(field, '98765432');
        await _read(t, reader);
        await _reach(t, field);
        expect(
          t.widget<TextField>(field).controller!.text,
          existing ? '98765432' : 'https://www.walmart.com/ip/10450479',
        );
        expect(await db.select(db.foods).get(), isEmpty);
        if (existing) {
          await _reach(t, find.text('Use this link'));
          await t.tap(find.text('Use this link'));
          await pumpFrames(t);
          expect(
            t.widget<TextField>(field).controller!.text,
            'https://www.walmart.com/ip/10450479',
          );
        }
        await t.tap(find.widgetWithText(FilledButton, 'Save'));
        await pumpFrames(t, frames: 15);
        final saved = (await db.select(db.foods).get()).single;
        expect(saved.walmartItemId, '10450479');
        expect(saved.name, 'Synthetic corn');
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('typing dismisses a stale replacement proposal', (t) async {
    final reader = WalmartFixtureReader();
    await pumpHearthApp(
      t,
      labelReader: reader,
      photoPicker: WalmartFixturePicker(),
    );
    await t.tap(find.text('Foods').last);
    await pumpFrames(t);
    await t.tap(find.text('Add food'));
    await pumpFrames(t);
    await t.tap(find.text('Enter it by hand'));
    await pumpFrames(t);
    final field = find.widgetWithText(TextField, 'walmart.com/ip/…/10450479');
    await _reach(t, field);
    await t.enterText(field, '98765432');
    await _read(t, reader);
    await _reach(t, find.text('Use this link'));
    await t.scrollUntilVisible(
      field,
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    await t.enterText(field, '12345678');
    await pumpFrames(t);
    expect(find.text('Use this link'), findsNothing);
    expect(t.widget<TextField>(field).controller!.text, '12345678');
  });
}
