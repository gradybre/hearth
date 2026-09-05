import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/data/adapters/edge_function_recipe_icon.dart';

/// What the function sends back when it has drawn something.
Map<Object?, Object?> envelope(Object? svg) => <Object?, Object?>{'svg': svg};

const String muffin =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">'
    '<path d="M6 12h12l-1 8H7z"/><path d="M8 12a4 4 0 018 0"/>'
    '</svg>';

void main() {
  group('reading what came back', () {
    test('a plain line drawing comes through unchanged', () {
      expect(EdgeFunctionRecipeIcon.iconFrom(envelope(muffin)), muffin);
    });

    test('surrounding whitespace is trimmed, not treated as a rejection', () {
      expect(
        EdgeFunctionRecipeIcon.iconFrom(envelope('\n  $muffin\n')),
        muffin,
      );
    });

    test('no drawing at all is no icon, which is an ordinary answer', () {
      expect(EdgeFunctionRecipeIcon.iconFrom(envelope(null)), isNull);
      expect(EdgeFunctionRecipeIcon.iconFrom(envelope('')), isNull);
      expect(
        EdgeFunctionRecipeIcon.iconFrom(const <Object?, Object?>{}),
        isNull,
      );
    });

    test('a number where markup was promised is no icon', () {
      expect(EdgeFunctionRecipeIcon.iconFrom(envelope(42)), isNull);
    });
  });

  group('the function is not the gate', () {
    // The server does a first pass, but this is what actually stands between
    // model output and something that renders in the app. These are the
    // payloads a compromised or confused function could send; every one of
    // them has to come back as no icon rather than as a broken one.
    const Map<String, String> hostile = <String, String>{
      'a script': '<svg viewBox="0 0 24 24"><script>alert(1)</script></svg>',
      'a foreignObject':
          '<svg viewBox="0 0 24 24"><foreignObject width="4" height="4"/>'
          '</svg>',
      'an external image':
          '<svg viewBox="0 0 24 24"><image href="http://x/y.png"/></svg>',
      'an event handler':
          '<svg viewBox="0 0 24 24" onload="x()"><path d="M1 1L2 2"/></svg>',
      'a data URI':
          '<svg viewBox="0 0 24 24">'
          '<path d="M1 1" fill="url(data:image/png;base64,AA)"/></svg>',
      'prose wrapped round the markup': 'Here you go! $muffin Hope that helps.',
      'markdown fencing the server failed to strip': '```svg\n$muffin\n```',
    };

    hostile.forEach((String what, String payload) {
      test('$what gives no icon', () {
        expect(EdgeFunctionRecipeIcon.iconFrom(envelope(payload)), isNull);
      });
    });

    test('a drawing over the size cap gives no icon', () {
      final StringBuffer buffer = StringBuffer('<svg viewBox="0 0 24 24">');
      while (buffer.length < 5000) {
        buffer.write('<path d="M1 1L2 2C3 3 4 4 5 5"/>');
      }
      buffer.write('</svg>');

      expect(
        EdgeFunctionRecipeIcon.iconFrom(envelope(buffer.toString())),
        isNull,
      );
    });
  });
}
