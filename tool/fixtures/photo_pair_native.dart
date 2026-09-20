// Native UI exercise only: in-memory food data and a deterministic reader.
// No server connection and no household storage are opened by this entrypoint.
//
// Scope: the label-photo merge as it lands in the food editor. Saving is not
// wired to a router here, so treat this fixture as a review-screen check --
// save-and-reopen behaviour is covered by its own regression work.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/features/foods/food_draft.dart';
import 'package:hearth/features/foods/food_editor_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = HearthDatabase.forTesting(NativeDatabase.memory());
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        supabaseReadyProvider.overrideWithValue(false),
        // Only the model call is faked. The photo picker stays at its real
        // provider default, so the native picker is what is exercised.
        labelReaderProvider.overrideWithValue(_Reader()),
      ],
      child: MaterialApp(theme: HearthTheme.light(), home: const _Home()),
    ),
  );
}

/// A fixed response that branches on the roles the caller stated.
///
/// Roles are read off [AiImage.role] rather than off the order the images
/// arrive in: the point of the fixture is that the *request's* stated intent
/// is what the controller trusts, so the fake has to answer the same way.
class _Reader implements LabelReader {
  static const String _link = 'https://www.walmart.com/ip/694935141';

  static WalmartLinkReading get _reading => WalmartLinkReading.fromJson({
    'status': 'found',
    'url': _link,
    'source': 'screenshot',
  });

  /// One portion, stated twice -- a volume and a weight for the same food.
  /// The pair is the whole point: it is the only statement of density a
  /// recipe line measured in cups can get from a food sold by weight.
  static const List<LabelServing> _pair = <LabelServing>[
    LabelServing(
      amount: 2 / 3,
      unitId: 'cup',
      kcal: 35,
      proteinG: 1,
      carbG: 8,
      fatG: 0,
      fiberG: 1,
      sodiumMg: 0,
      cholesterolMg: 0,
    ),
    LabelServing(
      amount: 85,
      unitId: 'g',
      kcal: 35,
      proteinG: 1,
      carbG: 8,
      fatG: 0,
      fiberG: 1,
      sodiumMg: 0,
      cholesterolMg: 0,
    ),
  ];

  @override
  Future<LabelReading> read(List<AiImage> images) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final bool hasNutrition = images.any((i) => i.role == 'nutrition');

    if (hasNutrition) {
      return LabelReading(
        name: 'Synthetic onions',
        servings: _pair,
        packageSize: Quantity.of(10, Units.ounce),
        servingsPerContainer: 3.5,
        servingsApproximate: true,
        packageBasis: 'as_packaged',
        fieldSources: const <String, String>{
          'servings': 'nutrition',
          'package_amount': 'package',
          'servings_per_container': 'nutrition',
        },
        walmartLink: _reading,
      );
    }

    // Package photo alone. This is the adversarial shape an older deployment
    // could still return: a serving transcribed from nothing, labelled as
    // though a nutrition photo had supplied it. The caller asked for a
    // package read, so the request's intent is what should win -- if this
    // 100 g / 40 kcal row reaches the editor, or its provenance is believed,
    // the override is not doing its job.
    return LabelReading(
      name: 'Synthetic onions',
      servings: const <LabelServing>[
        LabelServing(amount: 100, unitId: 'g', kcal: 40),
      ],
      packageSize: Quantity.of(10, Units.ounce),
      packageBasis: 'unknown',
      fieldSources: const <String, String>{
        'servings': 'nutrition',
        'package_amount': 'package',
      },
      walmartLink: _reading,
    );
  }

  @override
  Future<PackReading> readPack(List<AiImage> images) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return PackReading(
      name: 'Synthetic onions',
      size: Quantity.of(10, Units.ounce),
    );
  }
}

/// A food the household already has: both portions, real macros, stable ids,
/// and no package amount yet -- so a photo has somewhere to land without
/// overwriting anything a person entered.
///
/// Deliberately carries no `existingId`: nothing is seeded into the database
/// here, and an id pointing at a row that does not exist would be a worse lie
/// than an unsaved draft.
FoodDraft _existingDraft() => const FoodDraft(
  name: 'Synthetic onions',
  servings: <ServingDraft>[
    ServingDraft(
      id: 'synthetic-onions-cup',
      amount: '2/3',
      unitId: 'cup',
      kcal: '35',
      protein: '1',
      carbs: '8',
      fat: '0',
      fiber: '1',
      sodium: '0',
      cholesterol: '0',
    ),
    ServingDraft(
      id: 'synthetic-onions-gram',
      amount: '85',
      unitId: 'g',
      kcal: '35',
      protein: '1',
      carbs: '8',
      fat: '0',
      fiber: '1',
      sodium: '0',
      cholesterol: '0',
    ),
  ],
);

/// A food nobody has yet. The name is left empty on purpose -- the reader
/// supplies "Synthetic onions", and a blank field is how that gets seen.
FoodDraft _blankDraft() => FoodDraft.blank();

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photo pair UI fixture')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Text(
          'Synthetic data. The native photo picker is real; label extraction '
          'is a fixed test response and no model is called. Nothing is saved '
          'to a household database.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Pick a nutrition photo and a package photo: expect 2/3 cup and 85 '
          'g at 35 kcal each, a 10 oz package, about 3.5 servings, and the '
          'Walmart link 694935141.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Pick a package photo only: the fake answers with a bogus 100 g / '
          '40 kcal serving that claims a nutrition photo supplied it. The '
          'request said package, so that row and its provenance should not '
          'be believed.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Review only -- Save is not wired to a router in this fixture.',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _open(context, _blankDraft()),
          child: const Text('New blank onions'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _open(context, _existingDraft()),
          child: const Text('Existing onions'),
        ),
      ],
    ),
  );

  void _open(BuildContext context, FoodDraft draft) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FoodEditorScreen(initialDraft: draft),
      ),
    );
  }
}
