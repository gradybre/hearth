import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/data/local/preference_store.dart';

import '../../support/app_harness.dart';

/// Where Hearth opens (spec §6.2).
///
/// The louder version of the theme's flash problem: the router is built with a
/// starting route, so an answer that arrives a frame late is not a wrong colour
/// — it is the home screen appearing and then being replaced by a section, or
/// the other way round, every single launch.
/// Nutrition, by name.
///
/// These used to say `builtSections.single`, which was true while it was the
/// only room with tabs in it. Every section has tabs now, so the one this
/// suite is about has to be named.
BuiltSection get _nutrition =>
    builtSections.firstWhere((BuiltSection s) => s.id == 'nutrition');

void main() {
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

    test('a fresh install opens on the home screen', () async {
      final ProviderContainer container = containerOn(db);
      expect(
        await container.read(launchTargetProvider.future),
        LaunchTarget.home,
      );
    });

    test('choosing Nutrition outlives the container that chose it', () async {
      final LaunchTarget nutrition = LaunchTarget.section(_nutrition);
      final ProviderContainer first = containerOn(db);
      await first.read(launchTargetProvider.future);
      await first.read(launchTargetProvider.notifier).choose(nutrition);

      final ProviderContainer afterRestart = containerOn(db);
      expect(await afterRestart.read(launchTargetProvider.future), nutrition);
    });

    test('the choice lands in the device-local preference store', () async {
      // Named explicitly: this must stay device-local and out of sync, so one
      // person opening straight into Nutrition never moves where their
      // partner's app opens.
      final ProviderContainer container = containerOn(db);
      await container.read(launchTargetProvider.future);
      await container
          .read(launchTargetProvider.notifier)
          .choose(LaunchTarget.section(_nutrition));

      expect(
        await PreferenceStore(db).read(PreferenceStore.launchTarget),
        'section:nutrition',
      );
    });

    test('a write that fails takes the choice back with it', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          preferenceStoreProvider.overrideWithValue(_Unwritable(db)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(launchTargetProvider.future);

      await expectLater(
        container
            .read(launchTargetProvider.notifier)
            .choose(LaunchTarget.section(_nutrition)),
        throwsStateError,
        reason: 'the failure went nowhere the screen could see it',
      );

      expect(container.read(launchTargetProvider).value, LaunchTarget.home);
    });

    test('a value read before the first frame is there without waiting', () {
      // Which is the whole reason bootstrap reads it: the router is built from
      // this, and it is built once.
      final ProviderContainer container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          bootLaunchTargetProvider.overrideWithValue(
            LaunchTarget.section(_nutrition),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(launchTargetProvider).value?.path, '/recipes');
    });
  });

  group('so the first frame is already the right screen', () {
    testWidgets('a device that asked for Nutrition never sees the home screen', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        launchTarget: LaunchTarget.section(_nutrition),
      );

      // Before any frames are pumped past the first: no flash of a home screen
      // on the way in.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Hearth'), findsNothing);
    });

    testWidgets('and a device that asked for home never sees a section', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, launchTarget: LaunchTarget.home);

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Hearth'), findsOneWidget);
    });

    testWidgets('changing it does not move the screen you are looking at', (
      WidgetTester tester,
    ) async {
      // The preference is a statement about the next launch. Teleporting
      // someone out of Settings because they touched a row would be a
      // surprise, not a preference.
      await pumpHearthApp(
        tester,
        size: const Size(500, 2400),
        launchTarget: LaunchTarget.home,
      );
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Settings'));
      await pumpFrames(tester);
      // A page of its own now (review §7.8): the index says where the choice
      // stands, and the answers live behind it.
      await tester.tap(find.text('Opens on'));
      await pumpFrames(tester);

      await tester.tap(find.text('Nutrition'));
      await pumpFrames(tester);

      expect(
        find.text('Opens on'),
        findsOneWidget,
        reason: 'the tap left the settings page it was made on',
      );
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}

/// A device whose preference table refuses to be written to.
class _Unwritable extends PreferenceStore {
  _Unwritable(super.db);

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('the disk said no');
}
