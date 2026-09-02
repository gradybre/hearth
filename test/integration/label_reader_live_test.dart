@Tags(<String>['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/edge_function_label_reader.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/live_config.dart';

/// Reading a Nutrition Facts panel, against the deployed function (spec §9.4).
///
/// This test exists because its absence hid a real bug. The packet units —
/// scoop, bar, patty — were added to what the model may answer and not to what
/// the server accepts, so a tub reading "1 Rounded Scoop (31g)" came back as
/// a scoop and was thrown away before the app saw it. Every Dart test passed,
/// because they all build a `LabelReading` by hand and never cross the seam
/// where the two lists disagreed.
///
/// Run deliberately, because it costs money:
///
///   HEARTH_LIVE=1 flutter test --tags live test/integration
void main() {
  final ({String url, String key})? config = liveConfig();
  final String? skip = liveSkipReason();

  late EdgeFunctionLabelReader reader;

  setUpAll(() {
    HttpOverrides.global = null;
    if (config == null) return;
    reader = EdgeFunctionLabelReader(SupabaseClient(config.url, config.key));
  });

  test(
    'a scoop survives the round trip, and brings its weight',
    () async {
      final Uint8List bytes = await File('test/fixtures/scoop_label.png')
          .readAsBytes();

      final LabelReading reading = await reader.read(<AiImage>[
        AiImage(bytes: bytes, mediaType: 'image/png'),
      ]);

      final LabelServing scoop = reading.servings.firstWhere(
        (LabelServing s) => s.unitId == 'scoop',
        orElse: () => throw StateError(
          'the scoop was dropped: ${reading.servings.map((LabelServing s) => s.unitId)}',
        ),
      );
      final LabelServing grams = reading.servings.firstWhere(
        (LabelServing s) => s.unitId == 'g',
      );

      expect(scoop.amount, 1);
      expect(grams.amount, 31);

      // The pair is the point: together they are the only statement of what a
      // scoop of this weighs, which is what lets a recipe measured in scoops
      // resolve against a food sold by weight.
      expect(scoop.kcal, grams.kcal);
      expect(scoop.proteinG, grams.proteinG);

      // Transcribed, never computed — the numbers printed on the panel.
      expect(scoop.kcal, 120);
      expect(scoop.proteinG, 24);
      expect(scoop.carbG, 3);
      expect(scoop.fatG, 1);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
