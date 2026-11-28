import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app says "Favorites", not "Favourites" (CLAUDE.md, §6.1).
///
/// Hearth's own prose — comments, doc comments, test names, this sentence —
/// is written the way its author speaks. What a *user* reads is American,
/// and the two had drifted apart one string at a time: four quoted strings
/// said "Favourite" and five said "Favorite", and after the fibre-to-fiber
/// rename the app was going to say "Fiber" and "Favourites" on adjacent
/// screens.
///
/// So this reads the strings rather than the file. A comment explaining why
/// a colour is chosen is not what anybody sees, and neither is
/// `text_normaliser.dart` or the `favourites` key inside a record somebody's
/// phone has already written to disk — renaming that one would silently
/// empty their dashboard.
void main() {
  /// Words with an American spelling, as whole words so that "instal" does
  /// not find "install" and "analys" does not find "analysis" — which is
  /// spelled the same either side of the Atlantic.
  const List<String> british = <String>[
    'favourite',
    'favourites',
    'favourited',
    'favouriting',
    'colour',
    'colours',
    'coloured',
    'colouring',
    'colourful',
    'flavour',
    'flavours',
    'flavoured',
    'flavouring',
    'behaviour',
    'behaviours',
    'honour',
    'honoured',
    'labour',
    'centre',
    'centres',
    'centred',
    'metre',
    'metres',
    'litre',
    'litres',
    'fibre',
    'fibres',
    'theatre',
    'organise',
    'organised',
    'organising',
    'organisation',
    'realise',
    'realised',
    'realising',
    'recognise',
    'recognised',
    'recognising',
    'customise',
    'customised',
    'customising',
    'normalise',
    'normalised',
    'normalising',
    'prioritise',
    'prioritised',
    'summarise',
    'summarised',
    'utilise',
    'utilised',
    'apologise',
    'apologised',
    'analyse',
    'analysed',
    'analysing',
    'cancelled',
    'cancelling',
    'labelled',
    'labelling',
    'travelled',
    'travelling',
    'modelling',
    'signalling',
    'marvellous',
    'catalogue',
    'catalogues',
    'defence',
    'licence',
    'practise',
    'practised',
    'programme',
    'programmes',
    'grey',
    'greyed',
    'whilst',
    'amongst',
    'aeroplane',
    'storey',
    'tyre',
    'plough',
  ];

  /// Strings that look like displayed text and are not.
  ///
  /// Two kinds, and both are load-bearing.
  ///
  /// **A key somebody's phone has already written.** `favourites` sits
  /// inside the JSON a device stores for its house dashboard. Renaming it
  /// would not be a spelling change — it would be every household's chosen
  /// favourites quietly emptying on the next launch, which is the same
  /// reason a database column is out of scope.
  ///
  /// **Words the app reads rather than writes.** A unit alias, an
  /// ingredient the matcher knows to leave alone, a word that makes a food
  /// name less specific: these are vocabularies for understanding what
  /// somebody typed or what a label says, and every one of them lists both
  /// spellings on purpose. Hearth speaks American and has to understand
  /// British, because people write "1 litre" and "food colouring" and a
  /// jar says what it says.
  const Map<String, Set<String>> allowed = <String, Set<String>>{
    'lib/data/house/ha_selection.dart': <String>{'favourites'},
    'lib/domain/units/unit.dart': <String>{
      'litre',
      'litres',
      'metre',
      'metres',
    },
    'lib/domain/foods/food_concept.dart': <String>{'litre', 'litres'},
    'lib/domain/foods/no_match_rule.dart': <String>{
      'colouring',
      'flavoured',
      'flavour',
    },
    'lib/domain/foods/food_relevance.dart': <String>{
      'flavoured',
      'flavour',
      'coloured',
      'colour',
    },
  };

  final RegExp literal = RegExp("'([^'\\\\\n]*)'|\"([^\"\\\\\n]*)\"");
  final RegExp interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*');

  test('nothing a user reads is spelled the British way', () {
    final List<String> found = <String>[];

    for (final File file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart'))
            .where((File f) => !f.path.endsWith('.g.dart'))
            .where((File f) => !f.path.endsWith('.drift.dart'))) {
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i].trimLeft();
        // Not a string anybody reads: the path to another file, and the
        // line that says what this one is.
        if (line.startsWith('import ') ||
            line.startsWith('export ') ||
            line.startsWith('part ') ||
            line.startsWith('//') ||
            line.startsWith('///')) {
          continue;
        }
        for (final RegExpMatch match in literal.allMatches(lines[i])) {
          final String text = match.group(1) ?? match.group(2) ?? '';
          if (text.endsWith('.dart')) continue;
          final String bare = text.replaceAll(interpolation, ' ').toLowerCase();
          for (final String word in british) {
            if (!RegExp('\\b$word\\b').hasMatch(bare)) continue;
            if (allowed[file.path]?.contains(word) ?? false) continue;
            found.add('${file.path}:${i + 1}  "$text"  ($word)');
          }
        }
      }
    }

    expect(
      found,
      isEmpty,
      reason: 'these are read by somebody using the app:\n${found.join('\n')}',
    );
  });
}
