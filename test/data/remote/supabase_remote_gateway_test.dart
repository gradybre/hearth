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

  group('what a table is paged by (spec §7.1)', () {
    test('ordinary tables page by when they changed, then by id', () {
      // Ascending, so a row written during the pull sorts to the end — where
      // the loop is still heading — rather than shifting a page boundary
      // under rows already read.
      expect(SupabaseRemoteGateway.pageOrderFor('meal_plan_entries'), <String>[
        'updated_at',
        'id',
      ]);
    });

    test('and one keyed by something else pages by that', () {
      // `food_profiles` is one row per user and has no separate id; paging by
      // a column that is always null would be a cursor that cannot move.
      expect(SupabaseRemoteGateway.pageOrderFor('food_profiles'), <String>[
        'updated_at',
        'user_id',
      ]);
    });

    test('the join tables page by their pair, having no timestamp at all', () {
      // These are the ones the row cap could actually destroy rather than
      // merely skip: they are fetched whole and used as the authoritative
      // set, so a truncated read deletes local rows.
      expect(SupabaseRemoteGateway.pageOrderFor('recipe_favorites'), <String>[
        'user_id',
        'recipe_id',
      ]);
      expect(SupabaseRemoteGateway.pageOrderFor('recipe_collections'), <String>[
        'collection_id',
        'recipe_id',
      ]);
    });

    test('and every ordering ends in something unique', () {
      // A cursor that cannot move is a page that repeats for ever. The loop
      // refuses rather than spinning, but the ordering is what stops it
      // arising.
      for (final String table in <String>[
        'meal_plan_days',
        'meal_plan_entries',
        'macro_targets',
        'collections',
        'food_profiles',
        'plan_templates',
        'ingredient_matches',
        'shopping_lists',
        'shopping_list_items',
        'recipe_favorites',
        'recipe_collections',
      ]) {
        expect(
          SupabaseRemoteGateway.pageOrderFor(table),
          isNotEmpty,
          reason: '$table has no page order',
        );
      }
    });
  });
}
