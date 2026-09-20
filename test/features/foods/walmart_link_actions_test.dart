import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/domain/shopping/walmart_link_reading.dart';
import 'package:hearth/features/foods/walmart_link_field.dart';

WalmartLinkReading _found(String url, {String source = 'nutrition'}) {
  return WalmartLinkReading.fromJson(<String, Object?>{
    'status': 'found',
    'url': url,
    'source': source,
  });
}

WalmartLinkReading _status(String status) {
  return WalmartLinkReading.fromJson(<String, Object?>{'status': status});
}

Widget _harness(Widget child) {
  return MaterialApp(
    theme: HearthTheme.light(),
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3)),
        child: Center(
          child: SizedBox(
            width: 320,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows read button and calls onRead when canRead', (
    WidgetTester tester,
  ) async {
    bool readTapped = false;
    await tester.pumpWidget(
      _harness(
        WalmartLinkActions(
          value: '',
          reading: const WalmartLinkReading.notFound(),
          canRead: true,
          onRead: () => readTapped = true,
        ),
      ),
    );

    expect(find.text('Read link from screenshot'), findsOneWidget);
    await tester.tap(find.text('Read link from screenshot'));
    await tester.pump();
    expect(readTapped, isTrue);

    // notFound is quiet: no other messaging or action buttons.
    expect(find.text('Use this link'), findsNothing);
    expect(find.text('Keep current link'), findsNothing);
  });

  testWidgets('hides read button when canRead is false', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        WalmartLinkActions(
          value: '',
          reading: const WalmartLinkReading.notFound(),
          canRead: false,
          onRead: () {},
        ),
      ),
    );

    expect(find.text('Read link from screenshot'), findsNothing);
  });

  testWidgets('found matching current value shows confirmation only', (
    WidgetTester tester,
  ) async {
    const String url = 'https://www.walmart.com/ip/12345678';
    await tester.pumpWidget(
      _harness(
        WalmartLinkActions(
          value: url,
          reading: _found(url),
          canRead: false,
          onRead: () {},
        ),
      ),
    );

    expect(
      find.text('Read from your screenshot — check before saving.'),
      findsOneWidget,
    );
    expect(find.text('Use this link'), findsNothing);
    expect(find.text('Keep current link'), findsNothing);
  });

  testWidgets(
    'found differing from nonblank value offers use/keep and callbacks',
    (WidgetTester tester) async {
      const String candidate = 'https://www.walmart.com/ip/99999999';
      bool replaced = false;
      bool kept = false;

      await tester.pumpWidget(
        _harness(
          WalmartLinkActions(
            value: 'https://www.walmart.com/ip/11111111',
            reading: _found(candidate),
            canRead: false,
            onRead: () {},
            onReplace: () => replaced = true,
            onKeep: () => kept = true,
          ),
        ),
      );

      expect(find.text(candidate), findsOneWidget);
      expect(find.text('Use this link'), findsOneWidget);
      expect(find.text('Keep current link'), findsOneWidget);

      await tester.ensureVisible(find.text('Use this link'));
      await tester.tap(find.text('Use this link'));
      await tester.pump();
      expect(replaced, isTrue);

      await tester.ensureVisible(find.text('Keep current link'));
      await tester.tap(find.text('Keep current link'));
      await tester.pump();
      expect(kept, isTrue);
    },
  );

  testWidgets('found with blank value shows fallback use-this-link only', (
    WidgetTester tester,
  ) async {
    const String candidate = 'https://www.walmart.com/ip/55555555';
    bool replaced = false;

    await tester.pumpWidget(
      _harness(
        WalmartLinkActions(
          value: '',
          reading: _found(candidate),
          canRead: false,
          onRead: () {},
          onReplace: () => replaced = true,
        ),
      ),
    );

    expect(find.text(candidate), findsOneWidget);
    expect(find.text('Use this link'), findsOneWidget);
    expect(find.text('Keep current link'), findsNothing);

    await tester.ensureVisible(find.text('Use this link'));
    await tester.tap(find.text('Use this link'));
    await tester.pump();
    expect(replaced, isTrue);
  });

  testWidgets('ambiguous shows crop guidance', (WidgetTester tester) async {
    await tester.pumpWidget(
      _harness(
        WalmartLinkActions(
          value: '',
          reading: _status('ambiguous'),
          canRead: false,
          onRead: () {},
        ),
      ),
    );

    expect(
      find.text(
        'More than one Walmart product link was found. Crop to the one '
        'you want, or paste it instead.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unreadable shows choose-another-screenshot guidance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        WalmartLinkActions(
          value: '',
          reading: _status('unreadable'),
          canRead: false,
          onRead: () {},
        ),
      ),
    );

    expect(
      find.text(
        'No complete Walmart product link could be read. Choose a '
        'screenshot with the full link, or paste it instead.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders without overflow at 320px width and 3x text scale', (
    WidgetTester tester,
  ) async {
    const String candidate = 'https://www.walmart.com/ip/99999999';
    await tester.pumpWidget(
      _harness(
        WalmartLinkActions(
          value: 'https://www.walmart.com/ip/11111111',
          reading: _found(candidate),
          canRead: true,
          onRead: () {},
          onReplace: () {},
          onKeep: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
