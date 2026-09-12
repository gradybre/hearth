import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearth/data/adapters/thermostat.dart';
import 'package:hearth/domain/house/thermostat.dart';
import 'package:hearth/features/house/thermostat_screen.dart';

import '../../support/app_harness.dart';

/// The thermostat screen (spec §11).
///
/// Everything here runs against a fake gateway. What cannot be covered from a
/// keyboard is named in the group at the bottom.
class FakeThermostat implements ThermostatGateway {
  FakeThermostat({this.state, this.failWith});

  ThermostatState? state;
  ThermostatException? failWith;

  final List<ThermostatCommand> sent = <ThermostatCommand>[];
  int statusCalls = 0;
  int unlinks = 0;
  String? codeGiven;

  @override
  String get displayName => 'Google Nest';

  @override
  Future<Uri> consentUrl() async => Uri.parse('https://example.test/consent');

  @override
  Future<String> link(String code) async {
    codeGiven = code;
    state = aThermostat();
    return 'Hallway';
  }

  @override
  Future<ThermostatLink> status() async {
    statusCalls++;
    final ThermostatException? failure = failWith;
    if (failure != null) throw failure;
    final ThermostatState? now = state;
    return now == null
        ? const ThermostatLink.unlinked()
        : ThermostatLink.linked(state: now, linkedByYou: true);
  }

  @override
  Future<void> send(ThermostatCommand command) async {
    final ThermostatException? failure = failWith;
    if (failure != null) throw failure;
    sent.add(command);
  }

  @override
  Future<void> unlink() async {
    unlinks++;
    state = null;
  }
}

ThermostatState aThermostat({
  ThermostatMode mode = ThermostatMode.heat,
  double? heatC,
  double? coolC,
  EcoMode eco = EcoMode.off,
  FanState? fan,
  HvacStatus hvac = HvacStatus.heating,
  Set<ThermostatMode>? availableModes,
}) => ThermostatState(
  label: 'Hallway',
  ambientC: Temp.fToC(70),
  humidityPercent: 43,
  mode: mode,
  availableModes:
      availableModes ??
      <ThermostatMode>{
        ThermostatMode.off,
        ThermostatMode.heat,
        ThermostatMode.cool,
        ThermostatMode.heatCool,
      },
  hvac: hvac,
  heatC: heatC ?? Temp.fToC(68),
  coolC: coolC,
  eco: eco,
  fan: fan,
);

void main() {
  Future<void> openHouse(WidgetTester tester, FakeThermostat fake) async {
    await pumpHearthApp(tester, thermostat: fake);
    await pumpFrames(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/thermostat');
    await pumpFrames(tester, frames: 10);
  }

  group('what the house is doing', () {
    testWidgets('the temperature is the biggest thing on the screen', (
      WidgetTester tester,
    ) async {
      final FakeThermostat fake = FakeThermostat(state: aThermostat());
      await openHouse(tester, fake);

      expect(find.text('Hallway'), findsOneWidget);
      expect(find.text('70°'), findsOneWidget);
      expect(find.text('43% humidity'), findsOneWidget);
    });

    testWidgets('and what the system is doing is a word, not a colour', (
      WidgetTester tester,
    ) async {
      // Meaning is never carried by colour alone (spec §6.3).
      await openHouse(tester, FakeThermostat(state: aThermostat()));
      expect(find.text('Heating'), findsOneWidget);
    });

    testWidgets('the target is shown in Fahrenheit', (
      WidgetTester tester,
    ) async {
      await openHouse(tester, FakeThermostat(state: aThermostat()));
      expect(find.text('Target'), findsOneWidget);
      expect(find.text('68°'), findsOneWidget);
    });
  });

  group('pressing warmer', () {
    testWidgets('moves the number before the thermostat has agreed', (
      WidgetTester tester,
    ) async {
      // Optimism with a short shelf life: the next reading replaces it.
      final FakeThermostat fake = FakeThermostat(state: aThermostat());
      await openHouse(tester, fake);

      await tester.tap(find.byTooltip('Warmer'));
      await tester.pump();

      expect(find.text('69°'), findsOneWidget);
    });

    testWidgets('and a burst of taps becomes one command, not five', (
      WidgetTester tester,
    ) async {
      // Commands are capped at five a minute per device, so one per tap would
      // let a few seconds of deciding exhaust the allowance.
      final FakeThermostat fake = FakeThermostat(state: aThermostat());
      await openHouse(tester, fake);

      for (int i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip('Warmer'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(fake.sent, isEmpty, reason: 'nothing goes while taps continue');

      await tester.pump(ThermostatScreen.settleAfter);
      await pumpFrames(tester);

      expect(fake.sent, hasLength(1));
      expect(Temp.displayF((fake.sent.single as SetHeat).heatC), 73);
    });

    testWidgets('and a refusal puts the number back with the reason', (
      WidgetTester tester,
    ) async {
      final FakeThermostat fake = FakeThermostat(state: aThermostat());
      await openHouse(tester, fake);
      // Set only after the first read, so the screen has a state to put back.
      fake.failWith = const ThermostatException('The thermostat said no.');

      await tester.tap(find.byTooltip('Warmer'));
      await tester.pump();
      await tester.pump(ThermostatScreen.settleAfter);
      await pumpFrames(tester);

      expect(find.text('The thermostat said no.'), findsOneWidget);
      expect(find.text('68°'), findsOneWidget, reason: 'the press came back');
    });
  });

  group('what the thermostat will not let you do', () {
    testWidgets('Eco hides the targets and says why', (
      WidgetTester tester,
    ) async {
      // The API rejects every setpoint while Eco is on, so the control would
      // only ever fail. Saying so beats a button that does nothing.
      await openHouse(
        tester,
        FakeThermostat(state: aThermostat(eco: EcoMode.manualEco)),
      );

      expect(find.textContaining('Eco is holding the temperature'), findsOne);
      expect(find.byTooltip('Warmer'), findsNothing);
    });

    testWidgets('and a thermostat that is off offers no target either', (
      WidgetTester tester,
    ) async {
      await openHouse(
        tester,
        FakeThermostat(
          state: aThermostat(mode: ThermostatMode.off, heatC: null),
        ),
      );

      expect(find.textContaining('The thermostat is off'), findsOne);
      expect(find.byTooltip('Warmer'), findsNothing);
    });

    testWidgets('a heat-only system is not offered Cool', (
      WidgetTester tester,
    ) async {
      await openHouse(
        tester,
        FakeThermostat(
          state: aThermostat(
            availableModes: <ThermostatMode>{
              ThermostatMode.off,
              ThermostatMode.heat,
            },
          ),
        ),
      );

      expect(find.widgetWithText(ChoiceChip, 'Heat'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Cool'), findsNothing);
    });

    testWidgets('and a thermostat with no fan wire has no fan control', (
      WidgetTester tester,
    ) async {
      // Absent is different from off, and the screen is a picture of this
      // thermostat rather than of the API (spec §11).
      await openHouse(tester, FakeThermostat(state: aThermostat()));
      expect(find.text('Fan'), findsNothing);
    });

    testWidgets('while one wired for a fan gets the control', (
      WidgetTester tester,
    ) async {
      await openHouse(
        tester,
        FakeThermostat(state: aThermostat(fan: const FanState(isOn: false))),
      );
      expect(find.text('Fan'), findsOneWidget);
    });
  });

  group('Heat · Cool', () {
    testWidgets('shows both targets and moves one at a time', (
      WidgetTester tester,
    ) async {
      final FakeThermostat fake = FakeThermostat(
        state: aThermostat(
          mode: ThermostatMode.heatCool,
          heatC: Temp.fToC(68),
          coolC: Temp.fToC(76),
        ),
      );
      await openHouse(tester, fake);

      expect(find.text('Heat to'), findsOneWidget);
      expect(find.text('Cool to'), findsOneWidget);

      await tester.tap(find.byTooltip('Warmer').first);
      await tester.pump(ThermostatScreen.settleAfter);
      await pumpFrames(tester);

      final SetRange sent = fake.sent.single as SetRange;
      expect(Temp.displayF(sent.heatC), 69);
      expect(Temp.displayF(sent.coolC), 76, reason: 'the other one held');
    });
  });

  group('when there is nothing connected', () {
    testWidgets('the screen offers to connect rather than drawing a dial', (
      WidgetTester tester,
    ) async {
      await openHouse(tester, FakeThermostat());

      expect(find.text('Connect Google Nest'), findsOneWidget);
      expect(find.byTooltip('Warmer'), findsNothing);
    });

    testWidgets('and pasting the code finishes it', (
      WidgetTester tester,
    ) async {
      final FakeThermostat fake = FakeThermostat();
      await openHouse(tester, fake);

      await tester.enterText(find.byType(TextField), '4/0AbCd');
      await tester.tap(find.text('Finish connecting'));
      await pumpFrames(tester, frames: 10);

      expect(fake.codeGiven, '4/0AbCd');
      expect(find.text('70°'), findsOneWidget);
    });

    testWidgets('a dead credential says reconnect, not "something went wrong"', (
      WidgetTester tester,
    ) async {
      // The failure this integration will actually have: Google revokes the
      // refresh token weekly while the consent screen is in Testing. It has to
      // read as a thing to fix rather than as a bug.
      await openHouse(
        tester,
        FakeThermostat(
          failWith: const ThermostatException(
            'Google stopped accepting Hearth’s connection.',
            needsRelink: true,
          ),
        ),
      );

      expect(find.textContaining('Google stopped accepting'), findsWidgets);
      expect(find.text('Connect Google Nest'), findsOneWidget);
    });
  });

  group('disconnecting', () {
    testWidgets('asks once before destroying the household\'s credential', (
      WidgetTester tester,
    ) async {
      final FakeThermostat fake = FakeThermostat(state: aThermostat());
      await openHouse(tester, fake);

      await tester.tap(find.text('Disconnect'));
      await pumpFrames(tester);
      expect(fake.unlinks, 0, reason: 'one press is not a decision');
      expect(find.textContaining('Really disconnect'), findsOneWidget);

      await tester.tap(find.textContaining('Really disconnect'));
      await pumpFrames(tester, frames: 10);

      expect(fake.unlinks, 1);
      expect(find.text('Connect Google Nest'), findsOneWidget);
    });
  });

  group('a build with no backend', () {
    testWidgets('says so rather than showing a dial that cannot move', (
      WidgetTester tester,
    ) async {
      await pumpHearthApp(tester);
      await pumpFrames(tester);
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go('/thermostat');
      await pumpFrames(tester, frames: 10);

      expect(find.textContaining('no connection to the house'), findsOneWidget);
    });
  });

  group('at three times the text on a small phone (spec §6.3)', () {
    // The screen is a column of controls with a 56-point number at the top of
    // it, which is exactly the shape that stops fitting first. Dynamic type is
    // honoured, not capped, so it has to give way rather than the text.
    for (final double scale in <double>[1.0, 2.0, 3.0]) {
      testWidgets('survives ${scale}x text', (WidgetTester tester) async {
        await pumpHearthApp(
          tester,
          thermostat: FakeThermostat(
            state: aThermostat(
              mode: ThermostatMode.heatCool,
              heatC: Temp.fToC(68),
              coolC: Temp.fToC(76),
              fan: const FanState(isOn: false),
            ),
          ),
          size: const Size(320, 568),
          textScale: scale,
        );
        await pumpFrames(tester);
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go('/thermostat');
        await pumpFrames(tester, frames: 10);

        expect(find.text('Hallway'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the thermostat overflowed at ${scale}x on a 320 phone',
        );
      });
    }

    testWidgets('and the target announces itself as an adjustable', (
      WidgetTester tester,
    ) async {
      // The number is the control, so a screen reader's rotor works on it
      // without anybody having to find the two buttons beside it.
      final SemanticsHandle handle = tester.ensureSemantics();
      await openHouse(tester, FakeThermostat(state: aThermostat()));

      // The value, not the label: an adjustable announces "Target, 68
      // degrees Fahrenheit", and it is the degrees a rotor changes.
      final SemanticsNode target = tester.getSemantics(find.text('68°'));
      expect(target.label.trim(), 'Target');
      expect(target.value, '68 degrees Fahrenheit');
      expect(target.increasedValue, '69 degrees Fahrenheit');
      expect(target.decreasedValue, '67 degrees Fahrenheit');
      expect(
        target.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
        reason: 'a rotor has nothing to turn without it',
      );

      expect(find.bySemanticsLabel(RegExp('Warmer')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Cooler')), findsOneWidget);
      handle.dispose();
    });
  });

  group('what a keyboard cannot prove', () {
    test('is named rather than left to look covered', () {
      // Everything above runs against a fake. None of it says whether Google
      // accepts the consent URL, whether `devices.list` finds the thermostat,
      // whether a setpoint moves the furnace, or whether the refresh token
      // survives past the seven days it gets while the OAuth consent screen
      // is in Testing. Those are Brendan's manual pass and are reported
      // separately — see docs/NEST_SETUP.md.
      expect(true, isTrue);
    });
  });
}
