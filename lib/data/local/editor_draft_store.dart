import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import 'hearth_database.dart';

/// What was in an editor when it was interrupted (spec §5.2, review N01).
@immutable
class EditorDraft {
  const EditorDraft({
    required this.kind,
    required this.payload,
    this.targetId,
    this.sourceUpdatedAt,
  });

  /// `recipe` or `food`.
  final String kind;

  /// The record being edited, or null for one that does not exist yet.
  final String? targetId;

  /// What the record's `updatedAt` was when the draft started.
  ///
  /// The whole of the stale-draft check: if the record has moved on since,
  /// the other phone edited it while this draft sat here, and restoring
  /// without saying so would overwrite their work with a copy of a version
  /// that is no longer current.
  final DateTime? sourceUpdatedAt;

  final Map<String, Object?> payload;
}

/// Keeps a draft alive across a crash, a restart, or an app the system killed
/// to reclaim memory (review N01).
///
/// **Local, and never synced.** A draft is the state *before* the review that
/// rule 4 requires, so pushing one would put unreviewed work in front of the
/// other person as though a decision had been made. It is also simply not
/// true of the household — it is true of this phone, a minute ago.
///
/// One draft per editing target. A second draft of the same recipe is not a
/// choice anybody wants to be offered.
class EditorDraftStore {
  EditorDraftStore(this._db, {required String userId}) : _userId = userId;

  final HearthDatabase _db;

  /// Whose drafts these are.
  ///
  /// Two people share a device in exactly one situation — a sign-out and a
  /// sign-in — and being offered a stranger's half-written recipe would be
  /// both baffling and a small privacy failure.
  final String _userId;

  /// The key for an editing target. `recipe:new` and `recipe:<id>` are
  /// different drafts, which is what stops a new recipe inheriting the draft
  /// of the last one edited.
  static String keyFor({required String kind, String? targetId}) =>
      '$kind:${targetId ?? 'new'}';

  Future<void> save(EditorDraft draft, {required DateTime at}) async {
    await _db
        .into(_db.editorDrafts)
        .insertOnConflictUpdate(
          EditorDraftRow(
            id: keyFor(kind: draft.kind, targetId: draft.targetId),
            userId: _userId,
            kind: draft.kind,
            targetId: draft.targetId,
            sourceUpdatedAt: draft.sourceUpdatedAt,
            payload: jsonEncode(draft.payload),
            updatedAt: at,
          ),
        );
  }

  /// The draft for this target, or null when there is none to offer.
  ///
  /// A row whose payload will not parse is treated as no draft rather than as
  /// an error: it is unrecoverable either way, and refusing to open the editor
  /// over it would turn a lost draft into a screen nobody can reach.
  Future<EditorDraft?> find({required String kind, String? targetId}) async {
    final EditorDraftRow? row =
        await (_db.select(_db.editorDrafts)..where(
              ($EditorDraftsTable d) =>
                  d.id.equals(keyFor(kind: kind, targetId: targetId)) &
                  d.userId.equals(_userId),
            ))
            .getSingleOrNull();
    if (row == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(row.payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;

    return EditorDraft(
      kind: row.kind,
      targetId: row.targetId,
      // UTC on the way out, because the comparison this exists for is between
      // instants and Dart's `DateTime` equality is not: the same moment in
      // local time and in UTC are two unequal objects, so a draft would read
      // as stale against the very record it was taken from.
      sourceUpdatedAt: row.sourceUpdatedAt?.toUtc(),
      payload: decoded,
    );
  }

  /// Forgets the draft for a target.
  ///
  /// Called after a save has committed *locally* — not before, and not on the
  /// strength of a queued write. A save that fails must leave the draft where
  /// it is, because that is the moment the draft is worth most.
  Future<void> clear({required String kind, String? targetId}) async {
    await (_db.delete(_db.editorDrafts)..where(
          ($EditorDraftsTable d) =>
              d.id.equals(keyFor(kind: kind, targetId: targetId)) &
              d.userId.equals(_userId),
        ))
        .go();
  }
}
