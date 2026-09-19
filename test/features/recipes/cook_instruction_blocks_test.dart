import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/features/recipes/cook_instruction_blocks.dart';

/// Regression-first tests for P-HEARTH-COOK-002 R4/A2, written before the UI
/// change lands. `cookInstructionBlocks` is the shared deterministic
/// formatter that will turn a step's stored `text` into readable blocks
/// without ever touching storage, rewriting words, or inventing content.

String _stripWhitespace(String s) => s.replaceAll(RegExp(r'\s+'), '');

void main() {
  group('the supplied chili screenshot text', () {
    const String s1 =
        'Heat 1 tbsp neutral oil in a large skillet over medium-high heat.';
    const String s2 =
        'Add 2 lb 96:4 ground beef and cook, breaking it into crumbles, '
        'until no longer pink, about 6-8 minutes.';
    const String s3 =
        "There's very little fat to render from 96:4, so this step is "
        'really about browning for flavor rather than rendering fat.';
    final String source = '$s1 $s2 $s3';

    test('splits into exactly the three authored sentences', () {
      expect(cookInstructionBlocks(source), <String>[s1, s2, s3]);
    });

    test('preserves every non-whitespace character in order', () {
      final String rejoined = cookInstructionBlocks(source).join();
      expect(_stripWhitespace(rejoined), _stripWhitespace(source));
    });
  });

  group('exact character and order preservation across inputs', () {
    for (final String sample in <String>[
      'One sentence with no follow-up.',
      'Preheat the oven, then wait for it to come up to temperature',
      'Mix 1.5 cups flour with 96:4 lean beef at 6:00, about 6-8 minutes.',
      'Add the eggs.\n\nFold gently.\r\n- Chill for 1 hr.\n- Serve cold.',
    ]) {
      test('"$sample"', () {
        final List<String> blocks = cookInstructionBlocks(sample);
        expect(_stripWhitespace(blocks.join(' ')), _stripWhitespace(sample));
      });
    }
  });

  group('authored line and list boundaries are always kept', () {
    test('multiple blank lines separate blocks even with no punctuation', () {
      expect(
        cookInstructionBlocks('First step here\n\n\nSecond step here'),
        <String>['First step here', 'Second step here'],
      );
    });

    test('CRLF line endings are treated the same as LF', () {
      expect(
        cookInstructionBlocks('Chop the onion.\r\nMince the garlic.'),
        <String>['Chop the onion.', 'Mince the garlic.'],
      );
    });

    test('bullet-style lines are kept as separate, unaltered blocks', () {
      expect(
        cookInstructionBlocks('- Preheat the oven.\n- Mix the batter.'),
        <String>['- Preheat the oven.', '- Mix the batter.'],
      );
    });
  });

  group('conservative punctuation guards protect a single sentence', () {
    test('a plain decimal number is not split', () {
      expect(
        cookInstructionBlocks('Use 3.5 cups of broth for the base.'),
        <String>['Use 3.5 cups of broth for the base.'],
      );
    });

    test('a ratio like 96:4 is untouched', () {
      expect(
        cookInstructionBlocks('Use 96:4 ground beef for less grease.'),
        <String>['Use 96:4 ground beef for less grease.'],
      );
    });

    test('a clock time like 6:00 is untouched', () {
      expect(
        cookInstructionBlocks('Start the roast at 6:00 in the morning.'),
        <String>['Start the roast at 6:00 in the morning.'],
      );
    });

    test('approx. does not split from the rest of the sentence', () {
      expect(
        cookInstructionBlocks('Simmer for approx. 20 minutes, covered.'),
        <String>['Simmer for approx. 20 minutes, covered.'],
      );
    });

    test('tbsp. and tsp. do not split from what follows', () {
      expect(
        cookInstructionBlocks('Add 1 tbsp. oil, then 1 tsp. salt to the pan.'),
        <String>['Add 1 tbsp. oil, then 1 tsp. salt to the pan.'],
      );
    });

    test('e.g. and i.e. stay attached to their sentence', () {
      expect(
        cookInstructionBlocks(
          'Use a firm apple, e.g. Granny Smith, for this pie.',
        ),
        <String>['Use a firm apple, e.g. Granny Smith, for this pie.'],
      );
      expect(
        cookInstructionBlocks(
          'Use a neutral fat, i.e. canola oil, for frying.',
        ),
        <String>['Use a neutral fat, i.e. canola oil, for frying.'],
      );
    });

    test('a multi-letter acronym like U.S. stays intact', () {
      expect(
        cookInstructionBlocks('Follow U.S. customary measurements here.'),
        <String>['Follow U.S. customary measurements here.'],
      );
    });

    test('an unrecognized single initial is still protected', () {
      expect(
        cookInstructionBlocks('Ask J. Smith to taste it before serving.'),
        <String>['Ask J. Smith to taste it before serving.'],
      );
    });

    test('an ellipsis never forces a split', () {
      expect(
        cookInstructionBlocks('Wait... then stir the pot once more.'),
        <String>['Wait... then stir the pot once more.'],
      );
    });

    test('a quoted mid-sentence exclamation is not a boundary', () {
      expect(
        cookInstructionBlocks('She said "Stop!" and pulled the pan off.'),
        <String>['She said "Stop!" and pulled the pan off.'],
      );
    });

    test('a real sentence boundary after a quoted ending still splits', () {
      expect(
        cookInstructionBlocks('She said "Stop!" Then she left the room.'),
        <String>['She said "Stop!"', 'Then she left the room.'],
      );
    });
  });

  group('fallback behaviour', () {
    test('a long unpunctuated sentence stays a single block', () {
      const String prose =
          'Stir constantly to prevent the roux from sticking to the bottom '
          'of the pot while it slowly darkens over low heat';
      expect(cookInstructionBlocks(prose), <String>[prose]);
    });

    test('whitespace-only text produces no blocks', () {
      expect(cookInstructionBlocks('   \n\t  \r\n  '), <String>[]);
      expect(cookInstructionBlocks(''), <String>[]);
    });

    test('Unicode characters are preserved without being split apart', () {
      const String prose = 'Add crème fraîche and stir until combined.';
      expect(cookInstructionBlocks(prose), <String>[prose]);
    });
  });

  group('commas are never a split point', () {
    test('a comma-joined clause stays one block', () {
      const String prose =
          'Add the beans, stir well, and let the chili simmer for an hour';
      expect(cookInstructionBlocks(prose), <String>[prose]);
    });
  });
}
