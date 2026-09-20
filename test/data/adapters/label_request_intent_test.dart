import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// The request-intent gate (spec R11).
///
/// Which photos were sent is the authority on whether a reply may state
/// nutrition. The provenance a reading carries is the model's account of its
/// own work: absent from an older server, mistaken at times, and — from
/// anything that is not really this app's server — simply invented.
LabelReading reading({
  List<LabelServing> servings = const <LabelServing>[
    LabelServing(amount: 100, unitId: 'g', kcal: 40),
  ],
  Map<String, String> fieldSources = const <String, String>{},
  bool withPackageFact = true,
}) => LabelReading(
  servings: servings,
  fieldSources: fieldSources,
  // A real package-only read has something of the package in it, and these
  // cases are about the nutrition being dropped. A reply holding nothing
  // but nutrition is its own case, below.
  packageSize: withPackageFact ? Quantity.of(10, Units.ounce) : null,
);

void main() {
  group('what a set of roles means', () {
    test('package alone is a front-of-package read', () {
      final LabelRequestIntent intent = LabelRequestIntent.ofRoles(<String?>[
        'package',
      ]);
      expect(intent.isPackageOnly, isTrue);
      expect(intent.nutrition, isFalse);
    });

    test('a panel photo permits nutrition, alone or paired', () {
      expect(
        LabelRequestIntent.ofRoles(<String?>['nutrition']).isPackageOnly,
        isFalse,
      );
      expect(
        LabelRequestIntent.ofRoles(<String?>['nutrition', 'package'])
            .isPackageOnly,
        isFalse,
      );
    });

    test('no roles at all is the permissive answer', () {
      // A read that predates roles, or one made by something that does not
      // set them. It read panels before this gate existed and must keep
      // doing so.
      expect(
        LabelRequestIntent.ofRoles(const <String?>[]).isPackageOnly,
        isFalse,
      );
      expect(
        LabelRequestIntent.ofRoles(<String?>[null, null]).isPackageOnly,
        isFalse,
      );
    });

    test('an unrecognised role fails open rather than into a false gate', () {
      // Throwing away a panel somebody photographed is worse than letting a
      // request nobody can classify through; the server gates that one too.
      expect(
        LabelRequestIntent.ofRoles(<String?>['sidebar']).isPackageOnly,
        isFalse,
      );
      expect(
        LabelRequestIntent.ofRoles(<String?>['package', 'thumbnail'])
            .isPackageOnly,
        isFalse,
      );
    });
  });

  group('gating a reading to its request', () {
    test('nutrition from a panel-less read is dropped, and said so', () {
      final LabelReading gated = gateLabelReadingToRequest(
        reading(),
        LabelRequestIntent.ofRoles(<String?>['package']),
      );

      expect(gated.servings, isEmpty);
      expect(gated.fieldSources['servings'], 'package');
      expect(
        gated.uncertain.map((AiUncertainty u) => u.field),
        contains('servings'),
      );
    });

    test('forged provenance does not get it past the gate', () {
      // The reply claims a panel supplied these macros. No panel was sent.
      final LabelReading gated = gateLabelReadingToRequest(
        reading(fieldSources: const <String, String>{'servings': 'nutrition'}),
        LabelRequestIntent.ofRoles(<String?>['package']),
      );

      expect(gated.servings, isEmpty);
    });

    test('the package facts it did read all survive', () {
      final LabelReading gated = gateLabelReadingToRequest(
        LabelReading(
          servings: const <LabelServing>[
            LabelServing(amount: 100, unitId: 'g', kcal: 40),
          ],
          name: 'Chopped Onions',
          brand: 'Great Value',
          packageBasis: 'unknown',
          packageSize: Quantity.of(10, Units.ounce),
        ),
        LabelRequestIntent.ofRoles(<String?>['package']),
      );

      expect(gated.name, 'Chopped Onions');
      expect(gated.brand, 'Great Value');
      expect(gated.packageBasis, 'unknown');
      expect(gated.packageSize, isNotNull);
    });

    test('a reply holding nothing but nutrition says so', () {
      // Once the nutrition nobody asked for is gone there is nothing left to
      // merge. A silent no-op would close the sheet on an unchanged draft.
      expect(
        () => gateLabelReadingToRequest(
          reading(withPackageFact: false),
          LabelRequestIntent.ofRoles(<String?>['package']),
        ),
        throwsA(
          isA<RecipeAiException>().having(
            (RecipeAiException e) => e.message,
            'message',
            contains('package size'),
          ),
        ),
      );
    });

    test('a read that included a panel is untouched', () {
      final LabelReading original = reading();
      expect(
        gateLabelReadingToRequest(
          original,
          LabelRequestIntent.ofRoles(<String?>['nutrition', 'package']),
        ),
        same(original),
      );
    });

    test('a legacy roleless read keeps its nutrition', () {
      final LabelReading original = reading();
      expect(
        gateLabelReadingToRequest(
          original,
          LabelRequestIntent.ofRoles(const <String?>[]),
        ),
        same(original),
      );
    });

    test('gating twice removes nothing the first pass left', () {
      const LabelRequestIntent front = LabelRequestIntent(
        nutrition: false,
        package: true,
      );
      final LabelReading once = gateLabelReadingToRequest(reading(), front);
      final LabelReading twice = gateLabelReadingToRequest(once, front);

      expect(twice.servings, isEmpty);
      expect(twice.uncertain, hasLength(once.uncertain.length));
    });
  });
}
