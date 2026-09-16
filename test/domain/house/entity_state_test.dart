import 'package:hearth/domain/house/entity_state.dart';
import 'package:test/test.dart';

/// Absence of news is not good news (`docs/HOME_ASSISTANT_SPEC.md` §4.2, §6.1).
void main() {
  EntityState live(String? raw) => EntityState(
    availability: Availability.fromState(raw),
    freshness: Freshness.live,
    raw: raw,
  );

  group('Home Assistant says three different things', () {
    test('a value, which is a value', () {
      expect(live('on').availability, Availability.known);
      expect(live('on').value, 'on');
    });

    test('"unknown", which is not a value', () {
      // It arrives as an ordinary state string, which is the trap: read `raw`
      // without checking and the door is in the state "unknown".
      expect(live('unknown').availability, Availability.unknown);
      expect(live('unknown').value, isNull);
    });

    test('and "unavailable", which is a different not-a-value', () {
      // Kept distinct from unknown all the way through: one is a thing that
      // has not said, the other is a thing that cannot be reached, and §4.2
      // requires them to stay apart.
      expect(live('unavailable').availability, Availability.unavailable);
      expect(live('unavailable').value, isNull);
      expect(
        live('unavailable').availability,
        isNot(live('unknown').availability),
      );
    });

    test('and nothing at all is unknown rather than a crash', () {
      expect(live(null).availability, Availability.unknown);
      expect(live(null).value, isNull);
    });
  });

  group('and Hearth has its own doubt, separately', () {
    test('a reading over a live connection is confident', () {
      expect(live('off').isConfident, isTrue);
    });

    test('the same reading over a dead one is not', () {
      // The door has not moved. What changed is whether anybody would know if
      // it had — so "Closed" becomes "Last known: closed".
      final EntityState stale = live('off').staleNow();
      expect(stale.value, 'off', reason: 'the reading is still worth showing');
      expect(stale.freshness, Freshness.lastKnown);
      expect(
        stale.isConfident,
        isFalse,
        reason: 'a broken connection makes the snapshot unverified (§6.1)',
      );
    });

    test('and a known value Hearth has never read shows nothing', () {
      // Cold offline launch. §5.3: do not fabricate last-known readings.
      const EntityState cold = EntityState.neverRead();
      expect(cold.freshness, Freshness.neverRead);
      expect(cold.value, isNull);
      expect(cold.isConfident, isFalse);
    });

    test('and going stale cannot invent a reading that never existed', () {
      // The failure this guards: a connection drops before the first snapshot
      // and every card quietly becomes "Last known: —".
      const EntityState cold = EntityState.neverRead();
      expect(cold.staleNow().freshness, Freshness.neverRead);
      expect(cold.staleNow().value, isNull);
    });
  });

  group('the two doubts are independent', () {
    test('a live connection reporting unavailable is not confident', () {
      // Home Assistant is up and telling us the battery is flat. Hearth's
      // connection is fine; the door sensor is not.
      expect(live('unavailable').isConfident, isFalse);
    });

    test('and a stale connection does not become unavailable', () {
      // The other direction: our socket died. That says nothing about whether
      // Home Assistant can reach the door, and claiming "Unavailable" would
      // be reporting our own fault as the house's.
      final EntityState stale = live('on').staleNow();
      expect(stale.availability, Availability.known);
      expect(stale.freshness, Freshness.lastKnown);
    });
  });

  group('and the attributes are part of the reading', () {
    // Found by the command lane, in this file's own code. `EntityState`
    // presents itself as a value, and a caller comparing two of them to decide
    // whether anything moved is the obvious thing to write:
    //
    //     if (next == current) return;
    //
    // With `attributes` left out of equality, that line silently swallows an
    // attribute-only change — including the very event that confirms a
    // brightness command, which is a change to `brightness` and to nothing
    // else. In practice Home Assistant's `last_updated` moves when an
    // attribute does, so the two usually differ by that field anyway; the
    // cases where they do not are a payload with no timestamp, and a state
    // never read. Relying on a neighbouring field to carry a comparison this
    // type claims to make is not a contract, it is a coincidence.
    EntityState bulb(int brightness, {DateTime? at}) => EntityState(
      availability: Availability.known,
      freshness: Freshness.live,
      raw: 'on',
      attributes: <String, Object?>{'brightness': brightness},
      lastChanged: at,
      lastUpdated: at,
    );

    test('a bulb at 40 is not the same reading as the same bulb at 200', () {
      expect(bulb(40), isNot(bulb(200)));
    });

    test('and two readings that agree completely are still equal', () {
      // The other half: a rebuild with identical state must not look like a
      // change, or every frame is a change.
      expect(bulb(40), bulb(40));
      expect(bulb(40).hashCode, bulb(40).hashCode);
    });

    test('even when nothing carries a timestamp to tell them apart', () {
      // The case the coincidence does not cover.
      expect(bulb(40, at: null), isNot(bulb(200, at: null)));
    });

    test('and a nested attribute counts too', () {
      // `hs_color` arrives as a list. Comparing maps by identity would call
      // these equal, which is the same bug one level down.
      EntityState coloured(List<double> hs) => EntityState(
        availability: Availability.known,
        freshness: Freshness.live,
        raw: 'on',
        attributes: <String, Object?>{'hs_color': hs},
      );
      expect(coloured(<double>[30, 80]), isNot(coloured(<double>[210, 80])));
      expect(coloured(<double>[30, 80]), coloured(<double>[30, 80]));
    });
  });

  group('the timestamps are three different facts', () {
    test('an unchanged sensor is not a stale one', () {
      // §6.1: a door that has stayed shut for a week is healthy, and deciding
      // it is stale because `lastChanged` is old is how a working sensor gets
      // reported as broken.
      final DateTime weekAgo = DateTime.utc(2026, 1, 8);
      final DateTime justNow = DateTime.utc(2026, 1, 15, 12);
      final EntityState door = EntityState(
        availability: Availability.known,
        freshness: Freshness.live,
        raw: 'off',
        lastChanged: weekAgo,
        lastUpdated: justNow,
      );

      expect(door.isConfident, isTrue);
      expect(door.lastChanged, weekAgo);
      expect(
        door.lastUpdated,
        justNow,
        reason: 'last_changed and last_updated are not the same fact',
      );
    });
  });
}
