import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/house/ha_credentials.dart';
import 'package:hearth/domain/house/ha_endpoint.dart';
import 'package:hearth/features/house/ha_setup_screen.dart';

/// Connecting Hearth to Home Assistant (`docs/HOME_ASSISTANT_SPEC.md` §4.1).
void main() {
  // Obviously not a real one.
  const String token = 'NOT_A_REAL_TOKEN_example_long_lived';

  late List<MethodCall> platform;
  String? clipboard;

  setUp(() {
    platform = <MethodCall>[];
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          platform.add(call);
          if (call.method == 'Clipboard.getData') {
            return clipboard == null
                ? null
                : <String, Object?>{'text': clipboard};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Records what the screen was asked to do.
  late List<String> probed;
  late List<String> saved;

  Future<void> open(
    WidgetTester tester, {
    HaSetupOutcome outcome = HaSetupOutcome.reachable,
    Object? saveThrows,
  }) async {
    probed = <String>[];
    saved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: HearthTheme.light(),
        home: HaSetupScreen(
          // A fresh key per pump. Without one, re-pumping the same widget type
          // updates the existing State rather than replacing it, so a test
          // that opens the screen twice inherits the first run's messages —
          // which grows the list and pushes the button out of it.
          key: UniqueKey(),
          probe: (HaEndpoint endpoint, String t) async {
            probed.add('${endpoint.restBase}');
            return outcome;
          },
          save: (HaEndpoint endpoint, String t) async {
            if (saveThrows != null) throw saveThrows;
            saved.add('${endpoint.restBase}');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillIn(
    WidgetTester tester, {
    required String address,
    String? withToken,
  }) async {
    await tester.enterText(find.byType(TextField).first, address);
    if (withToken != null) {
      await tester.enterText(find.byType(TextField).last, withToken);
    }
    await tester.pumpAndSettle();
  }

  group('the token is not on display', () {
    testWidgets('it is obscured until somebody asks', (
      WidgetTester tester,
    ) async {
      // A long-lived token shown by default is shown to the room, and to
      // whoever is looking at the screen share.
      await open(tester);
      final TextField field = tester.widget<TextField>(
        find.byType(TextField).last,
      );
      expect(field.obscureText, isTrue);
    });

    testWidgets('and revealing it is a press', (WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Show the token'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isFalse,
      );
      expect(find.byTooltip('Hide the token'), findsOneWidget);
    });
  });

  group('the clipboard is not read on its own', () {
    testWidgets('opening the screen reads nothing', (
      WidgetTester tester,
    ) async {
      // An app that inspects the clipboard on open is reading whatever else
      // somebody copied — a password, an address, somebody else's token.
      clipboard = 'something private';
      await open(tester);

      expect(
        platform.where((MethodCall c) => c.method == 'Clipboard.getData'),
        isEmpty,
      );
    });

    testWidgets('and only a press does', (WidgetTester tester) async {
      clipboard = token;
      await open(tester);
      await tester.tap(find.text('Paste the token'));
      await tester.pumpAndSettle();

      expect(
        platform.where((MethodCall c) => c.method == 'Clipboard.getData'),
        hasLength(1),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        token,
      );
    });
  });

  group('an address is checked before a token is sent to it', () {
    testWidgets('a credential in the address is refused, not forwarded', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await fillIn(
        tester,
        address: 'https://user:pass@ha.example.test',
        withToken: token,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(probed, isEmpty, reason: 'nothing was contacted');
      expect(find.textContaining('Leave the sign-in details'), findsOneWidget);
    });

    testWidgets('an unencrypted address needs the tick', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await fillIn(
        tester,
        address: 'http://192.168.1.10:8123',
        withToken: token,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(probed, isEmpty);
      // Specific, because the checkbox's own label also says "not encrypted"
      // — a looser finder matches the choice as well as the complaint.
      expect(find.textContaining('Tick the box below'), findsOneWidget);
    });

    testWidgets('and with the tick it goes through', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await fillIn(
        tester,
        address: 'http://192.168.1.10:8123',
        withToken: token,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(probed, hasLength(1));
      expect(saved, hasLength(1));
    });

    testWidgets('a public address does not get the tick as an excuse', (
      WidgetTester tester,
    ) async {
      // §5.1: a public host is not local because somebody said so.
      await open(tester);
      await fillIn(tester, address: 'http://ha.example.com', withToken: token);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(probed, isEmpty);
      expect(find.textContaining('only use an unencrypted'), findsOneWidget);
    });
  });

  group('nothing is saved until the connection is proved', () {
    testWidgets('a refused token saves nothing', (WidgetTester tester) async {
      await open(tester, outcome: HaSetupOutcome.refused);
      await fillIn(
        tester,
        address: 'https://ha.example.test',
        withToken: token,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(probed, hasLength(1));
      expect(saved, isEmpty, reason: 'a working connection is not replaced');
      expect(find.textContaining('did not accept that token'), findsOneWidget);
    });

    testWidgets('and each failure says which part to change', (
      WidgetTester tester,
    ) async {
      // "That will not work" tells somebody nothing about what to fix.
      await open(tester, outcome: HaSetupOutcome.unreachable);
      await fillIn(
        tester,
        address: 'https://ha.example.test',
        withToken: token,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing answered'), findsOneWidget);
    });

    testWidgets('and a keychain failure is said out loud', (
      WidgetTester tester,
    ) async {
      // §4.1: losing secure storage must fail clearly, never fall back to
      // somewhere ordinary.
      await open(
        tester,
        saveThrows: const HaCredentialException(
          'Hearth could not save the Home Assistant token securely on this '
          'device. It has not been saved anywhere else.',
        ),
      );
      await fillIn(
        tester,
        address: 'https://ha.example.test',
        withToken: token,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('has not been saved'), findsOneWidget);
    });
  });

  group('no failure quotes what was typed', () {
    testWidgets('not the refusal, not the success', (
      WidgetTester tester,
    ) async {
      // A token in an on-screen error is a token in a screenshot, a bug
      // report and a support thread.
      for (final HaSetupOutcome outcome in HaSetupOutcome.values) {
        await open(tester, outcome: outcome);
        await fillIn(
          tester,
          address: 'https://ha.example.test',
          withToken: token,
        );
        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();

        // Scoped to `Text`, deliberately. The token field itself holds the
        // token — that is the point of it, and it is obscured. What must
        // never carry it is a message: a token in an on-screen error is a
        // token in a screenshot, a bug report and a support thread.
        final Iterable<Text> messages = tester.widgetList<Text>(
          find.byType(Text),
        );
        expect(
          messages.where((Text t) => (t.data ?? '').contains(token)),
          isEmpty,
          reason: 'the token appeared in a message for $outcome',
        );
      }
    });
  });

  group('the example address is not somebody\'s house', () {
    testWidgets('it is a documentation name', (WidgetTester tester) async {
      // §4.1: never prefill a real household URL in source. A source file is
      // read by more people than a house has.
      await open(tester);
      final TextField field = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(field.decoration!.hintText, contains('homeassistant.local'));
      expect(field.controller!.text, isEmpty);
    });
  });
}
