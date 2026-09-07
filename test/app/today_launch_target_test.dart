import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/shell/destinations.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';
import 'package:hearth/domain/planning/week.dart';

import '../support/app_harness.dart';

/// Opening on the day you are in (spec §6.2, U02).
///
/// A section opens on its first destination, which for Nutrition is the
/// recipe library — so someone who opens Hearth to log lunch had no way to
/// ask for the day.
void main() {
  test('is offered alongside the home screen and the sections', () {
    expect(LaunchTarget.options, contains(LaunchTarget.today));
    expect(LaunchTarget.options.first, LaunchTarget.home);
  });

  test('carries no date, so it cannot open on the wrong one', () {
    // A stored `/plan/2026-09-07` would open on the seventh for ever. What
    // "today" means is resolved when the day provider is built, at launch.
    expect(LaunchTarget.today.stored, 'today');
    expect(RegExp(r'\d').hasMatch(LaunchTarget.today.path), isFalse);
  });

  test('and points at the plan destination, not a path of its own', () {
    // `LaunchTarget.section` takes its path from the registry, on the stated
    // principle that the sections are data. This one spells the path out,
    // because a destination has no id to look it up by — so the two can
    // drift, and the app would open on a route it no longer has for everyone
    // who chose Today. Held together here instead.
    final AppDestination plan = foodDestinations.firstWhere(
      (AppDestination destination) => destination.label == 'Plan',
    );

    expect(
      LaunchTarget.today.path,
      plan.path,
      reason: 'Today opens on a path the app no longer routes',
    );
  });

  test('is read back from what was stored', () {
    expect(LaunchTarget.parse('today'), LaunchTarget.today);
  });

  group('what was already stored still means what it meant', () {
    test('the home screen', () {
      expect(LaunchTarget.parse('home'), LaunchTarget.home);
      expect(LaunchTarget.parse(null), LaunchTarget.home);
    });

    test('a section', () {
      final LaunchTarget nutrition = LaunchTarget.options.firstWhere(
        (LaunchTarget target) => target.stored == 'section:nutrition',
      );
      expect(LaunchTarget.parse('section:nutrition'), nutrition);
      expect(nutrition.path, '/recipes');
    });

    test('and anything unrecognised still opens somewhere', () {
      // A value from a newer build, or a section since taken out. Opening on
      // the home screen is always defensible; failing to open is not.
      expect(LaunchTarget.parse('section:gone'), LaunchTarget.home);
      expect(LaunchTarget.parse('tomorrow'), LaunchTarget.home);
    });
  });

  group('and choosing it opens there', () {
    testWidgets('on the day, not the recipe library', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, launchTarget: LaunchTarget.today);
      await pumpFrames(tester, frames: 12);

      // The Plan tab's own headings, which the recipe library does not have.
      expect(find.text('Day'), findsWidgets);
      expect(find.text('Week'), findsWidgets);
    });

    testWidgets('with the plan tab selected, not merely present', (
      WidgetTester tester,
    ) async {
      // Reading `selectedDateProvider` was the first version of this and it
      // proved nothing: that provider resolves to today in any container, so
      // the assertion passed with the *home* launch target too. The selected
      // icon is a fact about where the app actually opened.
      await pumpHearthApp(tester, launchTarget: LaunchTarget.today);
      await pumpFrames(tester, frames: 12);

      expect(find.byIcon(Icons.calendar_today), findsWidgets);
      expect(find.byIcon(Icons.menu_book), findsNothing);

      // And the day it opened on is the day it is.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp).first),
      );
      expect(container.read(selectedDateProvider), dayKey(DateTime.now()));
    });

    testWidgets('while the home screen still opens on the home screen', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester, launchTarget: LaunchTarget.home);
      await pumpFrames(tester, frames: 12);

      expect(find.text('Nutrition'), findsWidgets);
    });

    testWidgets('and a section still opens on its first destination', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(
        tester,
        launchTarget: LaunchTarget.section(builtSections.first),
      );
      await pumpFrames(tester, frames: 12);

      expect(find.byIcon(Icons.menu_book), findsWidgets);
      expect(find.byIcon(Icons.calendar_today), findsNothing);
    });
  });
}
