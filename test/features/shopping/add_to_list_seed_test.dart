import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/shopping/add_to_list_sheet.dart';

import '../../support/fixtures.dart';

class _Result {
  bool completed = false;
  ListAddition? addition;
}

Recipe _recipe({double servings = 4}) => aRecipe(
  id: 'beans',
  title: 'White bean supper',
  servings: servings,
  ingredients: <RecipeIngredient>[
    anIngredient('white beans', amount: 2, unit: Units.can),
  ],
);

Future<_Result> _open(
  WidgetTester tester, {
  required Recipe recipe,
  double? servings = 8,
  bool seeded = true,
  double textScale = 1,
}) async {
  final _Result result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      theme: HearthTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => FilledButton(
            onPressed: () async {
              result.addition = await showAddToListSheet(
                context,
                recipes: <Recipe>[recipe],
                foods: const <Food>[],
                recipe: seeded ? recipe : null,
                servings: seeded ? servings : null,
              );
              result.completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets(
    'seed opens the quantity review and returns the original recipe',
    (WidgetTester tester) async {
      final Recipe recipe = _recipe();
      final _Result result = await _open(tester, recipe: recipe);
      expect(find.text('Add ingredients'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('8 servings'), findsOneWidget);
      expect(result.completed, isFalse);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to the list'));
      await tester.pumpAndSettle();
      final RecipeAddition addition = result.addition! as RecipeAddition;
      expect(identical(addition.recipe, recipe), isTrue);
      expect(addition.recipe.servings, 4);
      expect(
        addition.recipe.allIngredients.single.quantity!.canonicalAmount,
        2,
      );
      expect(addition.servings, 8.5);
    },
  );

  testWidgets(
    'seed preserves a cooking yield above the ordinary picker range',
    (WidgetTester tester) async {
      final _Result result = await _open(
        tester,
        recipe: _recipe(),
        servings: 120,
      );
      expect(find.text('120 servings'), findsOneWidget);
      await tester.tap(find.text('Add to the list'));
      await tester.pumpAndSettle();
      expect((result.addition! as RecipeAddition).servings, 120);
    },
  );

  for (final double originalYield in <double>[0.25, 120]) {
    testWidgets('recipe seed alone preserves yield $originalYield', (
      WidgetTester tester,
    ) async {
      final _Result result = await _open(
        tester,
        recipe: _recipe(servings: originalYield),
        servings: null,
      );
      if (originalYield == 0.25) {
        expect(find.text('¼ servings'), findsOneWidget);
      }
      await tester.tap(find.text('Add to the list'));
      await tester.pumpAndSettle();
      expect((result.addition! as RecipeAddition).servings, originalYield);
    });
  }

  testWidgets('Cancel returns no addition', (WidgetTester tester) async {
    final _Result result = await _open(tester, recipe: _recipe());
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result.completed, isTrue);
    expect(result.addition, isNull);
  });

  testWidgets('ordinary invocation still begins with search and choices', (
    WidgetTester tester,
  ) async {
    final _Result result = await _open(
      tester,
      recipe: _recipe(),
      seeded: false,
    );
    expect(find.text('What do you need?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('White bean supper'));
    await tester.pumpAndSettle();
    expect(find.text('4 servings'), findsOneWidget);
    await tester.ensureVisible(find.text('Add to the list'));
    await tester.tap(find.text('Add to the list'));
    await tester.pumpAndSettle();
    expect((result.addition! as RecipeAddition).servings, 4);
  });

  for (final double badYield in <double>[0, double.nan, double.infinity]) {
    testWidgets(
      'invalid recipe yield $badYield explains why Add is unavailable',
      (WidgetTester tester) async {
        await _open(tester, recipe: _recipe(servings: badYield));
        expect(find.textContaining('positive recipe yield'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Add to the list'),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final double textScale in <double>[1, 3]) {
    testWidgets(
      'seed review fits 320 by 568 at $textScale text with safe areas',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
        addTearDown(tester.view.reset);
        final _Result result = await _open(
          tester,
          recipe: _recipe(),
          textScale: textScale,
        );
        await tester.scrollUntilVisible(
          find.text('8 servings'),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        final RenderParagraph amount = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('8 servings'),
            matching: find.byType(RichText),
          ),
        );
        expect(
          amount.getBoxesForSelection(
            const TextSelection(baseOffset: 2, extentOffset: 10),
          ),
          hasLength(1),
          reason: 'The word servings must not be split across several lines.',
        );
        await tester.scrollUntilVisible(
          find.text('Add to the list'),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(find.text('Add to the list'));
        await tester.pumpAndSettle();
        expect(find.text('Add to the list').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Add to the list'));
        await tester.pumpAndSettle();
        expect(result.addition, isA<RecipeAddition>());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
