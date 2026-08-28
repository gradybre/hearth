import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/remote/supabase_remote_gateway.dart';

void main() {
  group('which tables go through a function', () {
    test('the two aggregates do, and nothing else', () {
      // A recipe is four tables underneath and a food is two. Pushing either
      // as separate client calls means a dropped connection can leave half
      // the old children and half the new — a record that never existed on
      // either device.
      expect(
        SupabaseRemoteGateway.aggregateFunctions.keys,
        containsAll(<String>['recipes', 'foods']),
      );
      expect(
        SupabaseRemoteGateway.aggregateFunctions.containsKey(
          'meal_plan_entries',
        ),
        isFalse,
      );
    });

    test('each names its parameter explicitly', () {
      // Deriving "p_recipe" from "recipes" works right up until a table whose
      // singular is not "drop the s", and then fails as a runtime error
      // nobody would connect to the derivation.
      expect(SupabaseRemoteGateway.aggregateFunctions['recipes'], (
        function: 'upsert_recipe',
        parameter: 'p_recipe',
      ));
      expect(SupabaseRemoteGateway.aggregateFunctions['foods'], (
        function: 'upsert_food',
        parameter: 'p_food',
      ));
    });
  });

  group('what identifies a row for a delete', () {
    test('the join tables are keyed by their pair, not by an id', () {
      // They have no id column. A delete that fell back to `id` would match
      // nothing at best, and at worst match on a column meaning something
      // else entirely.
      expect(SupabaseRemoteGateway.deleteKeys['recipe_favorites'], <String>[
        'user_id',
        'recipe_id',
      ]);
      expect(SupabaseRemoteGateway.deleteKeys['recipe_collections'], <String>[
        'collection_id',
        'recipe_id',
      ]);
    });

    test('everything else falls back to id', () {
      expect(
        SupabaseRemoteGateway.deleteKeys.containsKey('meal_plan_entries'),
        isFalse,
        reason: 'no entry means the id fallback, which is what these want',
      );
    });
  });
}
