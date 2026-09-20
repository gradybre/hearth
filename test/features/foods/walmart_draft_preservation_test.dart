import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
import 'package:hearth/features/foods/food_draft.dart';
import 'package:test/test.dart';

import '../../support/package_fixtures.dart';

WalmartLinkReading link(String id) => WalmartLinkReading.fromJson({
  'status': 'found',
  'url': 'https://www.walmart.com/ip/$id',
  'source': 'screenshot',
});

void main() {
  test('link-only label changes exactly one serialized draft field', () {
    final before = FoodDraft.fromFood(packageCorn()).copyWith(
      packageReviewNotes: ['Already reviewed against the package'],
      packageFieldSources: {'package_amount': 'package'},
      packageBasisAcknowledged: true,
    );
    final after = before.withLabel(
      LabelReading(
        servings: const [],
        name: 'Unrelated extracted name',
        brand: 'Unrelated brand',
        walmartLink: link('10450479'),
      ),
    );
    expect(after.toJson(), {
      ...before.toJson(),
      'walmart_item_id': 'https://www.walmart.com/ip/10450479',
    });
    expect(after.packageNutritionReviewed, isTrue);
    expect(FoodDraft.fromJson(after.toJson()).toJson(), after.toJson());
  });

  test('existing values survive until replacement is explicit', () {
    final before = FoodDraft.fromFood(packageCorn())
        .copyWith(walmartItemId: '98765432');
    expect(identical(before.withWalmartLink(link('10450479')), before), isTrue);
    expect(before.withWalmartLink(link('10450479'), replace: true).toJson(), {
      ...before.toJson(),
      'walmart_item_id': 'https://www.walmart.com/ip/10450479',
    });
    expect(
      identical(
        before.withWalmartLink(link('98765432'), replace: true),
        before,
      ),
      isTrue,
    );
  });

  test(
    'combined nutrition fills blank link but preserves an existing link',
    () {
      final reading = LabelReading(
        servings: const [LabelServing(amount: 30, unitId: 'g', kcal: 90)],
        walmartLink: link('10450479'),
      );
      final before = FoodDraft.blank();
      final after = before.withLabel(reading);
      expect(after.walmartItemId, 'https://www.walmart.com/ip/10450479');
      expect(after.servings.single.kcal, '90');
      final existing = before.copyWith(walmartItemId: '98765432');
      expect(existing.withLabel(reading).walmartItemId, '98765432');
    },
  );

  test('unsafe or missing results never change a draft', () {
    final before = FoodDraft.fromFood(packageCorn());
    for (final status in ['not_found', 'ambiguous', 'unreadable']) {
      final reading = WalmartLinkReading.fromJson({'status': status});
      expect(identical(before.withWalmartLink(reading), before), isTrue);
    }
  });
}
