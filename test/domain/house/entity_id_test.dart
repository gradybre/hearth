import 'package:hearth/domain/house/entity_id.dart';
import 'package:test/test.dart';

/// Identity, and what may not be inferred from it
/// (`docs/HOME_ASSISTANT_SPEC.md` §3).
void main() {
  group('an entity id is parsed once', () {
    test('into the kind of thing and the thing', () {
      final EntityId? id = EntityId.tryParse('binary_sensor.front_door');
      expect(id, isNotNull);
      expect(id!.domain, HaDomain.binarySensor);
      expect(id.objectId, 'front_door');
      expect(id.value, 'binary_sensor.front_door');
    });

    test('and a domain Hearth cannot draw is still a real id', () {
      // §3 defers locks. Deferring them means saying so on the discovery
      // screen, which takes an id that parsed — not one that was refused.
      final EntityId? id = EntityId.tryParse('lock.front_door');
      expect(id, isNotNull);
      expect(id!.domain, HaDomain.unsupported);
      expect(id.domainName, 'lock');
      expect(
        id.value,
        'lock.front_door',
        reason: 'an unsupported domain still has to round-trip exactly',
      );
    });
  });

  group('and anything that is not one is refused', () {
    test('a bare domain addresses everything in it', () {
      // The empty target §6.2 forbids: `switch.` is every switch in the
      // house, and turning all of them off is not what anybody tapped.
      expect(EntityId.tryParse('switch.'), isNull);
    });

    test('so does nothing at all', () {
      expect(EntityId.tryParse(''), isNull);
      expect(EntityId.tryParse(null), isNull);
      expect(EntityId.tryParse('switch'), isNull);
      expect(EntityId.tryParse('.front_door'), isNull);
    });

    test('and a second dot means this is not an entity id', () {
      expect(EntityId.tryParse('switch.front.door'), isNull);
    });

    test('and neither is anything outside the slug rules', () {
      // Refusing here is what lets everything downstream put an EntityId in a
      // request without checking it again.
      expect(EntityId.tryParse('switch.Front_Door'), isNull);
      expect(EntityId.tryParse('switch.front door'), isNull);
      expect(EntityId.tryParse('switch.front-door'), isNull);
      expect(EntityId.tryParse('switch.front/door'), isNull);
      expect(EntityId.tryParse('Switch.front_door'), isNull);
    });
  });

  group('the name is not a capability', () {
    test('a switch named after a light is still a switch', () {
      // The whole reason the domain is parsed and the words are not: this is
      // a plug somebody plugged a lamp into. Offering it a brightness slider
      // would be offering a control that can only fail.
      final EntityId id = EntityId.tryParse('switch.front_door_light')!;
      expect(id.domain, HaDomain.switch_);
      expect(id.domain, isNot(HaDomain.light));
    });

    test('and a sensor named like a camera is still a sensor', () {
      final EntityId id = EntityId.tryParse('sensor.driveway_camera_battery')!;
      expect(id.domain, HaDomain.sensor);
    });
  });

  group('two ids are the same id when they say the same thing', () {
    test('which is what lets a selection survive a reconnect', () {
      expect(
        EntityId.tryParse('light.kitchen'),
        EntityId.tryParse('light.kitchen'),
      );
      expect(
        EntityId.tryParse('light.kitchen').hashCode,
        EntityId.tryParse('light.kitchen').hashCode,
      );
    });

    test('and two different things are never the same id', () {
      // §4.2: a removed selection stays missing rather than being reassigned
      // to something similarly named. That starts with these not matching.
      expect(
        EntityId.tryParse('light.kitchen'),
        isNot(EntityId.tryParse('light.kitchen_2')),
      );
      expect(
        EntityId.tryParse('light.kitchen'),
        isNot(EntityId.tryParse('switch.kitchen')),
      );
    });
  });
}
