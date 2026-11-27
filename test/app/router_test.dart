import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';

import '../support/app_harness.dart';

/// Where a path that names nothing lands (spec §6.2).
///
/// Hearth hands out links — a share extension, a section tab, a recipe — and
/// the ones it does not recognise have to go somewhere a person can carry on
/// from. Home is the top of the app, so home is the answer; the framework's
/// red error page, which has no way out of it, is not.
void main() {
  const Size phone = Size(390, 844);

  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
    await pumpFrames(tester, frames: 10);
  }

  /// The home screen, by the two things only it says.
  ///
  /// The second used to be the "Still being built" footer, which went when
  /// every section got its tabs, and then the tagline under the wordmark,
  /// which went when the first room became a hero that says what it is for
  /// directly below it. What is durable is the way into that room: only the
  /// home screen offers one, and taking the name from the registry means
  /// renaming a section does not quietly make this assert nothing.
  void expectHome() {
    expect(find.text('Hearth'), findsOneWidget);
    expect(find.text('Open ${builtSections.first.label}'), findsOneWidget);
  }

  testWidgets('a path that names no section goes home', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, size: phone);
    await pumpFrames(tester);

    await goTo(tester, '/fitness');

    expectHome();
  });

  testWidgets('and so does one with more segments than any route has', (
    WidgetTester tester,
  ) async {
    // The section redirect only ever saw `/:section`, so anything deeper fell
    // through to go_router's own error page — a red screen with nothing on it
    // to tap.
    await pumpHearthApp(tester, size: phone);
    await pumpFrames(tester);

    await goTo(tester, '/fitness/sessions/today');

    expectHome();
    expect(find.textContaining('no routes for location'), findsNothing);
  });

  testWidgets('a malformed detail link goes home rather than half-opening', (
    WidgetTester tester,
  ) async {
    await pumpHearthApp(tester, size: phone);
    await pumpFrames(tester);

    await goTo(tester, '/recipe/abc/notes');

    expectHome();
  });

  testWidgets('the paths that do name something still resolve', (
    WidgetTester tester,
  ) async {
    // The guard is worth nothing if it swallows the real ones too.
    await pumpHearthApp(tester, size: phone, launchTarget: LaunchTarget.home);
    await pumpFrames(tester);

    await goTo(tester, '/plan');
    expect(find.byType(NavigationBar), findsOneWidget);

    await goTo(tester, '/household');
    expect(find.text('Settings'), findsWidgets);

    await goTo(tester, '/');
    expectHome();
  });
}
