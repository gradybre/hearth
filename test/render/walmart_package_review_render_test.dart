@Tags(<String>['render'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/shopping/shopping_line.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/shopping_export_sheet.dart';

import 'gallery.dart';

const List<Scene> _scenes = <Scene>[
  Scene(name: 'walmart-counts-phone'),
  Scene(name: 'walmart-counts-dark', brightness: Brightness.dark),
  Scene(name: 'walmart-counts-desktop', size: Size(1280, 900)),
  Scene(name: 'walmart-counts-small-3x', size: Size(320, 568), textScale: 3),
];

void main() {
  setUpAll(() async {
    if (renderingGallery) await loadIconFont();
  });
  for (final Scene scene in _scenes) {
    testWidgets(
      '${scene.name}: known, unknown, limited and excluded packages',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scene.size;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
        tester.platformDispatcher.textScaleFactorTestValue = scene.textScale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final List<ShoppingLine> lines = <ShoppingLine>[
          for (final String name in <String>[
            'Tomato sauce',
            'Brown rice',
            'Sliced peaches',
            'Coffee',
          ])
            ShoppingLine(
              key: name,
              name: name,
              foodId: name,
              planned: <Quantity>[
                Quantity.of(name == 'Sliced peaches' ? 10000 : 600, Units.gram),
              ],
            ),
          ShoppingLine(
            key: 'Protein powder',
            name: 'Protein powder',
            foodId: 'Protein powder',
            planned: <Quantity>[Quantity.of(1, Units.scoop)],
            onHand: Quantity.of(1, Units.container),
          ),
        ];
        final Map<String, Food> foods = <String, Food>{
          for (final (String name, double? pack, String id)
              in <(String, double?, String)>[
                ('Tomato sauce', 400, '123456789'),
                ('Brown rice', null, '987654321'),
                ('Sliced peaches', 100, '555555555'),
              ])
            name: Food(
              id: name,
              householdId: 'synthetic-home',
              name: name,
              brand: 'Kitchen brand',
              source: FoodSource.manual,
              servingOptions: const <ServingOption>[],
              walmartItemId: id,
              packSize: pack == null ? null : Quantity.of(pack, Units.gram),
            ),
          'Protein powder': Food(
            id: 'Protein powder',
            householdId: 'synthetic-home',
            name: 'Protein powder',
            brand: 'Kitchen brand',
            source: FoodSource.manual,
            servingOptions: const <ServingOption>[],
            walmartItemId: '444444444',
            packSize: Quantity.of(12, Units.scoop),
          ),
        };
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: scene.brightness == Brightness.dark
                ? HearthTheme.dark()
                : HearthTheme.light(),
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showShoppingExportSheet(context, lines, foods: foods),
                  child: const Text('Export'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();
        Future<void> capture(String suffix) async {
          expect(tester.takeException(), isNull);
          await writeScene(tester, Scene(name: '${scene.name}-$suffix'));
        }

        await capture('overview');
        for (final (String key, String suffix) in <(String, String)>[
          ('Tomato sauce', 'known'),
          ('Brown rice', 'unknown'),
          ('Sliced peaches', 'limited'),
        ]) {
          await tester.ensureVisible(
            find.text('Saved product: $key · Kitchen brand'),
          );
          await tester.pumpAndSettle();
          await capture('$suffix-product');
          await Scrollable.ensureVisible(
            tester.element(find.byKey(ValueKey<String>('cart-count-$key'))),
            alignment: .2,
          );
          await tester.pumpAndSettle();
          await capture(suffix);
        }
        await tester.ensureVisible(
          find.textContaining('remaining amount unknown'),
        );
        await tester.pumpAndSettle();
        await capture('unresolved-on-hand');
        await tester.ensureVisible(find.text('Review at Walmart'));
        await tester.pumpAndSettle();
        await capture('review-action');
        await tester.ensureVisible(find.text('Copy the list'));
        await tester.pumpAndSettle();
        expect(find.text('Copy the list').hitTestable(), findsOneWidget);
        await capture('copy-action');
      },
      skip: !renderingGallery,
    );
  }
}
