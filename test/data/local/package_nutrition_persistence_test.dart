import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/food_store.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/pending_write_store.dart';
import 'package:hearth/data/mappers/food_mapper.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/domain/foods/food_merge.dart';
import 'package:hearth/domain/foods/pack_size_queue.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/models/package_nutrition.dart';
import 'package:hearth/domain/units/mass_display_mode.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';

/// The two fields R9-R13 added, through every place they are stored.
///
/// The failure this is for is the quiet one: a `Food` is rebuilt by hand in
/// five places, none of them a `copyWith`, and a field left out of one of
/// them does not fail to compile -- it takes its default. A household's
/// display preference silently returns to automatic, or a reviewed package
/// relationship is deleted by an unrelated save.
void main() {
  late HearthDatabase db;
  late FoodStore store;

  final DateTime now = DateTime.utc(2026, 9, 19, 12);
  const String household = 'household-1';

  // Looked up rather than named, so this test does not have to guess at the
  // Dart identifier for a unit whose id the schema already fixes.
  final Unit ounce = Units.byId('oz')!;
  final Unit cup = Units.byId('cup')!;

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = FoodStore(db);
  });

  tearDown(() => db.close());

  ServingOption cupServing({String id = 'serving-cup'}) => ServingOption(
    id: id,
    label: '1 cup',
    amount: Quantity.of(1, cup),
    macros: const Macros(kcal: 100, proteinG: 8, carbG: 2, fatG: 7),
  );

  /// The label on the jar: 10 oz net, about 2 servings of 1 cup.
  PackageNutrition relation({String servingId = 'serving-cup'}) =>
      PackageNutrition.manual(
        servingsPerPackage: 2,
        servingOptionId: servingId,
        servingAmount: Quantity.of(1, cup),
        packageAmount: Quantity.of(10, ounce),
        isApproximate: true,
        source: PackageNutritionSource.photos,
      );

  Food cheddar({
    MassDisplayMode mode = MassDisplayMode.ounces,
    PackageNutrition? packageNutrition,
    Quantity? packSize,
  }) => Food(
    id: 'food-cheddar',
    householdId: household,
    name: 'Shredded cheddar',
    source: FoodSource.manual,
    servingOptions: <ServingOption>[cupServing()],
    packSize: packSize ?? Quantity.of(10, ounce),
    massDisplayMode: mode,
    packageNutrition: packageNutrition,
  );

  group('the local cache', () {
    test('a reviewed relationship survives a save and a read back', () async {
      await store.upsert(cheddar(packageNutrition: relation()), updatedAt: now);

      final Food back = (await store.byId('food-cheddar'))!;
      expect(back.massDisplayMode, MassDisplayMode.ounces);
      expect(back.packageNutrition, isNotNull);
      expect(back.packageNutrition!.isValid, isTrue);
      expect(back.packageNutrition!.servingsPerPackage, 2);
      // The printed qualifier is a fact about the label and is carried as one.
      expect(back.packageNutrition!.isApproximate, isTrue);
      expect(back.packageNutrition!.source, PackageNutritionSource.photos);
      expect(back.activePackageServing?.id, 'serving-cup');
      // 10 oz across two cups, computed rather than typed: a literal here
      // would be a second, drifting copy of the unit table.
      expect(
        back.effectiveGramsPerMillilitre,
        closeTo(
          Quantity.of(10, ounce).canonicalAmount /
              (2 * Quantity.of(1, cup).canonicalAmount),
          1e-9,
        ),
      );
    });

    test('a food nobody has set up reads as automatic, with none', () async {
      await store.upsert(
        const Food(
          id: 'food-plain',
          householdId: household,
          name: 'Plain',
          source: FoodSource.manual,
          servingOptions: <ServingOption>[],
        ),
        updatedAt: now,
      );

      final Food back = (await store.byId('food-plain'))!;
      expect(back.massDisplayMode, MassDisplayMode.automatic);
      expect(back.packageNutrition, isNull);
      expect(back.hasStalePackageNutrition, isFalse);
    });

    test('removing it explicitly clears the column', () async {
      await store.upsert(cheddar(packageNutrition: relation()), updatedAt: now);
      await store.upsert(cheddar(), updatedAt: now);

      final Food back = (await store.byId('food-cheddar'))!;
      expect(back.packageNutrition, isNull);
      // A separate field, and it must not have gone with it.
      expect(back.massDisplayMode, MassDisplayMode.ounces);
    });

    test('a version this build cannot read is kept verbatim', () async {
      const Map<String, dynamic> future = <String, dynamic>{
        'version': 99,
        'servings_per_package': 2,
        'something_new': <String, dynamic>{'nested': true},
      };
      await store.upsert(
        cheddar(packageNutrition: PackageNutrition.fromJson(future)),
        updatedAt: now,
      );

      final Food back = (await store.byId('food-cheddar'))!;
      expect(back.packageNutrition, isNotNull);
      // Nothing activates off a record nobody here understands, and nothing
      // asks the user to check it either -- there is nothing they could fix.
      expect(back.packageNutrition!.isValid, isFalse);
      expect(back.activePackageServing, isNull);
      expect(back.hasStalePackageNutrition, isFalse);
      expect(back.packageNutrition!.toJson(), future);
    });

    test('changing the package leaves the facts for review', () async {
      await store.upsert(cheddar(packageNutrition: relation()), updatedAt: now);

      final Food loaded = (await store.byId('food-cheddar'))!;
      await store.upsert(
        loaded.withPackSize(Quantity.of(16, ounce)),
        updatedAt: now,
      );

      final Food back = (await store.byId('food-cheddar'))!;
      expect(
        back.packageNutrition,
        isNotNull,
        reason: 'the reviewed facts are what a correction is made from',
      );
      expect(back.activePackageServing, isNull);
      expect(back.hasStalePackageNutrition, isTrue);
      expect(back.massDisplayMode, MassDisplayMode.ounces);
    });
  });

  group('the repository, which stamps the household', () {
    test('keeps both fields, and queues both for sync', () async {
      final FoodRepository repository = FoodRepository(
        database: db,
        store: store,
        queue: PendingWriteStore(db),
        householdId: household,
        clock: () => now,
      );

      await repository.save(cheddar(packageNutrition: relation()));

      final Food back = (await repository.byId('food-cheddar'))!;
      expect(back.massDisplayMode, MassDisplayMode.ounces);
      expect(back.activePackageServing?.id, 'serving-cup');

      final List<PendingWrite> queued = await PendingWriteStore(db).pending();
      final Map<String, Object?> payload = queued.single.payload;
      expect(payload['mass_display_mode'], 'ounces');
      final Map<String, Object?> record =
          payload['package_nutrition']! as Map<String, Object?>;
      expect(record['version'], 1);
      expect(record['servings_per_package'], 2);
      expect(record['serving_option_id'], 'serving-cup');
      expect(record['is_approximate'], true);
      expect(record['basis'], 'as_packaged');
    });
  });

  group('the sync payload', () {
    Map<String, Object?> payloadFor(Food food) =>
        FoodMapper.toJson(food, updatedAt: now);

    test('states both keys, with an explicit null for no relation', () {
      final Map<String, Object?> json = payloadFor(
        cheddar(mode: MassDisplayMode.automatic),
      );

      expect(json['mass_display_mode'], 'automatic');
      expect(
        json.containsKey('package_nutrition'),
        isTrue,
        reason: 'silence and removal are different answers to the server',
      );
      expect(json['package_nutrition'], isNull);
    });

    test('and decodes back to the same relation', () {
      final Map<String, Object?> json = payloadFor(
        cheddar(packageNutrition: relation()),
      );

      expect(FoodMapper.massDisplayModeFrom(json), MassDisplayMode.ounces);

      final PackageNutrition? back = FoodMapper.packageNutritionFrom(json);
      expect(back, isNotNull);
      expect(back!.isValid, isTrue);
      expect(back.servingsPerPackage, 2);
      expect(back.servingOptionId, 'serving-cup');
      expect(back.isApproximate, isTrue);
      expect(back.source, PackageNutritionSource.photos);
      // The authored unit, not just the canonical number: a 10 oz package is
      // labelled in ounces however it is stored.
      expect(back.packageAmount!.preferredUnit?.id, 'oz');
      expect(back.servingAmount!.preferredUnit?.id, 'cup');
    });

    test('an older client says nothing, and changes nothing', () {
      final Map<String, Object?> json =
          payloadFor(cheddar(packageNutrition: relation()))
            ..remove('mass_display_mode')
            ..remove('package_nutrition');
      final PackageNutrition stored = relation();

      expect(
        FoodMapper.massDisplayModeFrom(json, fallback: MassDisplayMode.weight),
        MassDisplayMode.weight,
      );
      expect(
        FoodMapper.packageNutritionFrom(json, fallback: stored),
        same(stored),
      );
    });

    test('but an explicit null is a removal', () {
      final Map<String, Object?> json = <String, Object?>{
        ...payloadFor(cheddar()),
        'package_nutrition': null,
      };

      expect(
        FoodMapper.packageNutritionFrom(json, fallback: relation()),
        isNull,
      );
    });

    test('an unreadable record does not stop a food loading', () {
      expect(FoodMapper.decodePackageNutrition('not json at all'), isNull);
      expect(FoodMapper.decodePackageNutrition(''), isNull);
      expect(FoodMapper.decodePackageNutrition(null), isNull);

      final PackageNutrition? future = FoodMapper.decodePackageNutrition(
        jsonEncode(<String, dynamic>{'version': 7, 'kept': 'yes'}),
      );
      expect(future, isNotNull);
      expect(future!.isValid, isFalse);
      expect(future.toJson()['kept'], 'yes');
    });

    test('a malformed record is kept locally but never pushed', () async {
      final PackageNutrition malformed = PackageNutrition.fromJson(
        <String, dynamic>{...relation().toJson(), 'source': 'guess'},
      );
      expect(malformed.isValid, isFalse);

      await store.upsert(cheddar(packageNutrition: malformed), updatedAt: now);

      final Food back = (await store.byId('food-cheddar'))!;
      expect(
        back.packageNutrition,
        isNotNull,
        reason: 'the original facts are what a correction is made from',
      );
      expect(back.packageNutrition!.isValid, isFalse);
      expect(back.packageNutrition!.toJson()['source'], 'guess');

      final Map<String, Object?> json = payloadFor(back);
      expect(
        json.containsKey('package_nutrition'),
        isFalse,
        reason: 'the server would refuse it, and take the whole food with it',
      );
      // Silence about the relation, and the rest of the food still goes.
      expect(json['mass_display_mode'], 'ounces');
      expect(json['name'], 'Shredded cheddar');
      expect((json['serving_options']! as List<Object?>), hasLength(1));
    });

    test('an oversized record is omitted; a removal is still stated', () {
      final PackageNutrition huge = PackageNutrition.fromJson(<String, dynamic>{
        ...relation().toJson(),
        'padding': 'x' * 5000,
      });
      expect(huge.isSendable, isFalse);
      expect(
        payloadFor(cheddar(packageNutrition: huge))
            .containsKey('package_nutrition'),
        isFalse,
      );

      final Map<String, Object?> removed = payloadFor(cheddar());
      expect(removed.containsKey('package_nutrition'), isTrue);
      expect(removed['package_nutrition'], isNull);
    });

    test('a stale but well-formed record is still sent', () {
      final Food moved = cheddar(
        packageNutrition: relation(),
        packSize: Quantity.of(16, ounce),
      );
      expect(moved.hasStalePackageNutrition, isTrue);
      expect(
        payloadFor(moved)['package_nutrition'],
        isNotNull,
        reason: 'it is a true record of what somebody reviewed',
      );
    });
  });

  group('merging two foods', () {
    Food survivorWith({PackageNutrition? packageNutrition, Quantity? pack}) =>
        Food(
          id: 'food-survivor',
          householdId: household,
          name: 'Shredded cheddar',
          source: FoodSource.manual,
          servingOptions: <ServingOption>[
            ServingOption(
              id: 'survivor-100g',
              label: '100 g',
              amount: Quantity.of(100, Units.gram),
              macros: const Macros(kcal: 400),
            ),
          ],
          packSize: pack ?? Quantity.of(10, ounce),
          massDisplayMode: MassDisplayMode.weight,
          packageNutrition: packageNutrition,
        );

    Food retiringWith() => Food(
      id: 'food-retiring',
      householdId: household,
      name: 'shredded cheddar',
      source: FoodSource.manual,
      servingOptions: <ServingOption>[cupServing()],
      packSize: Quantity.of(10, ounce),
      packageNutrition: relation(),
    );

    MergePlan planFor(Food survivor, Food retiring) => MergePlan.build(
      survivor: survivor,
      retiring: retiring,
      recipeLines: 0,
      stranded: const <StrandedLine>[],
      plannedEntries: const <({String id, double servings})>[],
      shoppingLines: 0,
      rememberedMatches: 0,
      loggedMeals: 0,
    );

    test('keeps the survivor own display preference', () {
      expect(
        planFor(survivorWith(), retiringWith()).merged.massDisplayMode,
        MassDisplayMode.weight,
      );
    });

    test('adopts the retiring relation, remapped to the copied serving', () {
      final Food merged = planFor(survivorWith(), retiringWith()).merged;

      expect(merged.packageNutrition, isNotNull);
      expect(
        merged.packageNutrition!.servingOptionId,
        'food-survivor:serving-cup',
        reason: 'the adopted serving row carries a fresh id',
      );
      // Remapped, and therefore live rather than instantly stale.
      expect(merged.activePackageServing, isNotNull);
      expect(merged.hasStalePackageNutrition, isFalse);
      expect(merged.packageNutrition!.isApproximate, isTrue);
      expect(merged.packageNutrition!.source, PackageNutritionSource.photos);
    });

    test('but never over one the survivor already has', () {
      final PackageNutrition own = PackageNutrition.manual(
        servingsPerPackage: 4,
        servingOptionId: 'survivor-100g',
        servingAmount: Quantity.of(1, cup),
        packageAmount: Quantity.of(10, ounce),
      );

      final Food merged = planFor(
        survivorWith(packageNutrition: own),
        retiringWith(),
      ).merged;

      expect(merged.packageNutrition!.servingsPerPackage, 4);
      expect(merged.packageNutrition!.servingOptionId, 'survivor-100g');
    });

    test('and not at all when it describes a different package', () {
      final Food merged = planFor(
        survivorWith(pack: Quantity.of(16, ounce)),
        retiringWith(),
      ).merged;

      expect(
        merged.packageNutrition,
        isNull,
        reason: 'a relation pinned to the wrong package is a wrong weight',
      );
    });
  });
}
