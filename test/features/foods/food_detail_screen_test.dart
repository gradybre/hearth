import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_detail_screen.dart';

const String _foodId = 'current-food';

ServingOption _serving({
  String id = 'small',
  String label = 'Small bowl',
  double amount = 1,
  bool reference = false,
  Macros macros = const Macros(
    kcal: 210,
    proteinG: 12.3,
    carbG: 20,
    fatG: 8,
    sodiumMg: 0,
  ),
}) => ServingOption(
  id: id,
  label: label,
  amount: Quantity.of(amount, Units.cup),
  macros: macros,
  isReference: reference,
);

Food _food({
  String? householdId,
  List<ServingOption>? servings,
  bool deleted = false,
  bool overridden = false,
  bool zeroCalorie = false,
  FoodSource source = FoodSource.manual,
}) => Food(
  id: _foodId,
  householdId: householdId,
  name: 'White bean soup',
  brand: 'Our kitchen',
  source: source,
  servingOptions: servings ?? <ServingOption>[_serving()],
  isDeleted: deleted,
  macrosOverridden: overridden,
  isZeroCalorie: zeroCalorie,
);

Future<ProviderContainer> _openFood(
  WidgetTester tester, {
  required FutureOr<Food?> Function() load,
  String? servingOptionId,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    ProviderScope(
      retry: (int retryCount, Object error) => null,
      overrides: [
        foodByIdProvider(_foodId).overrideWith((Ref ref) async => load()),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light
            ? HearthTheme.light()
            : HearthTheme.dark(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => FoodDetailScreen(
                      foodId: _foodId,
                      servingOptionId: servingOptionId,
                    ),
                  ),
                ),
                child: const Text('Open food'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open food'));
  // A pending lookup animates a spinner, so loading tests cannot settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(FoodDetailScreen)),
  );
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final String? householdId in <String?>[null, 'our-household']) {
    testWidgets(
      '${householdId == null ? 'global' : 'household'} food is read-only',
      (WidgetTester tester) async {
        final Food food = _food(householdId: householdId);
        await _openFood(tester, load: () => food);
        expect(find.text('White bean soup'), findsOneWidget);
        expect(find.text('Our kitchen'), findsOneWidget);
        expect(find.text('Source: Entered by hand'), findsOneWidget);
        expect(
          find.text('Current library values, not a past log.'),
          findsOneWidget,
        );
        expect(find.text('Current default serving'), findsOneWidget);
        expect(find.text('Small bowl'), findsOneWidget);
        expect(find.text('Per 1 cup'), findsOneWidget);
        expect(find.text('210 kcal'), findsOneWidget);
        expect(find.text('12.3 g'), findsOneWidget);
        expect(find.text('Unknown'), findsNWidgets(2));
        expect(find.text('0 mg'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        for (final String label in <String>['Edit', 'Save', 'Log', 'Log it']) {
          expect(find.text(label), findsNothing);
        }
        await _reveal(tester, find.text('Go back'));
        await tester.tap(find.text('Go back'));
        await tester.pumpAndSettle();
        expect(find.text('Open food').hitTestable(), findsOneWidget);
        expect(food.servingOptions.single.macros.proteinG, 12.3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('selected serving shows current values without using the default', (
    WidgetTester tester,
  ) async {
    Food current = _food(
      servings: <ServingOption>[
        _serving(),
        _serving(
          id: 'large',
          label: 'Large bowl',
          amount: 2,
          macros: const Macros(kcal: 430),
        ),
      ],
    );
    final ProviderContainer container = await _openFood(
      tester,
      load: () => current,
      servingOptionId: 'large',
    );
    expect(find.text('Current serving'), findsOneWidget);
    expect(find.text('Current default serving'), findsNothing);
    expect(find.text('Large bowl'), findsOneWidget);
    expect(find.text('Per 2 cups'), findsOneWidget);
    expect(find.text('430 kcal'), findsOneWidget);
    expect(find.text('210 kcal'), findsNothing);

    current = _food(
      servings: <ServingOption>[
        _serving(),
        _serving(
          id: 'large',
          label: 'Large bowl',
          amount: 2,
          macros: const Macros(kcal: 440),
        ),
      ],
    );
    container.invalidate(foodByIdProvider(_foodId));
    await tester.pumpAndSettle();
    expect(
      find.text('440 kcal'),
      findsOneWidget,
      reason:
          '${container.read(foodByIdProvider(_foodId))}; '
          '${tester.widgetList<Text>(find.byType(Text)).map((Text text) => text.data).toList()}',
    );
    expect(find.text('430 kcal'), findsNothing);
  });

  testWidgets(
    'removed planned serving has an explicit current-default fallback',
    (WidgetTester tester) async {
      final Food food = _food();
      await _openFood(
        tester,
        load: () => food,
        servingOptionId: 'removed-serving',
      );
      expect(
        find.textContaining('selected in your plan is no longer available'),
        findsOneWidget,
      );
      expect(find.textContaining('Your plan has not changed'), findsOneWidget);
      expect(find.text('Current default serving'), findsOneWidget);
      expect(find.text('210 kcal'), findsOneWidget);
      expect(food.servingOptions.single.id, 'small');
    },
  );

  testWidgets(
    'unreadable planned serving is explained without claiming it is the default',
    (WidgetTester tester) async {
      await _openFood(
        tester,
        load: () => _food(
          servings: <ServingOption>[
            _serving(amount: 0),
            _serving(id: 'usable', label: 'Current bowl'),
          ],
        ),
        servingOptionId: 'small',
      );
      expect(
        find.textContaining('selected in your plan cannot be read'),
        findsOneWidget,
      );
      expect(find.text('Current serving'), findsOneWidget);
      expect(find.text('Current default serving'), findsNothing);
      expect(find.text('Current bowl'), findsOneWidget);
    },
  );

  final Map<String, List<ServingOption>> unusable =
      <String, List<ServingOption>>{
        'empty': <ServingOption>[],
        'zero': <ServingOption>[_serving(amount: 0)],
        'negative': <ServingOption>[_serving(amount: -1)],
        'nonfinite': <ServingOption>[_serving(amount: double.nan)],
        'reference only': <ServingOption>[_serving(reference: true)],
      };
  for (final MapEntry<String, List<ServingOption>> entry in unusable.entries) {
    testWidgets(
      '${entry.key} servings leave the food readable without nutrition claims',
      (WidgetTester tester) async {
        await _openFood(tester, load: () => _food(servings: entry.value));
        expect(find.text('White bean soup'), findsOneWidget);
        expect(find.text('No usable serving'), findsOneWidget);
        expect(find.text('210 kcal'), findsNothing);
        expect(find.textContaining('Per '), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final bool deleted in <bool>[false, true]) {
    testWidgets('${deleted ? 'deleted' : 'missing'} food is unavailable', (
      WidgetTester tester,
    ) async {
      await _openFood(
        tester,
        load: () => deleted ? _food(deleted: true) : null,
      );
      expect(find.text('Food unavailable'), findsOneWidget);
      expect(find.text('White bean soup'), findsNothing);
      expect(find.text('210 kcal'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(FoodDetailScreen), findsNothing);
    });
  }

  testWidgets('loading is labeled and a failed lookup can be retried', (
    WidgetTester tester,
  ) async {
    final Completer<Food?> pending = Completer<Food?>();
    int attempts = 0;
    await _openFood(
      tester,
      load: () => ++attempts == 1 ? pending.future : _food(),
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'Loading food',
    );
    pending.completeError(StateError('private transport details'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open this food'), findsOneWidget);
    expect(find.textContaining('private transport'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('White bean soup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('estimate and household correction retain their qualifications', (
    WidgetTester tester,
  ) async {
    await _openFood(
      tester,
      load: () => _food(source: FoodSource.aiEstimate, overridden: true),
    );
    expect(find.text('Source: AI estimate'), findsOneWidget);
    expect(find.text('Nutrition corrected in your household.'), findsOneWidget);
    expect(find.text('Unknown'), findsNWidgets(2));
  });

  for (final bool zeroCalorie in <bool>[false, true]) {
    testWidgets(
      'zero values ${zeroCalorie ? 'are confirmed' : 'remain qualified'}',
      (WidgetTester tester) async {
        await _openFood(
          tester,
          load: () => _food(
            servings: <ServingOption>[_serving(macros: Macros.zero)],
            zeroCalorie: zeroCalorie,
          ),
        );
        expect(find.text('0 kcal'), findsOneWidget);
        expect(
          find.textContaining('Nutrition may be incomplete'),
          zeroCalorie ? findsNothing : findsOneWidget,
        );
        expect(find.text('Unknown'), findsNWidgets(3));
      },
    );
  }

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      '320pt 3x ${brightness.name} food details keep nutrients and return reachable',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        await _openFood(
          tester,
          load: () => _food(),
          textScale: 3,
          brightness: brightness,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        expect(
          tester.getSemantics(find.byType(BackButton)).rect.shortestSide,
          greaterThanOrEqualTo(44),
        );
        await _reveal(tester, find.text('Protein'));
        expect(find.bySemanticsLabel('Protein: 12.3 g'), findsOneWidget);
        await _reveal(tester, find.text('Cholesterol'));
        expect(find.bySemanticsLabel('Cholesterol: Unknown'), findsOneWidget);
        await _reveal(tester, find.text('Go back'));
        expect(find.text('Go back').hitTestable(), findsOneWidget);
        expect(
          tester.getSize(find.widgetWithText(OutlinedButton, 'Go back')).height,
          greaterThanOrEqualTo(44),
        );
        await tester.tap(find.text('Go back'));
        await tester.pumpAndSettle();
        expect(find.byType(FoodDetailScreen), findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
