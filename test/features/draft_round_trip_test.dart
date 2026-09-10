import 'dart:convert';

import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/features/foods/food_draft.dart';
import 'package:hearth/features/recipes/recipe_draft.dart';
import 'package:test/test.dart';

/// A draft written to the database comes back as the same draft (review N01).
///
/// The serialisers are hand-written, and the hazard with a hand-written one is
/// the field somebody forgets — which here means a recovered draft quietly
/// missing the notes, or the tags, or the matching decisions. That is the
/// defect the whole draft feature exists to prevent, arriving through the
/// mechanism meant to prevent it.
///
/// So these fixtures set **every field to something other than its default**
/// and lean on the value equality the unsaved-work guard already needs: a
/// field carried in `_props` and left out of `toJson` cannot survive the trip,
/// and the comparison fails. The two mechanisms hold each other up.
///
/// The bound, stated rather than implied: a field added to *neither* the
/// equality nor the JSON is invisible to this, exactly as it is to the guard.
/// A new field belongs in three places, and this catches two of the three
/// ways of forgetting.
void main() {
  group('a recipe draft', () {
    const RecipeDraft full = RecipeDraft(
      title: 'Braised short ribs',
      servings: 4.5,
      sections: <DraftSection>[
        DraftSection(
          name: 'Sauce',
          ingredientsText: '2 tbsp olive oil\n3 cloves garlic',
          directionsText: 'Sear, then braise.',
          existingId: 'section-1',
        ),
        DraftSection(name: 'To serve', ingredientsText: 'parsley'),
      ],
      prepMinutes: 20,
      cookMinutes: 180,
      cuisine: 'French',
      kind: RecipeKind.eatenOut,
      tags: <String>['Batch', 'Sunday'],
      notes: 'The butcher cuts these thick.',
      existingId: 'recipe-1',
      iconSvg: '<svg/>',
      matches: <String, String>{'olive oil': 'food-1'},
      noMatch: <String>{'salt'},
    );

    test('survives the round trip whole', () {
      expect(RecipeDraft.fromJson(full.toJson()), full);
    });

    test('and survives it as text, which is how it is stored', () {
      // The database column is text, so the trip is through `jsonEncode` as
      // well — which is where a `Set` or a `double` that looked fine in a map
      // stops being what it was.
      final Object? decoded = jsonDecode(jsonEncode(full.toJson()));
      expect(RecipeDraft.fromJson(decoded! as Map<String, Object?>), full);
    });

    test('an empty draft round-trips too', () {
      const RecipeDraft blank = RecipeDraft(title: '', servings: 1);
      expect(RecipeDraft.fromJson(blank.toJson()), blank);
    });
  });

  group('a food draft', () {
    const FoodDraft full = FoodDraft(
      name: 'Greek yogurt',
      brand: 'Fage',
      menuGroup: 'Dairy',
      menuOrder: 3,
      storeTag: 'Chilled',
      walmartItemId: '12345',
      packSize: '500 g',
      barcode: '5000000000000',
      servings: <ServingDraft>[
        ServingDraft(
          amount: '170',
          unitId: 'g',
          kcal: '100',
          protein: '17',
          carbs: '6',
          fat: '0',
          fiber: '0',
          sodium: '65',
          cholesterol: '10',
          id: 'serving-1',
        ),
      ],
      existingId: 'food-1',
      source: FoodSource.restaurant,
      isDefault: true,
      isZeroCalorie: true,
      isModifier: true,
    );

    test('survives the round trip whole', () {
      expect(FoodDraft.fromJson(full.toJson()), full);
    });

    test('and survives it as text', () {
      final Object? decoded = jsonDecode(jsonEncode(full.toJson()));
      expect(FoodDraft.fromJson(decoded! as Map<String, Object?>), full);
    });
  });
}
