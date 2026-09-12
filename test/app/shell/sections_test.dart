import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/shell/destinations.dart';
import 'package:hearth/app/shell/launch_target.dart';
import 'package:hearth/app/shell/sections.dart';

/// The section registry is the thing that makes "add a pillar" a small change
/// (spec §6.2). These are the promises the rest of the app leans on.
/// Nutrition, by name — `builtSections.single` was true only while it was the
/// only room with tabs in it.
BuiltSection get _nutrition =>
    builtSections.firstWhere((BuiltSection s) => s.id == 'nutrition');

void main() {
  group('what a section is', () {
    test('a section is built exactly when it has somewhere to go', () {
      // Derived rather than declared, so an "available" flag can never claim a
      // section is ready while it has no screens behind it.
      for (final AppSection section in appSections) {
        expect(section.isBuilt, section.destinations.isNotEmpty);
      }
    });

    test('every room has tabs, and Nutrition still holds its four', () {
      // Fitness, Health and House are walkable now — each has its tabs,
      // and each tab says on the screen behind it that it is not built yet.
      // What `isBuilt` claims is true of the rooms, not of the furniture.
      expect(builtSections.map((AppSection s) => s.id), <String>[
        'nutrition',
        'fitness',
        'health',
        'home',
      ]);
      expect(
        builtSections
            .firstWhere((BuiltSection s) => s.id == 'nutrition')
            .destinations,
        foodDestinations,
      );
    });

    test('every room is named and described, built or not', () {
      // The card is written before the room is furnished, so an empty label
      // is a real gap whichever kind a section is.
      for (final AppSection section in appSections) {
        expect(section.label, isNotEmpty);
        expect(section.blurb, isNotEmpty);
      }
    });

    test('nothing is planned, and the machinery for planning one survives', () {
      // `PlannedSection` is what stops a section claiming to be built with no
      // screens behind it, and the home screen's footer names whatever is in
      // this list. Both are unreachable while it is empty — kept, because the
      // next room starts here and the type is what makes `isBuilt` honest.
      expect(unbuiltSections, isEmpty);

      const PlannedSection next = PlannedSection(
        id: 'garden',
        label: 'Garden',
        blurb: 'Beds, plantings, and what came up.',
        icon: Icons.local_florist_outlined,
      );
      expect(next.isBuilt, isFalse);
      expect(next.destinations, isEmpty);
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
      expect(
        builtSections.firstWhere((BuiltSection s) => s.id == 'nutrition').path,
        '/recipes',
      );
      for (final BuiltSection section in builtSections) {
        expect(section.path, section.destinations.first.path);
      }
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

    test('every room can be looked up by id, now that every room has tabs', () {
      // `sectionById` hands out a way *in*, so it only ever answers for a
      // built section. That used to exclude Fitness; it no longer does, and
      // the guarantee it enforces is unchanged — an id with no tabs behind it
      // still gets nothing.
      for (final BuiltSection section in builtSections) {
        expect(sectionById(section.id)?.label, section.label);
      }
      expect(sectionById('garden'), isNull);
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
      // `section:fitness` used to stand for "a section that has since been
      // taken out", and Fitness is a real destination now. A name nothing
      // answers to makes the point without dating.
      expect(LaunchTarget.parse('section:garden'), LaunchTarget.home);
    });

    test(
      'a section named "home" could not be mistaken for the home screen',
      () {
        // Which is why the stored form is prefixed. The House section's id
        // is literally `home`, and now that it has tabs the two really are two
        // different destinations rather than one falling back to the other.
        //
        // No device can hold the old meaning: `section:home` was never
        // offerable while House had nowhere to go, so nothing stored it.
        expect(LaunchTarget.parse('home'), LaunchTarget.home);
        expect(LaunchTarget.parse('section:home').path, '/thermostat');
        expect(LaunchTarget.section(_nutrition).stored, 'section:nutrition');
      },
    );

    test('a room with nothing in it is not offered as a start screen', () {
      // Opening Hearth on a page that says "Not built yet." every launch is
      // not a preference anybody means to express. The list is derived from
      // `builtSections`, and since spec §11 that is every room — so it has to
      // ask the further question the launcher asks.
      //
      // House is on the list because the thermostat is a real screen now;
      // Fitness and Health are not, because their tabs still draw the
      // placeholder. That is the question answering itself.
      expect(LaunchTarget.options.map((LaunchTarget t) => t.stored), <String>[
        'home',
        'today',
        'section:nutrition',
        'section:home',
      ]);
    });

    test('each option maps to the route the app would open at', () {
      expect(LaunchTarget.home.path, '/');
      expect(LaunchTarget.section(_nutrition).path, '/recipes');
      for (final BuiltSection section in builtSections) {
        expect(LaunchTarget.section(section).path, section.path);
      }
    });

    test('every option says what it is in words as well as an icon', () {
      // Meaning is never carried by an icon alone (spec §6.3).
      for (final LaunchTarget target in LaunchTarget.options) {
        expect(target.label, isNotEmpty);
      }
    });
  });
}
