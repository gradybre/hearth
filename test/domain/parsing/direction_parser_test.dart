import 'package:hearth/domain/parsing/direction_parser.dart';
import 'package:test/test.dart';

List<String> _texts(ParsedDirections d) =>
    d.steps.map((ParsedStep s) => s.text).toList();

void main() {
  group('existing structure is transcribed, not second-guessed', () {
    test('numbered lists keep their steps', () {
      final ParsedDirections d = DirectionParser.parse('''
1. Season the ribs generously
2. Sear them in a heavy pot until browned
3. Lower the heat and add the aromatics
''');
      expect(d.format, DirectionFormat.numbered);
      expect(d.wasInferred, isFalse);
      expect(_texts(d), <String>[
        'Season the ribs generously',
        'Sear them in a heavy pot until browned',
        // Not re-split: the author already said this was one step.
        'Lower the heat and add the aromatics',
      ]);
    });

    test('other numbering styles are recognised', () {
      for (final String input in <String>[
        '1) Season the ribs\n2) Sear the ribs',
        'Step 1: Season the ribs\nStep 2: Sear the ribs',
        '1 - Season the ribs\n2 - Sear the ribs',
      ]) {
        final ParsedDirections d = DirectionParser.parse(input);
        expect(d.format, DirectionFormat.numbered, reason: input);
        expect(_texts(d), <String>['Season the ribs', 'Sear the ribs']);
      }
    });

    test('bulleted lists become numbered steps', () {
      final ParsedDirections d = DirectionParser.parse(
        '- Season the ribs\n• Sear the ribs\n* Serve hot',
      );
      expect(d.format, DirectionFormat.bulleted);
      expect(d.steps.map((ParsedStep s) => s.number), <int>[1, 2, 3]);
      expect(_texts(d).first, 'Season the ribs');
    });

    test('bare line breaks are one step per line', () {
      final ParsedDirections d = DirectionParser.parse(
        'Season the ribs\nSear the ribs\nServe hot',
      );
      expect(d.format, DirectionFormat.lineBreaks);
      expect(_texts(d), hasLength(3));
    });

    test('numbering is renumbered from one and stays sequential', () {
      final ParsedDirections d = DirectionParser.parse(
        '3. Season the ribs\n7. Sear the ribs',
      );
      expect(d.steps.map((ParsedStep s) => s.number), <int>[1, 2]);
    });
  });

  group('prose is split into steps', () {
    test('sentences become steps', () {
      final ParsedDirections d = DirectionParser.parse(
        'Preheat the oven to 325F. Pat the ribs dry. Serve over polenta.',
      );
      expect(d.format, DirectionFormat.prose);
      expect(d.wasInferred, isTrue);
      expect(_texts(d), <String>[
        'Preheat the oven to 325F.',
        'Pat the ribs dry.',
        'Serve over polenta.',
      ]);
    });

    test('a joined instruction becomes two steps', () {
      // The case that prompted this: one sentence, two things to do.
      final ParsedDirections d = DirectionParser.parse(
        'Season the ribs generously and sear them in a heavy pot until '
        'deeply browned on every side.',
      );
      expect(_texts(d), <String>[
        'Season the ribs generously',
        'Sear them in a heavy pot until deeply browned on every side.',
      ]);
    });

    test('the split clause is capitalised as its own step', () {
      final ParsedDirections d = DirectionParser.parse(
        'Lower the heat and add the aromatics.',
      );
      expect(_texts(d).last, startsWith('Add'));
    });

    test('several joined instructions all split', () {
      final ParsedDirections d = DirectionParser.parse(
        'Heat the oil and brown the meat and remove it to a plate.',
      );
      expect(_texts(d), hasLength(3));
    });
  });

  group('conjunction splitting stays conservative', () {
    test('an ingredient list is never split', () {
      final ParsedDirections d = DirectionParser.parse(
        'Add the carrots, celery, and onion to the pot.',
      );
      expect(_texts(d), hasLength(1));
    });

    test('"salt and pepper" survives intact', () {
      final ParsedDirections d = DirectionParser.parse(
        'Season the meat with salt and pepper.',
      );
      expect(_texts(d), hasLength(1));
    });

    test('a one-word tail is not worth its own step', () {
      final ParsedDirections d = DirectionParser.parse('Stir and serve.');
      expect(_texts(d), hasLength(1));
    });

    test('a one-word head is not worth its own step either', () {
      // Regression: this split into "Cover" and "Cook for approx. 3 hr.",
      // and a bare "Cover" is not an instruction anyone needs numbered.
      final ParsedDirections d = DirectionParser.parse(
        'Cover and cook for approx. 3 hr.',
      );
      expect(_texts(d), <String>['Cover and cook for approx. 3 hr.']);
    });

    test(
      'a sentence that does not start with an instruction is left alone',
      () {
        final ParsedDirections d = DirectionParser.parse(
          'The ribs should be tender and the sauce should be glossy.',
        );
        expect(_texts(d), hasLength(1));
      },
    );

    test('splitting can be turned off', () {
      final ParsedDirections d = DirectionParser.parse(
        'Season the ribs and sear them until browned.',
        splitConjunctions: false,
      );
      expect(_texts(d), hasLength(1));
    });
  });

  group('sentence splitting handles recipe punctuation', () {
    test('decimals do not end a sentence', () {
      final ParsedDirections d = DirectionParser.parse(
        'Pour in 1.5 cups of stock. Bring to a simmer.',
      );
      expect(_texts(d), hasLength(2));
      expect(_texts(d).first, contains('1.5 cups'));
    });

    test('abbreviations do not end a sentence mid-measure', () {
      final ParsedDirections d = DirectionParser.parse(
        'Simmer for approx. 20 min. Serve hot.',
      );
      expect(_texts(d), hasLength(2));
      expect(_texts(d).first, contains('approx. 20 min.'));
      expect(_texts(d).last, 'Serve hot.');
    });

    test('a unit abbreviation before a proper noun stays joined', () {
      // "2 tbsp. Dijon mustard" is one measurement, not two steps — the
      // capital letter alone must not be read as a new sentence.
      final ParsedDirections d = DirectionParser.parse(
        'Whisk in 2 tbsp. Dijon mustard until smooth.',
      );
      expect(_texts(d), hasLength(1));
    });
  });

  group('edge cases', () {
    test('empty input yields no steps', () {
      final ParsedDirections d = DirectionParser.parse('   \n  \n');
      expect(d.isEmpty, isTrue);
      expect(d.steps, isEmpty);
    });

    test('blank lines between steps are ignored', () {
      final ParsedDirections d = DirectionParser.parse(
        '1. Season the ribs\n\n\n2. Sear the ribs\n',
      );
      expect(_texts(d), hasLength(2));
    });

    test('a single unnumbered sentence is one step', () {
      final ParsedDirections d = DirectionParser.parse('Serve over polenta.');
      expect(_texts(d), <String>['Serve over polenta.']);
    });
  });
}
