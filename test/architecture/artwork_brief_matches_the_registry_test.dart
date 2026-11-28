import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/widgets/recipe_art.dart';
import 'package:hearth/domain/recipes/recipe_artwork.dart';

import '../../tool/write_artwork_brief.dart';

/// The brief and the registry say the same thing, or the suite says so.
///
/// They are two halves of one decision: the registry is what the app
/// matches a recipe against, and the brief is what somebody draws from. A
/// brief that has drifted commissions pictures nothing will ever ask for and
/// leaves ones the app wants undrawn — and neither failure shows up until
/// the art arrives and half of it is useless.
void main() {
  final File brief = File('docs/design/ui-redesign-2026-11/ARTWORK_BRIEF.md');

  test('the brief lists exactly what the registry asks for', () {
    final String onDisk = brief.readAsStringSync();
    expect(
      artworkBriefWith(onDisk),
      onDisk,
      reason:
          'the brief is out of date — run '
          '`dart run tool/write_artwork_brief.dart`',
    );
  });

  test('and every drawing that has shipped is one the registry knows', () {
    // The other direction: a file in `assets/art` whose id nothing matches
    // is a drawing that can never appear, and the set that names it is the
    // only place that would say so.
    final Set<String> known = <String>{
      for (final RecipeArtwork art in kRecipeArtwork) art.id,
    };
    for (final String id in kArtworkShipped) {
      expect(
        known,
        contains(id),
        reason: '$id has shipped but no recipe can ask for it',
      );
    }
  });
}
