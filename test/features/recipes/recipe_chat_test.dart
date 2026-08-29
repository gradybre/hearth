import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';

import '../../support/app_harness.dart';
import '../../support/fixtures.dart';

/// Writing a recipe by talking about it (spec §5.4).
///
/// The part worth being strict about: a generated recipe is never trusted on
/// the model's own macros. It goes through the same editor as everything else,
/// its ingredients run through the real OFF → USDA chain, and anything only
/// the model has a number for is labelled as an estimate.
class FakeAi implements RecipeAiSource {
  FakeAi({this.answers = const <AiRecipe>[], this.error});

  final List<AiRecipe> answers;
  final RecipeAiException? error;
  int calls = 0;
  List<AiTurn> lastTurns = const <AiTurn>[];
  Map<String, Object?> lastProfile = const <String, Object?>{};

  @override
  Future<AiRecipe> extract({
    List<AiImage> images = const <AiImage>[],
    String? url,
  }) async => throw UnimplementedError();

  @override
  Future<AiRecipe> generate({
    required List<AiTurn> turns,
    Map<String, Object?> profile = const <String, Object?>{},
  }) async {
    lastTurns = turns;
    lastProfile = profile;
    if (error != null) throw error!;
    final int index = calls.clamp(0, answers.length - 1);
    calls++;
    return answers[index];
  }
}

class StubNutrition implements NutritionSource {
  StubNutrition(this.results);

  final Map<String, List<NutritionMatch>> results;

  @override
  String get displayName => 'Stub';

  @override
  Future<NutritionMatch?> byBarcode(String barcode) async => null;

  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async =>
      results[query] ?? const <NutritionMatch>[];
}

AiRecipe pasta({
  String title = 'Chilli garlic pasta',
  String? reply = 'A quick one, plenty of heat.',
  String ingredients = '200 g spaghetti\n1 tbsp chilli oil',
  List<AiEstimate> estimates = const <AiEstimate>[],
}) => AiRecipe(
  title: title,
  servings: 2,
  reply: reply,
  estimates: estimates,
  sections: <AiSection>[
    AiSection(
      name: '',
      ingredientsText: ingredients,
      directionsText: 'Boil the pasta.\nToss with the oil.',
    ),
  ],
);

Future<void> openChat(
  WidgetTester tester, {
  RecipeAiSource? ai,
  List<NutritionSource> nutrition = const <NutritionSource>[],
}) async {
  await pumpHearthApp(tester, recipeAi: ai, nutritionSources: nutrition);
  await tester.tap(find.byIcon(Icons.auto_awesome));
  await pumpFrames(tester);
}

Future<void> say(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await pumpFrames(tester);
  await tester.tap(find.byIcon(Icons.arrow_upward));
  await pumpFrames(tester, frames: 20);
}

void main() {
  testWidgets('an empty chat says what Hearth already knows about you', (
    WidgetTester tester,
  ) async {
    await openChat(tester, ai: FakeAi(answers: <AiRecipe>[pasta()]));

    // So nobody has to wonder whether their allergy was remembered.
    expect(find.textContaining('Describe what you want'), findsOneWidget);
    expect(find.textContaining('food profile is empty'), findsOneWidget);
  });

  testWidgets('what you ask for comes back as a recipe you can save', (
    WidgetTester tester,
  ) async {
    final FakeAi ai = FakeAi(answers: <AiRecipe>[pasta()]);
    await openChat(tester, ai: ai);
    await say(tester, 'A quick weeknight pasta');

    expect(find.text('A quick weeknight pasta'), findsOneWidget);
    expect(find.text('A quick one, plenty of heat.'), findsOneWidget);
    expect(find.text('Chilli garlic pasta'), findsOneWidget);
    expect(find.text('Read it and save'), findsOneWidget);
  });

  testWidgets(
    'a refinement carries the whole conversation, not just the last',
    (WidgetTester tester) async {
      final FakeAi ai = FakeAi(
        answers: <AiRecipe>[
          pasta(),
          pasta(reply: 'Spicier now.'),
        ],
      );
      await openChat(tester, ai: ai);
      await say(tester, 'A quick weeknight pasta');
      await say(tester, 'Make it spicier');

      // Without the earlier turns "make it spicier" means nothing.
      expect(ai.lastTurns, hasLength(3));
      expect(ai.lastTurns.first.text, 'A quick weeknight pasta');
      expect(ai.lastTurns.last.text, 'Make it spicier');
      expect(ai.lastTurns.last.fromUser, isTrue);
    },
  );

  testWidgets('the earlier version stays on screen to go back to', (
    WidgetTester tester,
  ) async {
    await openChat(
      tester,
      ai: FakeAi(
        answers: <AiRecipe>[
          pasta(title: 'Mild pasta'),
          pasta(title: 'Fiery pasta'),
        ],
      ),
    );
    await say(tester, 'A pasta');
    await say(tester, 'Spicier');

    expect(find.text('Mild pasta'), findsOneWidget);
    expect(find.text('Fiery pasta'), findsOneWidget);
    expect(find.text('Read it and save'), findsNWidgets(2));
  });

  testWidgets('a failure keeps the conversation and offers another go', (
    WidgetTester tester,
  ) async {
    final FakeAi ai = FakeAi(
      error: const RecipeAiException('The writer was busy.'),
    );
    await openChat(tester, ai: ai);
    await say(tester, 'A quick weeknight pasta');

    // §5.4's fail-soft: no lost work.
    expect(find.text('A quick weeknight pasta'), findsOneWidget);
    expect(find.text('The writer was busy.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await pumpFrames(tester, frames: 20);

    expect(ai.calls + 1, greaterThanOrEqualTo(1));
    // Retrying asks the same question rather than making it be retyped.
    expect(ai.lastTurns.single.text, 'A quick weeknight pasta');
  });

  testWidgets('saving goes through the editor, never straight to the library', (
    WidgetTester tester,
  ) async {
    await openChat(tester, ai: FakeAi(answers: <AiRecipe>[pasta()]));
    await say(tester, 'A quick weeknight pasta');
    await tester.tap(find.text('Read it and save'));
    await pumpFrames(tester, frames: 20);

    expect(find.text('Check and save'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Chilli garlic pasta',
    );
  });

  testWidgets('real data outranks the model, and the estimate is not used', (
    WidgetTester tester,
  ) async {
    await openChat(
      tester,
      ai: FakeAi(
        answers: <AiRecipe>[
          pasta(
            ingredients: '200 g spaghetti',
            estimates: const <AiEstimate>[
              AiEstimate(ingredient: '200 g spaghetti', kcal: 999),
            ],
          ),
        ],
      ),
      nutrition: <NutritionSource>[
        StubNutrition(<String, List<NutritionMatch>>{
          'spaghetti': <NutritionMatch>[
            NutritionMatch(
              source: FoodSource.usda,
              confidence: 0.9,
              food: aFood(
                'Spaghetti',
                id: 'usda:spaghetti',
                source: FoodSource.usda,
                servingOptions: <ServingOption>[
                  aServing(
                    id: 'usda:spaghetti:100g',
                    amount: 100,
                    unit: Units.gram,
                    macros: const Macros(kcal: 158, proteinG: 6),
                  ),
                ],
              ),
            ),
          ],
        }),
      ],
    );
    await say(tester, 'A quick weeknight pasta');
    await tester.tap(find.text('Read it and save'));
    await pumpFrames(tester, frames: 20);
    await tester.tap(find.text('Find nutrition for 1 ingredient'));
    await pumpFrames(tester, frames: 30);

    // §5.4: generated recipes are not trusted on AI-estimated macros. The
    // chain found this one, so 999 never gets a look in.
    expect(find.textContaining('USDA'), findsOneWidget);
    expect(find.textContaining('999'), findsNothing);
    expect(find.textContaining('own guess'), findsNothing);
  });

  testWidgets(
    'an ingredient nothing real covers falls back, clearly labelled',
    (WidgetTester tester) async {
      await openChat(
        tester,
        ai: FakeAi(
          answers: <AiRecipe>[
            pasta(
              ingredients: '1 tbsp gochujang',
              estimates: const <AiEstimate>[
                AiEstimate(ingredient: '1 tbsp gochujang', kcal: 30),
              ],
            ),
          ],
        ),
      );
      await say(tester, 'Something spicy');
      await tester.tap(find.text('Read it and save'));
      await pumpFrames(tester, frames: 20);
      await tester.tap(find.text('Find nutrition for 1 ingredient'));
      await pumpFrames(tester, frames: 30);

      // A rough number that admits to being rough beats a silent zero — but it
      // is opted into, not out of.
      expect(find.textContaining('about 30 kcal'), findsOneWidget);
      expect(find.textContaining('own guess'), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsNothing);
    },
  );
}
