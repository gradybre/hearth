import 'package:flutter/foundation.dart';

import '../plan/logging_intent.dart';
import 'recipe_draft.dart';
import 'recipe_import_controller.dart';

/// What the recipe editor was opened with.
///
/// One object rather than three `extra` shapes the route has to tell apart by
/// type. The editor is reached from an import, a duplicate, the restaurant
/// builder and the plain Add control, and the first three all want to hand it
/// something — a draft, a read recipe, or the meal the build belongs to
/// (U04). Sniffing `extra`'s runtime type worked while there were two; it
/// does not survive a third that needs to travel *alongside* one of the
/// others.
@immutable
class RecipeEditorArgs {
  const RecipeEditorArgs({this.draft, this.imported, this.intent});

  /// A copy already made, so it is reviewed and renamed before it is written.
  final RecipeDraft? draft;

  /// A recipe already read, so it is reviewed before anything is written
  /// (CLAUDE.md rule 4).
  final RecipeImportResult? imported;

  /// The meal this build belongs to, if it began in one.
  final LoggingIntent? intent;
}
