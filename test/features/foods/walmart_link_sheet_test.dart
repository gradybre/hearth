import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/adapters/walmart_link_reader.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
import 'package:hearth/features/foods/read_walmart_link_sheet.dart';
import 'package:hearth/features/foods/walmart_link_controller.dart';

import '../../support/walmart_fixtures.dart';

class _Pending implements WalmartLinkReader {
  final result = Completer<WalmartLinkReading>();
  @override
  Future<WalmartLinkReading> readWalmartLink(List<AiImage> images) =>
      result.future;
}

void main() {
  for (final scale in [2.0, 3.0]) {
    for (final status in ['not_found', 'ambiguous', 'unreadable']) {
      testWidgets(
        '$status at 320px and ${scale}x keeps manual entry reachable',
        (t) async {
          t.view.physicalSize = const Size(320, 568);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final reader = _Pending();
          await t.pumpWidget(
            ProviderScope(
              overrides: [
                photoPickerProvider.overrideWithValue(WalmartFixturePicker()),
                walmartLinkReaderProvider.overrideWithValue(reader),
              ],
              child: MaterialApp(
                theme: HearthTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => showReadWalmartLinkSheet(context),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('Open'));
          await t.pumpAndSettle();
          expect(find.byTooltip('Close link reader'), findsOneWidget);
          await t.ensureVisible(find.text('Choose screenshot'));
          await t.tap(find.text('Choose screenshot'));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Read link'));
          await t.tap(find.text('Read link'));
          await t.pump();
          reader.result.complete(
            WalmartLinkReading.fromJson({'status': status}),
          );
          await t.pumpAndSettle();
          expect(
            find.textContaining(
              status == 'ambiguous'
                  ? 'More than one Walmart'
                  : 'No complete Walmart',
            ),
            findsOneWidget,
          );
          expect(find.byType(Image), findsNothing);
          await t.ensureVisible(find.text('Choose another screenshot'));
          await t.ensureVisible(find.text('Enter it manually instead'));
          await t.tap(find.text('Enter it manually instead'));
          await t.pumpAndSettle();
          expect(find.text('Open'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'reading has an accessible manual exit and ignores a late result',
    (t) async {
      final reader = _Pending();
      WalmartLinkReading? returned;
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            photoPickerProvider.overrideWithValue(WalmartFixturePicker()),
            walmartLinkReaderProvider.overrideWithValue(reader),
          ],
          child: MaterialApp(
            theme: HearthTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    returned = await showReadWalmartLinkSheet(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.tap(find.text('Choose screenshot'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Read link'));
      await t.pump();
      expect(find.text('Reading the link…'), findsOneWidget);
      expect(find.text('Enter it manually instead'), findsOneWidget);
      await t.tap(find.text('Enter it manually instead'));
      // Complete during the reverse route animation, while still mounted.
      reader.result.complete(
        WalmartLinkReading.fromJson({
          'status': 'found',
          'url': 'https://www.walmart.com/ip/10450479',
          'source': 'screenshot',
        }),
      );
      await t.pumpAndSettle();
      expect(returned, isNull);
      expect(find.text('Open'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
