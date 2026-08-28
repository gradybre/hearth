import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';

void main() {
  late HearthDatabase db;
  late PreferenceStore store;

  setUp(() {
    db = HearthDatabase.forTesting(NativeDatabase.memory());
    store = PreferenceStore(db);
  });

  tearDown(() => db.close());

  test('an unset preference falls back rather than throwing', () async {
    expect(await store.read('nothing.here'), isNull);
    expect(await store.readFlag('nothing.here'), isFalse);
    expect(await store.readFlag('nothing.here', orElse: true), isTrue);
  });

  test('a flag survives being written and read back', () async {
    await store.writeFlag(PreferenceStore.cookShowAllSteps, value: true);
    expect(await store.readFlag(PreferenceStore.cookShowAllSteps), isTrue);
  });

  test('writing again replaces rather than duplicating', () async {
    await store.writeFlag(PreferenceStore.cookShowAllSteps, value: true);
    await store.writeFlag(PreferenceStore.cookShowAllSteps, value: false);

    expect(await store.readFlag(PreferenceStore.cookShowAllSteps), isFalse);
  });

  test('an unrecognised value falls back instead of guessing', () async {
    // Better a known default than a coin flip on data the app did not write.
    await store.write(PreferenceStore.cookShowAllSteps, 'perhaps');
    expect(
      await store.readFlag(PreferenceStore.cookShowAllSteps, orElse: true),
      isTrue,
    );
  });

  test('preferences are independent of one another', () async {
    await store.writeFlag('a', value: true);
    await store.writeFlag('b', value: false);

    expect(await store.readFlag('a'), isTrue);
    expect(await store.readFlag('b'), isFalse);
  });
}
