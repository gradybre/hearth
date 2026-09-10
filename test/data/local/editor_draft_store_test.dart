import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/editor_draft_store.dart';
import 'package:hearth/data/local/hearth_database.dart';

/// Work in progress that survives an interruption (review N01).
void main() {
  late HearthDatabase db;
  late EditorDraftStore mine;
  final DateTime at = DateTime.utc(2026, 9, 10, 12);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    mine = EditorDraftStore(db, userId: 'user-1');
  });

  tearDown(() => db.close());

  EditorDraft draft({
    String? targetId,
    DateTime? sourceUpdatedAt,
    String title = 'Short ribs',
  }) => EditorDraft(
    kind: 'recipe',
    targetId: targetId,
    sourceUpdatedAt: sourceUpdatedAt,
    payload: <String, Object?>{'title': title},
  );

  test('a saved draft comes back', () async {
    await mine.save(draft(), at: at);

    final EditorDraft? found = await mine.find(kind: 'recipe');
    expect(found?.payload['title'], 'Short ribs');
  });

  test('and saving again replaces it rather than stacking', () async {
    // One draft per target. Being offered a choice between two versions of
    // the same half-written recipe is not a feature.
    await mine.save(draft(), at: at);
    await mine.save(draft(title: 'Braised short ribs'), at: at);

    expect(
      (await mine.find(kind: 'recipe'))?.payload['title'],
      'Braised short ribs',
    );
    expect(await db.select(db.editorDrafts).get(), hasLength(1));
  });

  test('a new recipe and an existing one are different drafts', () async {
    // Otherwise starting a new recipe offers you the last one you were
    // editing, which is worse than offering nothing.
    await mine.save(draft(title: 'Brand new'), at: at);
    await mine.save(
      draft(targetId: 'r1', title: 'The edited one'),
      at: at,
    );

    expect((await mine.find(kind: 'recipe'))?.payload['title'], 'Brand new');
    expect(
      (await mine.find(kind: 'recipe', targetId: 'r1'))?.payload['title'],
      'The edited one',
    );
  });

  test('and a food draft never answers for a recipe', () async {
    await mine.save(
      const EditorDraft(
        kind: 'food',
        payload: <String, Object?>{'name': 'Oats'},
      ),
      at: at,
    );

    expect(await mine.find(kind: 'recipe'), isNull);
    expect((await mine.find(kind: 'food'))?.payload['name'], 'Oats');
  });

  test("the other account's draft is not offered to you", () async {
    // The one situation two people share a device: a sign-out and a sign-in.
    // Being handed a stranger's half-written recipe is baffling, and it is a
    // small privacy failure besides.
    await mine.save(draft(title: 'Mine'), at: at);

    final EditorDraftStore theirs = EditorDraftStore(db, userId: 'user-2');
    expect(await theirs.find(kind: 'recipe'), isNull);

    // And the one they write does not take yours away.
    await theirs.save(draft(title: 'Theirs'), at: at);
    expect((await mine.find(kind: 'recipe'))?.payload['title'], 'Mine');
  });

  test('what the record looked like when the draft started is kept', () async {
    // The whole of the stale-draft check: restoring over a recipe the other
    // phone has edited since must be a decision, not a surprise.
    final DateTime source = DateTime.utc(2026, 9, 9);
    await mine.save(
      draft(targetId: 'r1', sourceUpdatedAt: source),
      at: at,
    );

    expect(
      (await mine.find(kind: 'recipe', targetId: 'r1'))?.sourceUpdatedAt,
      source,
    );
  });

  test('clearing forgets one draft and leaves the rest', () async {
    await mine.save(draft(title: 'New one'), at: at);
    await mine.save(
      draft(targetId: 'r1', title: 'Edited one'),
      at: at,
    );

    await mine.clear(kind: 'recipe', targetId: 'r1');

    expect(await mine.find(kind: 'recipe', targetId: 'r1'), isNull);
    expect((await mine.find(kind: 'recipe'))?.payload['title'], 'New one');
  });

  test(
    'a payload that will not parse reads as no draft, not as a crash',
    () async {
      // Unrecoverable either way; refusing to open the editor over it would
      // turn a lost draft into a screen nobody can reach.
      await db
          .into(db.editorDrafts)
          .insert(
            EditorDraftRow(
              id: EditorDraftStore.keyFor(kind: 'recipe'),
              userId: 'user-1',
              kind: 'recipe',
              payload: 'not json at all',
              updatedAt: at,
            ),
          );

      expect(await mine.find(kind: 'recipe'), isNull);
    },
  );
}
