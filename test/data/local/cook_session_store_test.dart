import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/cook_session_store.dart';
import 'package:hearth/data/local/hearth_database.dart';

void main() {
  late HearthDatabase db;
  late CookSessionStore store;

  final DateTime t0 = DateTime.utc(2026, 8, 28, 18);

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = CookSessionStore(db);
  });

  tearDown(() => db.close());

  Future<void> save({
    String recipeId = 'ribs',
    int currentStep = 2,
    Set<String> checked = const <String>{'step-1', 'step-2'},
    DateTime? at,
  }) => store.save(
    recipeId: recipeId,
    currentStep: currentStep,
    checkedStepIds: checked,
    now: at ?? t0,
  );

  group('a cook keeps its place', () {
    test('the step you were on and what you ticked both come back', () async {
      await save();

      final StoredCookProgress restored = (await store.read(
        'ribs',
        now: t0.add(const Duration(minutes: 20)),
      ))!;

      expect(restored.currentStep, 2);
      expect(restored.checkedStepIds, <String>{'step-1', 'step-2'});
    });

    test('a recipe never cooked has nothing to restore', () async {
      expect(await store.read('never-opened', now: t0), isNull);
    });

    test('sessions do not bleed between recipes', () async {
      // Opening a different recipe must not inherit another's ticks.
      await save(recipeId: 'ribs', checked: <String>{'step-1'});
      await save(recipeId: 'curry', checked: <String>{'other-1', 'other-2'});

      expect((await store.read('ribs', now: t0))!.checkedStepIds, <String>{
        'step-1',
      });
      expect(
        (await store.read('curry', now: t0))!.checkedStepIds,
        hasLength(2),
      );
    });

    test('saving again replaces rather than piling up', () async {
      await save(currentStep: 1, checked: <String>{'step-1'});
      await save(currentStep: 4, checked: <String>{'step-1', 'step-4'});

      final StoredCookProgress restored = (await store.read('ribs', now: t0))!;
      expect(restored.currentStep, 4);
      expect(restored.checkedStepIds, hasLength(2));
    });

    test('a session with nothing ticked still round-trips', () async {
      await save(currentStep: 0, checked: const <String>{});

      final StoredCookProgress restored = (await store.read('ribs', now: t0))!;
      expect(restored.currentStep, 0);
      expect(restored.checkedStepIds, isEmpty);
    });
  });

  group('an old session is a new cook', () {
    test('one from overnight is still yours', () async {
      // Long enough to cover a braise left going overnight.
      await save();
      expect(
        await store.read('ribs', now: t0.add(const Duration(hours: 10))),
        isNotNull,
      );
    });

    test('one from last week starts clean', () async {
      await save();
      expect(
        await store.read('ribs', now: t0.add(const Duration(days: 7))),
        isNull,
      );
    });

    test('and the stale row is cleared, not left to linger', () async {
      await save();
      await store.read('ribs', now: t0.add(const Duration(days: 7)));

      expect(
        await store.read('ribs', now: t0),
        isNull,
        reason: 'the stale session should have been deleted',
      );
    });
  });

  group('starting over', () {
    test('clears that recipe and leaves the others alone', () async {
      await save(recipeId: 'ribs');
      await save(recipeId: 'curry');

      await store.clear('ribs');

      expect(await store.read('ribs', now: t0), isNull);
      expect(await store.read('curry', now: t0), isNotNull);
    });
  });
}
