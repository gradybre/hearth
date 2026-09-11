import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/destinations.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';

/// The section registry is the thing that makes "add a pillar" a small change
/// (spec §6.2). These are the promises the rest of the app leans on.
void main() {
  group('what a section is', () {
    test('a section is built exactly when it has somewhere to go', () {
      // Derived rather than declared, so an "available" flag can never claim a
      // section is ready while it has no screens behind it.
      for (final AppSection section in appSections) {
        expect(section.isBuilt, section.destinations.isNotEmpty);
      }
    });

    test('Nutrition is the one that is built, and it holds the four tabs', () {
      expect(builtSections.map((AppSection s) => s.id), <String>['nutrition']);
      expect(builtSections.single.destinations, foodDestinations);
    });

    test('the ones that are not built are still named and described', () {
      // They render as a sentence on the home screen, and the day one is built
      // its card is already written — so an empty label is a real gap.
      for (final AppSection section in unbuiltSections) {
        expect(section.label, isNotEmpty);
        expect(section.blurb, isNotEmpty);
      }
      expect(unbuiltSections, isNotEmpty);
    });

    test('ids are unique, because the launch preference stores one', () {
      final Set<String> ids = appSections.map((AppSection s) => s.id).toSet();
      expect(ids, hasLength(appSections.length));
    });

    test('only a built section can be asked where it goes', () {
      // The type carries it, not a convention. `AppSection.path` used to exist
      // on every section and read `destinations.first`, so naming an unbuilt
      // one — `LaunchTarget.section(appSections[1])` — threw a StateError at
      // runtime where a compile error belonged. Now `path` lives on
      // BuiltSection alone, and the registry hands out nothing else: the two
      // lines this test replaces would not compile.
      expect(builtSections, isA<List<BuiltSection>>());
      expect(unbuiltSections, isA<List<PlannedSection>>());
      for (final AppSection section in appSections) {
        expect(section.isBuilt, section is BuiltSection);
      }
    });

    test('and no room is declared built with nowhere to go', () {
      // The other half of the guarantee, and the half a const constructor
      // cannot assert for itself: `path` reads `destinations.first`, so a
      // BuiltSection written with an empty list would put the old StateError
      // back. The registry is the only place either kind is written, and this
      // is what holds it to writing them correctly.
      for (final BuiltSection section in builtSections) {
        expect(section.destinations, isNotEmpty, reason: section.label);
        expect(section.path, section.destinations.first.path);
      }
    });

    test('entering a section lands on its first tab', () {
      // Hearth opened on the recipe library before there was a home screen,
      // and going into Nutrition should still land there.
      expect(builtSections.single.path, '/recipes');
    });

    test('every tab says what it is out loud', () {
      // Screen-reader labels on all navigation are non-negotiable (§6.3).
      for (final AppSection section in appSections) {
        for (final AppDestination tab in section.destinations) {
          expect(tab.semanticLabel, isNotEmpty);
          expect(tab.label, isNotEmpty);
        }
      }
    });
  });

  group('which section owns a route', () {
    test('each of the four tabs resolves to Nutrition', () {
      for (final AppDestination tab in foodDestinations) {
        expect(sectionForPath(tab.path)?.id, 'nutrition');
      }
    });

    test('a route outside every section belongs to none', () {
      // Settings and the home screen belong to the app, not to a room — the
      // shell must not try to draw section chrome around them.
      expect(sectionForPath('/'), isNull);
      expect(sectionForPath('/household'), isNull);
      expect(sectionForPath('/recipe/abc'), isNull);
    });

    test('a section that is only named cannot be looked up by id', () {
      // Nothing should be able to hand out a way into an empty room.
      expect(sectionById('nutrition')?.label, 'Nutrition');
      expect(sectionById('fitness'), isNull);
    });
  });

  group('what a stored launch preference means', () {
    test('every option survives being written and read back', () {
      for (final LaunchTarget target in LaunchTarget.options) {
        expect(LaunchTarget.parse(target.stored), target);
      }
    });

    test('a device that has never chosen opens on the home screen', () {
      expect(LaunchTarget.parse(null), LaunchTarget.home);
    });

    test('an unrecognised value opens on the home screen rather than '
        'nowhere', () {
      // A row written by a newer build, or a section that has since been taken
      // out. Home is always a defensible answer; failing to open is not.
      expect(LaunchTarget.parse('midnight'), LaunchTarget.home);
      expect(LaunchTarget.parse(''), LaunchTarget.home);
      expect(LaunchTarget.parse('section:fitness'), LaunchTarget.home);
    });

    test(
      'a section named "home" could not be mistaken for the home screen',
      () {
        // Which is why the stored form is prefixed. The house section's id is
        // literally `home`.
        expect(LaunchTarget.parse('home'), LaunchTarget.home);
        expect(LaunchTarget.parse('section:home'), LaunchTarget.home);
        expect(
          LaunchTarget.section(builtSections.single).stored,
          'section:nutrition',
        );
      },
    );

    test('each option maps to the route the app would open at', () {
      expect(LaunchTarget.home.path, '/');
      expect(LaunchTarget.section(builtSections.single).path, '/recipes');
    });

    test('every option says what it is in words as well as an icon', () {
      // Meaning is never carried by an icon alone (spec §6.3).
      for (final LaunchTarget target in LaunchTarget.options) {
        expect(target.label, isNotEmpty);
      }
    });
  });
}
