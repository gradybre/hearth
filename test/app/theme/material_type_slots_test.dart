import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/app/theme/hearth_typography.dart';

/// Every family Hearth actually ships. Anything else in a resolved text theme
/// arrived from Material's default typography, not from a decision here.
const Set<String> _hearthFamilies = <String>{
  HearthTypography.serif,
  HearthTypography.sans,
};

/// The resolved slot-by-slot text theme, named, as a widget will see it.
///
/// This reads [ThemeData.textTheme] rather than
/// [HearthTypography.materialTextTheme] on purpose: `ThemeData` merges the
/// platform's default typography underneath whatever it is given, so a slot
/// left null here does not stay null — it silently becomes Material's, in
/// Material's font. Asserting before that merge would miss exactly the defect
/// worth catching.
Map<String, TextStyle?> _slots(ThemeData theme) {
  final TextTheme t = theme.textTheme;
  return <String, TextStyle?>{
    'displayLarge': t.displayLarge,
    'displayMedium': t.displayMedium,
    'displaySmall': t.displaySmall,
    'headlineLarge': t.headlineLarge,
    'headlineMedium': t.headlineMedium,
    'headlineSmall': t.headlineSmall,
    'titleLarge': t.titleLarge,
    'titleMedium': t.titleMedium,
    'titleSmall': t.titleSmall,
    'bodyLarge': t.bodyLarge,
    'bodyMedium': t.bodyMedium,
    'bodySmall': t.bodySmall,
    'labelLarge': t.labelLarge,
    'labelMedium': t.labelMedium,
    'labelSmall': t.labelSmall,
  };
}

void main() {
  // Regression: `headlineSmall` was never set, and Material 3 resolves an
  // AlertDialog's title from exactly that slot. So every confirmation title in
  // the app — "Sign out?", "Discard this recipe?" — was drawn in Material's
  // default face while every other label in the app was Fraunces. Nothing
  // about it was visible to a colour or a layout check; only the typeface was
  // wrong.
  //
  // This asserts the requirement (a dialog title is Hearth's serif) through
  // AlertDialog's own resolution, so it keeps holding if Flutter ever moves
  // dialog titles to a different slot.
  group('a dialog title is drawn in Hearth type', () {
    Future<TextStyle?> titleStyle(WidgetTester tester, ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: AlertDialog(
              title: Text('Sign out?'),
              content: Text('You will need to sign in again.'),
            ),
          ),
        ),
      );
      final RichText rendered = tester.widget<RichText>(
        find.descendant(
          of: find.text('Sign out?'),
          matching: find.byType(RichText),
        ),
      );
      return rendered.text.style;
    }

    for (final (String name, ThemeData theme) in <(String, ThemeData)>[
      ('light', HearthTheme.light()),
      ('dark', HearthTheme.dark()),
    ]) {
      testWidgets('in $name', (WidgetTester tester) async {
        final TextStyle? style = await titleStyle(tester, theme);
        expect(
          style?.fontFamily,
          HearthTypography.serif,
          reason:
              'an AlertDialog title in $name resolved to ${style?.fontFamily} '
              '— the design language puts titles in the serif (spec §6.1)',
        );
      });
    }
  });

  // The same defect generalised: a slot left unset is not absent, it is
  // Material's. `headlineSmall` was the one that showed, because a dialog is
  // the stock Material surface this app opens constantly.
  group('no Material type slot falls back to a font Hearth did not choose', () {
    for (final (String name, ThemeData theme) in <(String, ThemeData)>[
      ('light', HearthTheme.light()),
      ('dark', HearthTheme.dark()),
    ]) {
      test('in $name', () {
        _slots(theme).forEach((String slot, TextStyle? style) {
          expect(
            style?.fontFamily,
            isIn(_hearthFamilies),
            reason:
                '$slot resolved to ${style?.fontFamily}: it is unset in '
                'HearthTypography.materialTextTheme, so any stock widget '
                'reading it draws in Material default type',
          );
        });
      });
    }
  });
}
