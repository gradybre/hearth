import 'dart:io';

import 'package:hearth/domain/recipes/recipe_artwork.dart';

/// Writes the subject list in the artwork brief from the registry.
///
/// The registry is the source of truth: it is what the app matches against,
/// so a brief that disagrees with it commissions a drawing nothing will ever
/// ask for, or leaves one the app wants undrawn. Generating the list means
/// the two cannot drift, and a test re-runs this in memory to prove it.
///
///     dart run tool/write_artwork_brief.dart
void main() {
  final File file = File('docs/design/ui-redesign-2026-11/ARTWORK_BRIEF.md');
  final String updated = artworkBriefWith(file.readAsStringSync());
  file.writeAsStringSync(updated);
  stdout.writeln('Wrote ${kRecipeArtwork.length} subjects to ${file.path}');
}

const String beginMarker = '<!-- BEGIN GENERATED SUBJECTS -->';
const String endMarker = '<!-- END GENERATED SUBJECTS -->';

/// [brief] with its subject list replaced by the registry's.
String artworkBriefWith(String brief) {
  final int begin = brief.indexOf(beginMarker);
  final int end = brief.indexOf(endMarker);
  if (begin < 0 || end < 0 || end < begin) {
    throw StateError('the brief has lost its generated-subject markers');
  }
  final StringBuffer out = StringBuffer()
    ..writeln(beginMarker)
    ..writeln()
    ..writeln('${kRecipeArtwork.length} drawings.')
    ..writeln();
  for (final RecipeArtwork art in kRecipeArtwork) {
    out.writeln('- `${art.id}` — ${art.keywords.join(', ')}');
  }
  out.write(endMarker);
  return brief.replaceRange(begin, end + endMarker.length, out.toString());
}
