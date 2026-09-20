// Native UI exercise only: in-memory food data and a deterministic reader.
// No server connection and no household storage are opened by this entrypoint.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/adapters/walmart_link_reader.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
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
        labelReaderProvider.overrideWithValue(_Reader()),
      ],
      child: MaterialApp(theme: HearthTheme.light(), home: const _Home()),
    ),
  );
}

class _Reader implements LabelReader, WalmartLinkReader {
  WalmartLinkReading get link => WalmartLinkReading.fromJson({
    'status': 'found',
    'url': 'https://www.walmart.com/ip/10450479',
    'source': 'screenshot',
  });
  @override
  Future<WalmartLinkReading> readWalmartLink(List<AiImage> images) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return link;
  }

  @override
  Future<LabelReading> read(List<AiImage> images) async => LabelReading(
    servings: const [LabelServing(amount: 30, unitId: 'g', kcal: 90)],
    walmartLink: link,
  );
  @override
  Future<PackReading> readPack(List<AiImage> images) async =>
      const PackReading();
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Walmart screenshot UI fixture')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Synthetic data. The native photo picker is real; extraction is a fixed test response.',
        ),
        for (final existing in [false, true])
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FoodEditorScreen(
                  initialDraft: FoodDraft(
                    name: 'Synthetic corn',
                    walmartItemId: existing ? '98765432' : '',
                    servings: const [
                      ServingDraft(
                        id: 'synthetic-serving',
                        amount: '30',
                        kcal: '90',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: Text(existing ? 'Existing link' : 'Empty link'),
          ),
      ],
    ),
  );
}
