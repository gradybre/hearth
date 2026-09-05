import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/theme_choice.dart';
import 'package:hearth/data/auth/auth_gateway.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';
import 'package:hearth/main.dart';

import '../../support/fake_auth.dart';

void main() {
  group('what a stored choice means', () {
    test('every choice survives being written and read back', () {
      // The stored form is the enum name, so this is also the guard against
      // renaming a value and silently resetting everyone's theme.
      for (final ThemeChoice choice in ThemeChoice.values) {
        expect(ThemeChoice.parse(choice.stored), choice);
      }
    });

    test('a device that has never chosen follows the device', () {
      expect(ThemeChoice.parse(null), ThemeChoice.system);
    });

    test('an unrecognised value falls back rather than leaving no theme', () {
      // A row written by a newer build, or edited by hand. Guessing would be
      // worse than the default, and throwing would be worst of all — it is
      // the app's entire appearance hanging off one string.
      expect(ThemeChoice.parse('midnight'), ThemeChoice.system);
      expect(ThemeChoice.parse(''), ThemeChoice.system);
    });

    test('each choice maps to the Flutter mode it claims', () {
      expect(ThemeChoice.system.mode, ThemeMode.system);
      expect(ThemeChoice.light.mode, ThemeMode.light);
      expect(ThemeChoice.dark.mode, ThemeMode.dark);
    });

    test('every choice says what it is in words as well as an icon', () {
      // Meaning is never carried by colour or an icon alone (spec §6.3).
      for (final ThemeChoice choice in ThemeChoice.values) {
        expect(choice.label, isNotEmpty);
        expect(choice.blurb, isNotEmpty);
      }
    });
  });

  group('remembering the choice across launches', () {
    late HearthDatabase db;

    setUp(() => db = HearthDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    ProviderContainer containerOn(HearthDatabase db) {
      final ProviderContainer container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a fresh install follows the device', () async {
      final ProviderContainer container = containerOn(db);
      expect(
        await container.read(themeChoiceProvider.future),
        ThemeChoice.system,
      );
    });

    test('choosing dark outlives the container that chose it', () async {
      // The whole point of the setting: a restart must not quietly hand the
      // device back its own preference.
      final ProviderContainer first = containerOn(db);
      await first.read(themeChoiceProvider.future);
      await first.read(themeChoiceProvider.notifier).choose(ThemeChoice.dark);

      final ProviderContainer afterRestart = containerOn(db);
      expect(
        await afterRestart.read(themeChoiceProvider.future),
        ThemeChoice.dark,
      );
    });

    test('the choice lands in the device-local preference store', () async {
      // Named explicitly: this must stay device-local and out of sync, so a
      // partner's screen is never recoloured by a choice they did not make.
      final ProviderContainer container = containerOn(db);
      await container.read(themeChoiceProvider.future);
      await container
          .read(themeChoiceProvider.notifier)
          .choose(ThemeChoice.light);

      expect(
        await PreferenceStore(db).read(PreferenceStore.themeChoice),
        'light',
      );
    });

    test('a write that fails takes the choice back with it', () async {
      // Optimism is right — recolouring the app has no business waiting on
      // sqlite — but an optimistic write that fails and is never taken back
      // leaves the app dark until the next launch and light again after it,
      // with nothing ever said about why.
      final ProviderContainer container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          preferenceStoreProvider.overrideWithValue(UnwritablePreferences(db)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(themeChoiceProvider.future);

      await expectLater(
        container.read(themeChoiceProvider.notifier).choose(ThemeChoice.dark),
        throwsStateError,
        reason: 'the failure went nowhere the screen could see it',
      );

      expect(
        container.read(themeChoiceProvider).value,
        ThemeChoice.system,
        reason: 'the choice was never taken back',
      );
    });

    test('the new choice is on screen before the write finishes', () async {
      // Recolouring the app is the whole point of the tap; it has no business
      // waiting on sqlite.
      final ProviderContainer container = containerOn(db);
      await container.read(themeChoiceProvider.future);

      final Future<void> writing = container
          .read(themeChoiceProvider.notifier)
          .choose(ThemeChoice.dark);

      expect(container.read(themeChoiceProvider).value, ThemeChoice.dark);
      await writing;
    });
  });

  group('the theme the app opens on', () {
    test('a choice read before the first frame is there without waiting', () {
      // The provider reads sqlite, which takes a frame or two. Until it
      // answered, the app painted ThemeMode.system — so every cold start on a
      // dark-mode-off device flashed cream at someone who had asked for dark.
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          launchThemeChoiceProvider.overrideWithValue(ThemeChoice.dark),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(themeChoiceProvider).value, ThemeChoice.dark);
    });

    testWidgets('so the first frame is already dark', (
      WidgetTester tester,
    ) async {
      final HearthDatabase db = HearthDatabase.forTesting(
        NativeDatabase.memory(),
      );
      addTearDown(db.close);
      final StreamController<HearthAccount?> accounts =
          StreamController<HearthAccount?>();
      addTearDown(accounts.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            launchThemeChoiceProvider.overrideWithValue(ThemeChoice.dark),
            // The app root watches sync, and the real controller leaves a
            // lifecycle observer, a debounce timer and a Drift stream running
            // that fake async cannot drive.
            syncControllerProvider.overrideWith(FakeSyncController.new),
            pendingWriteCountProvider.overrideWith(
              (Ref ref) => Stream<int>.value(0),
            ),
            supabaseReadyProvider.overrideWithValue(true),
            authGatewayProvider.overrideWithValue(FakeAuthGateway()),
            accountProvider.overrideWith((Ref ref) => accounts.stream),
          ],
          child: const HearthApp(),
        ),
      );
      accounts.add(null);
      await tester.pump();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
    });
  });
}

/// A device whose preference table refuses to be written to.
class UnwritablePreferences extends PreferenceStore {
  UnwritablePreferences(super.db);

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('the disk said no');
}
