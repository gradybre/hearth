import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/mappers/recipe_mapper.dart';
import 'package:hearth/data/mappers/sync_payload.dart';
import 'package:hearth/domain/models/recipe.dart';

import '../../support/fixtures.dart';

/// Whether a recipe is cooked or eaten out, through the wire (spec §5.2).
///
/// The two halves of the mapper drifting apart is how a column goes quietly
/// missing, and this one decides whether a planned meal sends you to the shop
/// — so it is read straight back rather than trusted.
void main() {
  test('an eaten-out recipe stays eaten out', () {
    final Map<String, Object?> json = RecipeMapper.toJson(
      aRecipe(title: 'Burrito bowl', servings: 1, kind: RecipeKind.eatenOut),
      updatedAt: DateTime.utc(2026, 9, 5),
    );
    expect(json['kind'], 'eaten_out');

    expect(SyncPayload.recipe(json).kind, RecipeKind.eatenOut);
    expect(SyncPayload.recipe(json).isEatenOut, isTrue);
  });

  test('an ordinary recipe stays cooked', () {
    final Map<String, Object?> json = RecipeMapper.toJson(
      aRecipe(title: 'Chilli'),
      updatedAt: DateTime.utc(2026, 9, 5),
    );
    expect(json['kind'], 'cooked');
    expect(SyncPayload.recipe(json).kind, RecipeKind.cooked);
  });

  test('a payload from before the column existed reads as cooked', () {
    // Every recipe already in the hosted database was written by a client
    // that had never heard of `kind`, and all of them are ones you cook.
    final Map<String, Object?> json = RecipeMapper.toJson(
      aRecipe(title: 'Chilli'),
      updatedAt: DateTime.utc(2026, 9, 5),
    )..remove('kind');

    expect(SyncPayload.recipe(json).kind, RecipeKind.cooked);
  });

  test('a kind written by some future client degrades rather than throws', () {
    // A pull that threw on an unrecognised value would break sync for every
    // record behind it. Reading it as an ordinary recipe loses a distinction;
    // throwing loses the day.
    final Map<String, Object?> json = RecipeMapper.toJson(
      aRecipe(title: 'Chilli'),
      updatedAt: DateTime.utc(2026, 9, 5),
    )..['kind'] = 'delivered_by_drone';

    expect(SyncPayload.recipe(json).kind, RecipeKind.cooked);
  });
}
